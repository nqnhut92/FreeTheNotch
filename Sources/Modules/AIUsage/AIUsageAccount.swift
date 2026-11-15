import Foundation

/// One usage card: a provider's default login.
struct AIUsageAccount: Hashable, Identifiable, Sendable {
    let provider: AIUsageProvider

    var id: String { provider.rawValue }
    var title: String { provider.title }

    /// The default logins, in provider order.
    static var all: [AIUsageAccount] { AIUsageProvider.allCases.map { AIUsageAccount(provider: $0) } }
}
