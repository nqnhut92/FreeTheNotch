import Foundation

/// How long unpinned clipboard items are kept.
enum ClipboardRetention: String, CaseIterable {
    case keep, onQuit, oneDay, threeDays

    var displayName: String {
        switch self {
        case .keep: return "Keep"
        case .onQuit: return "Clear on quit"
        case .oneDay: return "Delete after 1 day"
        case .threeDays: return "Delete after 3 days"
        }
    }

    /// Age after which an unpinned item expires; nil when age never matters.
    var maximumAge: TimeInterval? {
        let day: TimeInterval = 24 * 60 * 60
        switch self {
        case .keep, .onQuit: return nil
        case .oneDay: return day
        case .threeDays: return 3 * day
        }
    }
}

struct ClipboardItem: Identifiable, Codable {
    let id: UUID
    /// Empty for images.
    let text: String
    let date: Date
    var isPinned: Bool
    /// PNG in `ClipboardHistory.imageDirectory` (Atoll-style: image bytes live
    /// in files, not UserDefaults). Optional so text-only history decodes.
    var imageFileName: String? = nil
    var imageByteCount: Int? = nil

    var isImage: Bool { imageFileName != nil }

    var imageURL: URL? {
        imageFileName.map { ClipboardHistory.imageDirectory.appendingPathComponent($0) }
    }

    var preview: String {
        if isImage {
            let size = ByteCountFormatter.string(fromByteCount: Int64(imageByteCount ?? 0), countStyle: .file)
            return "Image (\(size))"
        }
        let single = text.replacingOccurrences(of: "\n", with: " ")
        return single.count > 140 ? String(single.prefix(140)) + "…" : single
    }
}

/// The history rules, kept free of the pasteboard and of storage.
enum ClipboardHistory {
    static let imageDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FreeTheNotch/Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The item captured last, pinned or not. Pinned items are listed first,
    /// so `items.first` is not necessarily the latest copy.
    static func latest(in items: [ClipboardItem]) -> ClipboardItem? {
        items.max { $0.date < $1.date }
    }

    /// Pinned items first, then at most `limit` unpinned ones, newest first
    /// as they were listed. `dropped` are the unpinned items over the limit.
    static func applyingLimit(
        _ items: [ClipboardItem], limit: Int
    ) -> (kept: [ClipboardItem], dropped: [ClipboardItem]) {
        let pinned = items.filter(\.isPinned)
        let rest = items.filter { !$0.isPinned }
        let keep = max(0, limit)
        return (pinned + rest.prefix(keep), Array(rest.dropFirst(keep)))
    }

    /// Unpinned items older than the retention allows at `now`.
    static func expired(
        _ items: [ClipboardItem], retention: ClipboardRetention, now: Date
    ) -> [ClipboardItem] {
        guard let maximumAge = retention.maximumAge else { return [] }
        let cutoff = now.addingTimeInterval(-maximumAge)
        return items.filter { !$0.isPinned && $0.date < cutoff }
    }
}
