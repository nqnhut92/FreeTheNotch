// Adapted from Atoll (GPL-3.0-or-later): Quota/CodexQuotaClient.swift
// and Quota/ClaudeQuotaClient.swift (credential payloads and source locations).
// Identity labels mirror CodeNotch (MIT): Sources/Providers/CodexCredentials.swift and ClaudeProfile.swift.

import Foundation

/// Credentials stay in memory for one request; the app never rotates or rewrites shared tokens.
struct AIUsageCredentials: Sendable {
    let accessToken: String
    let accountID: String?
    let expiresAt: Date?
    var identity: Identity? = nil

    struct Identity: Equatable, Sendable {
        let name: String?
        let email: String
        var label: String { name.map { $0 + " · " + email } ?? email }
    }

    /// JWT claims are display labels only; authentication remains the provider's responsibility.
    static func codexIdentity(_ token: String?) -> Identity? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
            let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let email = nonempty(claims["email"] as? String)
        else { return nil }
        return Identity(name: nonempty(claims["name"] as? String), email: email)
    }

    static func claudeIdentity(_ data: Data, matchingOrganization: String? = nil) -> Identity? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let account = root["oauthAccount"] as? [String: Any],
            matchingOrganization == nil || account["organizationUuid"] as? String == matchingOrganization,
            let email = nonempty(account["emailAddress"] as? String)
        else { return nil }
        return Identity(name: nonempty(account["displayName"] as? String), email: email)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    struct KeychainItem: Equatable {
        let service: String
        let account: String?
        let modifiedAt: Date
        let persistentReference: Data?
    }

    /// The freshest item under the account's own service name. Only the default login falls back to other
    /// Claude Code items (a CLAUDE_CONFIG_DIR set in a shell but not in the app), and never to one a profile owns.
    static func claudeItem(
        _ items: [KeychainItem], service: String, fallsBack: Bool, claimedServices: Set<String> = []
    ) -> KeychainItem? {
        let newest = { (candidates: [KeychainItem]) in candidates.max { $0.modifiedAt < $1.modifiedAt } }
        if let exact = newest(items.filter { $0.service == service }) { return exact }
        guard fallsBack else { return nil }
        return newest(
            items.filter { $0.service.hasPrefix("Claude Code-credentials") && !claimedServices.contains($0.service) })
    }

    /// Apple's security tool may return non-ASCII secrets as hexadecimal JSON.
    static func keychainData(_ output: Data) -> Data? {
        var text = String(decoding: output, as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { return Data(text.utf8) }
        guard text.utf8.count.isMultiple(of: 2),
            text.utf8.allSatisfy({
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            })
        else { return nil }
        var data = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<end], radix: 16) else { return nil }
            data.append(byte)
            index = end
        }
        return data
    }

    static func parse(_ data: Data, provider: AIUsageProvider) throws -> AIUsageCredentials {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIUsageError.signIn
        }
        switch provider {
        case .codex:
            guard let tokens = object["tokens"] as? [String: Any],
                let access = tokens["access_token"] as? String, !access.isEmpty
            else { throw AIUsageError.signIn }
            return AIUsageCredentials(
                accessToken: access, accountID: tokens["account_id"] as? String, expiresAt: nil,
                identity: codexIdentity(tokens["id_token"] as? String))
        case .claude:
            guard let oauth = object["claudeAiOauth"] as? [String: Any],
                let access = oauth["accessToken"] as? String, !access.isEmpty
            else { throw AIUsageError.signIn }
            let expires = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            return AIUsageCredentials(accessToken: access, accountID: nil, expiresAt: expires)
        }
    }
}
