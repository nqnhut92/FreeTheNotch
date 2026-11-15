// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/Quota/KeychainReader.swift,
// CodexQuotaClient.swift and ClaudeQuotaClient.swift (file-first lookup and freshest Claude item).
// Persistent-reference selection mirrors CodeNotch (MIT): Sources/Providers/ClaudeCredentials.swift.

import Foundation
import LocalAuthentication
import Security
import os

/// Reads the existing login on a background actor, without modifying provider credentials.
actor AIUsageCredentialStore {
    private let home: URL
    private let environment: [String: String]

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.home = home
        self.environment = environment
    }

    func load(_ account: AIUsageAccount, allowPrompt: Bool) throws -> AIUsageCredentials {
        let provider = account.provider
        return try load(
            provider, paths: defaultPaths(provider), accountFile: home.appendingPathComponent(".claude.json"),
            claudeService: AIUsageCredentials.keychainService(configDirectory: environment["CLAUDE_CONFIG_DIR"]),
            allowPrompt: allowPrompt)
    }

    private func defaultPaths(_ provider: AIUsageProvider) -> [URL] {
        switch provider {
        case .codex:
            if let directory = environment["CODEX_HOME"], !directory.isEmpty {
                return [URL(fileURLWithPath: directory).appendingPathComponent("auth.json")]
            }
            return [
                home.appendingPathComponent(".codex/auth.json"),
                home.appendingPathComponent(".config/codex/auth.json"),
            ]
        case .claude:
            let directory =
                environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".claude")
            return [directory.appendingPathComponent(".credentials.json")]
        }
    }

    private func load(
        _ provider: AIUsageProvider, paths: [URL], accountFile: URL, claudeService: String,
        allowPrompt: Bool
    ) throws -> AIUsageCredentials {
        var expired: AIUsageCredentials?
        for path in paths {
            guard let data = try? Data(contentsOf: path),
                var credentials = try? AIUsageCredentials.parse(data, provider: provider)
            else { continue }
            credentials.oauth?.source = .file(path)
            if let date = credentials.expiresAt, date <= Date() {
                expired = credentials
            } else {
                return withIdentity(credentials, provider: provider, accountFile: accountFile)
            }
        }
        let quietContext = LAContext()
        quietContext.interactionNotAllowed = true
        guard provider == .claude else {
            return try codexKeychainLogin(allowPrompt: allowPrompt, quietContext: quietContext, expired: expired)
        }
        let attributesQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationContext as String: quietContext,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributesQuery as CFDictionary, &result)
        guard status == errSecSuccess else {
            Logger.modules.error("[FreeTheNotch] AI usage: Claude Keychain enumeration failed, status \(status)")
            throw status == errSecInteractionNotAllowed ? AIUsageError.keychainAccess : AIUsageError.signIn
        }
        let items = (result as? [[String: Any]]) ?? (result as? [String: Any]).map { [$0] } ?? []
        let candidates = items.compactMap { attributes -> AIUsageCredentials.KeychainItem? in
            guard let service = attributes[kSecAttrService as String] as? String else { return nil }
            return AIUsageCredentials.KeychainItem(
                service: service, account: attributes[kSecAttrAccount as String] as? String,
                modifiedAt: attributes[kSecAttrModificationDate as String] as? Date ?? .distantPast)
        }
        guard let newest = AIUsageCredentials.claudeItem(candidates, service: claudeService) else {
            // The file's expired login can still be refreshed when the Keychain has nothing newer.
            if let expired { return withIdentity(expired, provider: provider, accountFile: accountFile) }
            throw AIUsageError.signIn
        }
        // The secret is read through Apple's `security` tool, the identity Claude Code created the item with and the
        // one that rewrites it on a token refresh. A rewrite resets the item's partition list to that tool alone, so
        // a native read by this app would be refused (and need another "Always Allow") after every refresh.
        guard let data = Self.securityToolSecret(service: newest.service, account: newest.account) else {
            if let expired { return withIdentity(expired, provider: provider, accountFile: accountFile) }
            throw AIUsageError.keychainAccess
        }
        return withIdentity(
            try parsed(data, provider: provider, item: newest), provider: provider, accountFile: accountFile)
    }

    private static let securityToolTimeout: TimeInterval = 15

    private static func securityToolSecret(service: String, account: String?) -> Data? {
        var arguments = ["find-generic-password", "-s", service]
        if let account { arguments += ["-a", account] }
        arguments.append("-w")
        guard let output = Subprocess.run("/usr/bin/security", arguments: arguments, timeout: securityToolTimeout),
            output.succeeded
        else { return nil }
        return AIUsageCredentials.keychainData(output.data)
    }

    /// Codex keeps its login in a Keychain item this app only reads; a prompt is allowed only for an explicit Connect.
    private func codexKeychainLogin(
        allowPrompt: Bool, quietContext: LAContext, expired: AIUsageCredentials?
    ) throws -> AIUsageCredentials {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Codex Auth",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowPrompt { query[kSecUseAuthenticationContext as String] = quietContext }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            Logger.modules.error("[FreeTheNotch] AI usage: Keychain read failed, status \(status)")
            if let expired { return expired }
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
                throw AIUsageError.keychainAccess
            }
            throw AIUsageError.signIn
        }
        return try AIUsageCredentials.parse(data, provider: .codex)
    }

    /// A Keychain secret, remembering which item it came from so a refreshed pair can go back to it.
    private func parsed(
        _ data: Data, provider: AIUsageProvider, item: AIUsageCredentials.KeychainItem?
    ) throws -> AIUsageCredentials {
        var credentials = try AIUsageCredentials.parse(data, provider: provider)
        if let item { credentials.oauth?.source = .keychain(service: item.service, account: item.account) }
        return credentials
    }

    private func withIdentity(
        _ credentials: AIUsageCredentials, provider: AIUsageProvider, accountFile: URL
    ) -> AIUsageCredentials {
        guard provider == .claude, let data = try? Data(contentsOf: accountFile) else {
            return credentials
        }
        var result = credentials
        result.identity = AIUsageCredentials.claudeIdentity(data)
        return result
    }

}
