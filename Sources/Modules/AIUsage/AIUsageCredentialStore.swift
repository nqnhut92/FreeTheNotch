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

    func load(_ provider: AIUsageProvider, allowPrompt: Bool) throws -> AIUsageCredentials {
        let paths: [URL]
        switch provider {
        case .codex:
            if let directory = environment["CODEX_HOME"], !directory.isEmpty {
                paths = [URL(fileURLWithPath: directory).appendingPathComponent("auth.json")]
            } else {
                paths = [
                    home.appendingPathComponent(".codex/auth.json"),
                    home.appendingPathComponent(".config/codex/auth.json"),
                ]
            }
        case .claude:
            let directory =
                environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".claude")
            paths = [directory.appendingPathComponent(".credentials.json")]
        }
        var expired: AIUsageCredentials?
        for path in paths {
            guard let data = try? Data(contentsOf: path),
                let credentials = try? AIUsageCredentials.parse(data, provider: provider)
            else { continue }
            if let date = credentials.expiresAt, date <= Date() {
                expired = credentials
            } else {
                return withIdentity(credentials, provider: provider)
            }
        }
        let quietContext = LAContext()
        quietContext.interactionNotAllowed = true
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var selectedItem: AIUsageCredentials.KeychainItem?
        if provider == .claude {
            let attributesQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecReturnAttributes as String: true,
                kSecReturnPersistentRef as String: true,
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
                    modifiedAt: attributes[kSecAttrModificationDate as String] as? Date ?? .distantPast,
                    persistentReference: attributes[kSecValuePersistentRef as String] as? Data)
            }
            guard let newest = AIUsageCredentials.newestClaudeItem(candidates) else {
                throw expired == nil ? AIUsageError.signIn : AIUsageError.expired
            }
            selectedItem = newest
            if let reference = newest.persistentReference {
                query[kSecValuePersistentRef as String] = reference
            } else {
                query[kSecAttrService as String] = newest.service
                query[kSecAttrAccount as String] = newest.account
            }
        } else {
            query[kSecAttrService as String] = "Codex Auth"
        }
        if !allowPrompt { query[kSecUseAuthenticationContext as String] = quietContext }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess, allowPrompt, let selectedItem {
            var arguments = ["find-generic-password", "-s", selectedItem.service]
            if let account = selectedItem.account { arguments += ["-a", account] }
            arguments.append("-w")
            if let output = Subprocess.run("/usr/bin/security", arguments: arguments, timeout: 30),
                output.succeeded, let data = AIUsageCredentials.keychainData(output.data)
            {
                return withIdentity(try AIUsageCredentials.parse(data, provider: provider), provider: provider)
            }
        }
        guard status == errSecSuccess, let data = result as? Data else {
            Logger.modules.error("[FreeTheNotch] AI usage: Keychain read failed, status \(status)")
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
                throw AIUsageError.keychainAccess
            }
            throw expired == nil ? AIUsageError.signIn : AIUsageError.expired
        }
        return withIdentity(try AIUsageCredentials.parse(data, provider: provider), provider: provider)
    }
    private func withIdentity(_ credentials: AIUsageCredentials, provider: AIUsageProvider) -> AIUsageCredentials {
        guard provider == .claude, let data = try? Data(contentsOf: home.appendingPathComponent(".claude.json")) else {
            return credentials
        }
        var result = credentials
        result.identity = AIUsageCredentials.claudeIdentity(data)
        return result
    }

}
