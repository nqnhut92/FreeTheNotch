// Adapted from CodeNotch (MIT): Sources/Sessions/CodexActivityMonitor.swift,
// ClaudeSessionRecord.swift and ClaudeTranscript.swift. See THIRD_PARTY_NOTICES.md.

import Foundation

/// A local agent turn, distinct from the account's five-hour quota window.
struct AIActivity: Equatable, Sendable, Identifiable {
    enum State: Equatable, Sendable { case working, waiting, completed, idle, stopped }
    let id: String
    let provider: AIUsageProvider
    let state: State
    let changedAt: Date

    static let completionDuration: TimeInterval = 4
    static let recentWriteInterval: TimeInterval = 8
    private static let clockSkewTolerance: TimeInterval = 5

    /// Silence never implies successful completion; only explicit end events do.
    func isVisible(at now: Date, isLive: Bool) -> Bool {
        let age = now.timeIntervalSince(changedAt)
        guard age >= -Self.clockSkewTolerance, state != .stopped, state != .idle else { return false }
        return state == .completed ? age < Self.completionDuration : isLive
    }
}
