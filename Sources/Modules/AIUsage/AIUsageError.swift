// Adapted from Atoll (GPL-3.0-or-later): Quota/CodexQuotaClient.swift
// and Quota/ClaudeQuotaClient.swift (credential payloads and source locations).
// Identity labels mirror CodeNotch (MIT): Sources/Providers/CodexCredentials.swift and ClaudeProfile.swift.

import Foundation

/// User-facing failures from provider login and quota requests.
enum AIUsageError: LocalizedError, Equatable {
    case signIn, keychainAccess, expired, network, invalidResponse, unavailable
    var errorDescription: String? {
        switch self {
        case .signIn: return "Sign in to the provider's app or CLI, then refresh."
        case .keychainAccess: return "Connect to allow access to the saved login in Keychain."
        case .expired: return "Open the provider's app or CLI to renew its login, then refresh."
        case .network: return "Could not refresh quota. Try again."
        case .invalidResponse: return "The provider returned an unsupported usage response."
        case .unavailable: return "Quota is unavailable for this account."
        }
    }
}
