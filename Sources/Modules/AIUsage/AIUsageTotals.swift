// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/UsageProvider.swift,
// Quota/CodexQuotaClient.swift and Quota/ClaudeQuotaClient.swift.

import Foundation

/// Local API-equivalent usage, not a charge against a subscription.
struct AIUsageTotals: Equatable, Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var estimatedCostUSD = 0.0
    var hasUnpricedModel = false
    var totalTokens: Int { inputTokens + outputTokens }
}
