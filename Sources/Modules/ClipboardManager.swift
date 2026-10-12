import AppKit
import Foundation
import os

/// Clipboard history. Passwords / concealed pasteboard types are never
/// captured. Retention is configurable (keep / clear on quit / 1 day /
/// 3 days); no encryption — the pasteboard is already user-local.
@MainActor
final class ClipboardManager: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private weak var settings: SettingsStore?
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.concealed-type")
    private let storeKey = "ftn.clipboardHistory"
    /// Images bigger than this are skipped (keeps the history folder sane).
    private let maxImageBytes = 25 * 1024 * 1024
    /// The item copied or restored last, which a new copy is compared with.
    private var lastItemID: UUID?

    /// What is on the pasteboard according to the history: the item copied
    /// or restored last, else the newest one (pinned items come first in
    /// `items`, so that is not always `items.first`).
    private var previousItem: ClipboardItem? {
        items.first { $0.id == lastItemID } ?? ClipboardHistory.latest(in: items)
    }

    // MARK: Lifecycle

    func configure(with settings: SettingsStore) {
        self.settings = settings
        loadPersisted()
        applyRetention()
    }

    func startMonitoring() {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func handleAppQuit() {
        if settings?.clipboardRetention == .onQuit {
            removeItems { _ in true }
        }
        persist()
    }

    // MARK: Polling

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard settings?.clipboardEnabled == true else { return }

        // Never capture passwords / concealed content (1Password etc.).
        if pb.types?.contains(concealedType) == true { return }

        if let png = currentImagePNG(pb) {
            captureImage(png)
            return
        }

        guard let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return }
        // The same text copied twice in a row is one item.
        if let previous = previousItem, !previous.isImage, previous.text == text { return }

        let item = ClipboardItem(id: UUID(), text: text, date: Date(), isPinned: false)
        items.insert(item, at: 0)
        lastItemID = item.id
        enforceLimit()
        persist()
    }

    /// Atoll's order: image files copied in Finder first, then raw image
    /// data with no file URLs (screenshots, "Copy Image"). Returns PNG bytes.
    private func currentImagePNG(_ pb: NSPasteboard) -> Data? {
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL],
            !urls.isEmpty
        {
            let exts: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]
            // The size check comes first: reading a huge file only to drop it
            // would stall the main thread.
            guard let url = urls.first(where: { exts.contains($0.pathExtension.lowercased()) }),
                let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxImageBytes,
                let data = try? Data(contentsOf: url)
            else { return nil }
            return Self.pngData(from: data)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")] {
            if let data = pb.data(forType: type) {
                return type == .png ? data : Self.pngData(from: data)
            }
        }
        return nil
    }

    private static func pngData(from data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func captureImage(_ png: Data) {
        guard png.count <= maxImageBytes else { return }
        // The same image copied twice in a row is one item.
        if let last = previousItem?.imageURL, (try? Data(contentsOf: last)) == png { return }
        let id = UUID()
        let fileName = "clipboard_image_\(id.uuidString).png"
        do {
            try png.write(to: ClipboardHistory.imageDirectory.appendingPathComponent(fileName))
        } catch {
            Logger.modules.error(
                "[FreeTheNotch] clipboard image save failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        items.insert(
            ClipboardItem(
                id: id, text: "", date: Date(), isPinned: false,
                imageFileName: fileName, imageByteCount: png.count), at: 0)
        lastItemID = id
        enforceLimit()
        persist()
    }

    // MARK: Actions

    func restore(_ item: ClipboardItem) {
        let imageData = item.imageURL.flatMap { try? Data(contentsOf: $0) }
        if item.isImage && imageData == nil { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let imageData {
            pb.setData(imageData, forType: .png)
        } else {
            pb.setString(item.text, forType: .string)
        }
        // Our own write must not be re-captured as a new item; move it to the top instead.
        lastChangeCount = pb.changeCount
        lastItemID = item.id
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            let it = items.remove(at: i)
            items.insert(it, at: 0)
            persist()
        }
    }

    func togglePin(_ item: ClipboardItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].isPinned.toggle()
        persist()
    }

    func delete(_ item: ClipboardItem) {
        removeItems { $0.id == item.id }
        persist()
    }

    func clear() {
        removeItems { !$0.isPinned }
        persist()
    }

    /// Removes matching items and their image files.
    private func removeItems(where shouldRemove: (ClipboardItem) -> Bool) {
        for item in items where shouldRemove(item) {
            if let url = item.imageURL { try? FileManager.default.removeItem(at: url) }
        }
        items.removeAll(where: shouldRemove)
    }

    // MARK: Limit + retention

    private func enforceLimit() {
        guard let settings else { return }
        let (kept, dropped) = ClipboardHistory.applyingLimit(items, limit: settings.clipboardLimit)
        for item in dropped {
            if let url = item.imageURL { try? FileManager.default.removeItem(at: url) }
        }
        items = kept
    }

    private func applyRetention() {
        guard let retention = settings?.clipboardRetention else { return }
        let expired = Set(ClipboardHistory.expired(items, retention: retention, now: Date()).map(\.id))
        if !expired.isEmpty {
            removeItems { expired.contains($0.id) }
        }
    }

    // MARK: Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
            let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else { return }
        // Drop images whose file is gone.
        items = decoded.filter { item in
            item.imageURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? true
        }
    }
}
