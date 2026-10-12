// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/UsageProvider.swift,
// Quota/CodexQuotaClient.swift and Quota/ClaudeQuotaClient.swift.

import Foundation

/// Providers supported by the notch's usage page.
enum AIUsageProvider: String, CaseIterable, Identifiable, Sendable {
    case codex, claude
    var id: String { rawValue }
    var title: String { self == .codex ? "Codex" : "Claude" }
}
