import Foundation

/// One warning per provider and quota window; historical cache readings cannot raise new warnings.
struct AIQuotaAlertPolicy {
    struct Alert: Equatable, Sendable {
        enum Window: CaseIterable, Hashable, Sendable {
            case session, week
            var title: String { self == .session ? "Session" : "Week" }
        }
        let provider: AIUsageProvider
        let window: Window
        let usedPercent: Double
    }

    static let threshold = 80.0
    private struct Key: Hashable {
        let provider: AIUsageProvider
        let identity: String
        let window: Alert.Window
    }

    private struct Announcement {
        let reset: Date?
        let at: Date
    }
    private static let resetTolerance: TimeInterval = 120
    private static let maximumSnapshotAge: TimeInterval = 120
    private static let historyRetention: TimeInterval = 14 * 24 * 3600
    static let presentationDuration: TimeInterval = 4
    private var announced: [Key: Announcement] = [:]

    mutating func alerts(provider: AIUsageProvider, snapshot: AIUsageSnapshot, now: Date) -> [Alert] {
        guard !snapshot.isQuotaStale(at: now), snapshot.quotaMessage == nil, !snapshot.requiresConnection,
            (0..<Self.maximumSnapshotAge).contains(now.timeIntervalSince(snapshot.updatedAt))
        else { return [] }
        // Keep a small bounded history even when accounts or reset windows change.
        announced = announced.filter { now.timeIntervalSince($0.value.at) < Self.historyRetention }
        return Alert.Window.allCases.compactMap { window in
            let limit = window == .session ? snapshot.sessionLimit : snapshot.weekLimit
            guard let limit, limit.usedPercent.isFinite, limit.usedPercent >= Self.threshold,
                limit.resetsAt.map({ $0 > now }) ?? true
            else { return nil }
            let identity = snapshot.identity?.label ?? ""
            let key = Key(provider: provider, identity: identity, window: window)
            if let previous = announced[key] {
                guard let reset = limit.resetsAt, let oldReset = previous.reset,
                    abs(reset.timeIntervalSince(oldReset)) > Self.resetTolerance
                else { return nil }
            }
            // Relative reset timestamps include request/clock jitter; that is not a new quota window.
            announced[key] = Announcement(reset: limit.resetsAt, at: now)
            return Alert(provider: provider, window: window, usedPercent: min(100, limit.usedPercent))
        }
    }
}
