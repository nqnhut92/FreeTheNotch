// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/UsageProvider.swift,
// Quota/CodexQuotaClient.swift and Quota/ClaudeQuotaClient.swift.

import Foundation

/// Quota, identity and local token totals, with independent freshness timestamps.
struct AIUsageSnapshot: Equatable, Sendable {
    var sessionLimit: AIUsageLimit?
    var weekLimit: AIUsageLimit?
    var today = AIUsageTotals()
    var week = AIUsageTotals()
    var hasLocalLogs = false
    var identity: AIUsageCredentials.Identity?
    var quotaSource: String?
    var quotaCapturedAt: Date?
    var requiresConnection = false
    var quotaMessage: String?
    var logsMessage: String?
    var updatedAt = Date.distantPast

    private static let quotaFreshnessInterval: TimeInterval = 30 * 60

    /// Older Desktop readings stay visible, with their original capture time.
    func isQuotaStale(at now: Date) -> Bool {
        guard let quotaCapturedAt else { return false }
        return now.timeIntervalSince(quotaCapturedAt) >= Self.quotaFreshnessInterval
    }
}
