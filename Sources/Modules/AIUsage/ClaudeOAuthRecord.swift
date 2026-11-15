// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/Quota/ClaudeQuotaClient.swift (Credentials).

import Foundation

/// What a token refresh needs to know about a Claude Code login: the refresh token, the credential JSON exactly
/// as read, and where it came from so a rotated pair can go back to the same place.
struct ClaudeOAuthRecord: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case file(URL)
        case keychain(service: String, account: String?)
    }

    let refreshToken: String
    /// Claude Code keeps more under `claudeAiOauth` than the tokens (scopes, subscription type, rate-limit tier,
    /// refresh-token expiry); a write-back hands all of it back untouched.
    let raw: Data
    var source: Source?

    /// The same record carrying a new token pair, with `raw` edited to match. Nil when `raw` is not the expected JSON.
    func rotated(accessToken: String, refreshToken: String, expiresAtMilliseconds: Int64) -> ClaudeOAuthRecord? {
        guard var object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
            var oauth = object["claudeAiOauth"] as? [String: Any]
        else { return nil }
        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        oauth["expiresAt"] = expiresAtMilliseconds
        object["claudeAiOauth"] = oauth
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return ClaudeOAuthRecord(refreshToken: refreshToken, raw: data, source: source)
    }
}
