import Foundation

/// One usage card: a provider's default login, or a Claude profile from claude-multiprofile.
struct AIUsageAccount: Hashable, Identifiable, Sendable {
    let provider: AIUsageProvider
    let profile: ClaudeProfile?

    init(provider: AIUsageProvider, profile: ClaudeProfile? = nil) {
        self.provider = provider
        self.profile = profile
    }

    var id: String { profile.map { provider.rawValue + "." + $0.name } ?? provider.rawValue }
    var title: String { profile.map { provider.title + " · " + $0.name } ?? provider.title }

    /// The default logins first, in provider order, then each Claude profile in registry order.
    static func all(profiles: [ClaudeProfile]) -> [AIUsageAccount] {
        AIUsageProvider.allCases.map { AIUsageAccount(provider: $0) }
            + profiles.map { AIUsageAccount(provider: .claude, profile: $0) }
    }
}
