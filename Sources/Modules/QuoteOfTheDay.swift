// Quote of the Day: no reference equivalent. Online quotes
// from the ZenQuotes API (zenquotes.io, free tier: attribution with a link
// back is required, 5 requests per 30 s per IP; one request returns 50
// quotes, so this makes about one request per 50 quotes shown).

import Combine
import Foundation
import SwiftUI
import os

/// The quote on Home. A new one every `quoteIntervalHours`, or on click.
/// Online quotes are fetched in batches of 50 and cached in UserDefaults;
/// offline or on failure the built-in list fills in.
@MainActor
final class QuoteStore: ObservableObject {
    static let shared = QuoteStore()

    @Published private(set) var current: Quote

    /// Hours between quotes that Settings offers.
    static let intervals = [1, 2, 4, 8, 24]

    private let defaults = UserDefaults.standard
    private var batch: [Quote]
    private var shownAt: Date
    private var timer: Timer?
    private var isFetching = false
    private var lastFetchAttempt: Date?
    private var cancellables = Set<AnyCancellable>()
    private weak var settings: SettingsStore?

    private static let endpoint = URL(string: "https://zenquotes.io/api/quotes")!

    private init() {
        let decoder = JSONDecoder()
        current =
            defaults.data(forKey: "ftn.quoteCurrent").flatMap { try? decoder.decode(Quote.self, from: $0) }
            ?? Quote.builtIn[0]
        batch = defaults.data(forKey: "ftn.quoteBatch").flatMap { try? decoder.decode([Quote].self, from: $0) } ?? []
        shownAt = defaults.object(forKey: "ftn.quoteShownAt") as? Date ?? .distantPast
    }

    func configure(with settings: SettingsStore) {
        self.settings = settings
        settings.$homeQuote
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in on ? self?.start() : self?.stop() }
            .store(in: &cancellables)
        // A new source or interval takes effect at once.
        Publishers.CombineLatest(
            settings.$quoteSourceRaw.removeDuplicates(),
            settings.$quoteIntervalHours.removeDuplicates()
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self, settings.homeQuote else { return }
            self.next()
        }
        .store(in: &cancellables)
    }

    private var source: QuoteSource {
        settings.flatMap { QuoteSource(rawValue: $0.quoteSourceRaw) } ?? .online
    }

    private var interval: TimeInterval {
        TimeInterval(settings?.quoteIntervalHours ?? 24) * 3600
    }

    private func start() {
        refreshIfDue()
        guard timer == nil else { return }
        // A date compare every 5 minutes; the network only when a batch runs out.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfDue() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when Home shows, and by the timer.
    func refreshIfDue() {
        guard settings?.homeQuote == true else { return }
        if Date().timeIntervalSince(shownAt) >= interval { next() }
    }

    /// Shows the next quote now (also the click on the quote).
    func next() {
        switch source {
        case .builtIn:
            show(Quote.randomBuiltIn(excluding: current))
        case .online:
            if let quote = popBatch() {
                show(quote)
            } else {
                fetchBatch()
            }
        }
    }

    private func popBatch() -> Quote? {
        guard !batch.isEmpty else { return nil }
        let quote = batch.removeFirst()
        defaults.set(try? JSONEncoder().encode(batch), forKey: "ftn.quoteBatch")
        return quote
    }

    private func show(_ quote: Quote) {
        current = quote
        shownAt = Date()
        defaults.set(try? JSONEncoder().encode(quote), forKey: "ftn.quoteCurrent")
        defaults.set(shownAt, forKey: "ftn.quoteShownAt")
    }

    /// One request for 50 quotes, off the main thread. On failure the
    /// built-in list fills in, and the next try waits a minute (free tier:
    /// 5 requests per 30 s).
    private func fetchBatch() {
        if isFetching { return }
        if let last = lastFetchAttempt, Date().timeIntervalSince(last) < 60 {
            show(Quote.randomBuiltIn(excluding: current))
            return
        }
        isFetching = true
        lastFetchAttempt = Date()
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            let quotes = data.map(Quote.parseZenQuotes) ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                if quotes.isEmpty {
                    Logger.modules.error(
                        "[FreeTheNotch] Quote fetch failed: \(error?.localizedDescription ?? "no quotes", privacy: .public)"
                    )
                    self.show(Quote.randomBuiltIn(excluding: self.current))
                    return
                }
                self.batch = quotes
                self.next()
            }
        }.resume()
    }
}

/// One line at the top of Home. Click for the next quote.
struct QuoteOfTheDayView: View {
    @ObservedObject private var store = QuoteStore.shared

    var body: some View {
        let quote = store.current
        HStack(spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.yellow)
            Text(quote.text)
                .font(.system(size: 13, weight: .medium))
                .italic()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text("\u{2014} \(quote.author)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { store.next() } }
        .id(quote.text)
        .transition(.opacity)
        .help("Click for another quote")
        .onAppear { store.refreshIfDue() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
