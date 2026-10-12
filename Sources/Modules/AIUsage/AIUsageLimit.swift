// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/UsageProvider.swift,
// Quota/CodexQuotaClient.swift and Quota/ClaudeQuotaClient.swift.

import Foundation

/// An account-wide quota window, independent of local token totals.
struct AIUsageLimit: Equatable, Sendable {
    let usedPercent: Double
    let resetsAt: Date?
    var fraction: Double { min(1, max(0, usedPercent / 100)) }
}
