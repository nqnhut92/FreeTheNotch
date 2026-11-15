// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/UsageProvider.swift,
// Quota/CodexQuotaClient.swift and Quota/ClaudeQuotaClient.swift.

import Foundation

/// Quota, identity and local token totals.
struct AIUsageSnapshot: Equatable, Sendable {
    var sessionLimit: AIUsageLimit?
    var weekLimit: AIUsageLimit?
    var today = AIUsageTotals()
    var week = AIUsageTotals()
    var hasLocalLogs = false
    var identity: AIUsageCredentials.Identity?
    var requiresConnection = false
    var quotaMessage: String?
    var logsMessage: String?
    var updatedAt = Date.distantPast
}
