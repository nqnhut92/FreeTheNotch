// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/Quota/ClaudeQuotaClient.swift (writeBack).

import Foundation
import os

/// Where a refreshed Claude Code credential is stored, injected so tests never touch the real Keychain or `~/.claude`.
struct ClaudeCredentialSink: Sendable {
    /// Whether a rotated pair could be put back. A refresh spends the refresh token, so it is not attempted when the
    /// result could not be stored: Claude Code would be left with a dead pair and logged out.
    var canStore: @Sendable (AIUsageCredentials) -> Bool
    var store: @Sendable (AIUsageCredentials) async -> Bool

    /// Never refreshes.
    static let none = ClaudeCredentialSink(canStore: { _ in false }, store: { _ in false })

    static let live = ClaudeCredentialSink(
        canStore: { credentials in
            guard let record = credentials.oauth, let source = record.source else { return false }
            switch source {
            case .file: return true
            case .keychain(let service, let account):
                guard let compact = compactSecret(record.raw) else { return false }
                return ClaudeKeychainStore.updateCommand(service: service, account: account, secret: compact)
                    .map { $0.count + keychainCommandMargin <= ClaudeKeychainStore.maximumCommandBytes } ?? false
            }
        },
        store: { credentials in
            guard let record = credentials.oauth, let source = record.source else { return false }
            return await Task.detached { () -> Bool in
                switch source {
                case .file(let url):
                    do {
                        try record.raw.write(to: url, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                        return true
                    } catch {
                        Logger.modules.error("[FreeTheNotch] AI usage: could not store refreshed Claude login file")
                        return false
                    }
                case .keychain(let service, let account):
                    guard let secret = compactSecret(record.raw) else { return false }
                    if let status = ClaudeKeychainStore.update(service: service, account: account, secret: secret) {
                        Logger.modules.error(
                            "[FreeTheNotch] AI usage: could not store refreshed Claude login in Keychain, status \(status)"
                        )
                        return false
                    }
                    return true
                }
            }.value
        })

    /// Headroom for the longer tokens a refresh can return.
    private static let keychainCommandMargin = 512

    private static func compactSecret(_ raw: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: raw),
            let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
