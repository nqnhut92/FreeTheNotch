import SwiftUI

extension SettingsView {
    private static let zenQuotesURL = URL(string: "https://zenquotes.io/")!
    /// ZenQuotes returns this many quotes per request (QuoteStore).
    private static let zenQuotesBatchSize = 50

    var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageTitle("Appearance")
            SettingsGroupHeader("Notch")
            SettingsCard {
                SettingsToggleRow(
                    "Liquid Glass",
                    description: "The open notch fades to 55% at the bottom",
                    isOn: $settings.liquidGlass, showDivider: false)
            }
            SettingsGroupHeader("Calendar")
            SettingsCard {
                SettingsToggleRow(
                    "Lunar date",
                    description:
                        "Vietnamese lunar calendar under the date, e.g. \(LunarCalendar.lunarDate(for: Date()).displayText)",
                    isOn: $settings.showLunarDate, showDivider: false)
            }
            notchPagesSection
        }
    }

    var skinsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageTitle("Skins")
            SkinSettingsSection()
        }
    }

    /// Reorder the open notch's page icons: drag a row by its ≡ handle;
    /// rows move live while dragging.
    private var notchPagesSection: some View {
        let order = settings.notchTabOrder
        return VStack(alignment: .leading, spacing: 0) {
            SettingsGroupHeader("Notch Tabs")
            SettingsCard {
                HStack {
                    notchTabLabel(.home, isFirst: true)
                    Spacer()
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).help("Home is always shown first")
                }
                .padding(16)
                Divider().padding(.leading, 16)
                ForEach(order.filter { $0 != .home }) { page in
                    notchTabRow(page, isFirst: page == settings.visibleNotchTabs.first)
                        .onDrop(
                            of: [.text],
                            delegate: ReorderDropDelegate(
                                target: page, dragging: $draggingPage, order: $settings.notchTabOrder))
                    Divider().padding(.leading, 16)
                }
                SettingsToggleRow(
                    "Batteries on Home",
                    description: "Mac and Bluetooth battery strip under the player and calendar",
                    isOn: $settings.homeBatteryStrip)
                SettingsToggleRow(
                    "Quote of the Day",
                    description: "A short quote at the top of Home. Click it for another one.",
                    isOn: $settings.homeQuote)
                quoteRows
                    .disabled(!settings.homeQuote)
                    .opacity(settings.homeQuote ? 1 : 0.5)
                SettingsRow("Reset order", showDivider: false) {
                    Button("Reset") { settings.notchTabOrderRaw = "" }
                        .disabled(settings.notchTabOrder == NotchPage.allCases)
                }
            }
        }
    }

    private var quoteRows: some View {
        Group {
            SettingsRow("Quote source", description: quoteSourceDescription) {
                Picker("", selection: $settings.quoteSource) {
                    ForEach(QuoteSource.allCases, id: \.self) { source in
                        Text(source.title).tag(source)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            if settings.quoteSource == .online {
                SettingsRow("Attribution") {
                    // ZenQuotes' free tier requires this link.
                    Link("Inspirational quotes provided by ZenQuotes API", destination: Self.zenQuotesURL)
                        .font(.system(size: 12))
                }
            }
            SettingsRow("New quote every") {
                Picker("", selection: $settings.quoteIntervalHours) {
                    ForEach(QuoteStore.intervals, id: \.self) { hours in
                        Text(Self.intervalTitle(hours: hours)).tag(hours)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }
        }
    }

    private var quoteSourceDescription: String {
        switch settings.quoteSource {
        case .online:
            return
                "Downloads \(Self.zenQuotesBatchSize) quotes at a time from zenquotes.io; the built-in list fills in when offline"
        case .builtIn:
            return "\(Quote.builtIn.count) quotes from old authors and proverbs, no network"
        }
    }

    private static func intervalTitle(hours: Int) -> String {
        switch hours {
        case 1: return "1 hour"
        case 24: return "1 day"
        default: return "\(hours) hours"
        }
    }

    private func notchTabRow(_ page: NotchPage, isFirst: Bool) -> some View {
        ReorderRow(payload: page.rawValue) {
            notchTabLabel(page, isFirst: isFirst)
        } trailing: {
            Toggle(
                "Show " + page.title,
                isOn: Binding(
                    get: { settings.isNotchTabVisible(page) },
                    set: { settings.setNotchTabVisible(page, isVisible: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(page == .aiUsage && settings.enabledAIUsageProviders.isEmpty)
        } dragPreview: {
            notchTabLabel(page, isFirst: false)
        } onDragStart: {
            draggingPage = page
        }
    }

    private func notchTabLabel(_ page: NotchPage, isFirst: Bool) -> some View {
        HStack(spacing: 12) {
            NotchPageIcon(page: page, size: 13, weight: .medium)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
            Text(page.title)
                .font(.system(size: 14))
            if isFirst {
                Text("Opens first")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
