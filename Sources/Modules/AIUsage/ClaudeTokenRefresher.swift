// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/Quota/ClaudeQuotaClient.swift (validAccessToken).

import Foundation

/// Exchanges an expired Claude Code OAuth pair for a new one, as Claude Code itself does.
struct ClaudeTokenRefresher: Sendable {
    let session: URLSession

    private struct Response: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
    }

    private static let endpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let scope = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
    private static let timeout: TimeInterval = 20

    /// The credentials with a new token pair, or nil when there is no refresh token or the refresh is refused.
    /// The refresh invalidates the old pair, so the caller must store the result where the old one was read.
    func refreshed(_ credentials: AIUsageCredentials, now: Date) async -> AIUsageCredentials? {
        guard let record = credentials.oauth else { return nil }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": record.refreshToken,
            "client_id": Self.clientID,
            "scope": Self.scope,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let reply = try? decoder.decode(Response.self, from: data) else { return nil }
        let expiresAt = now.addingTimeInterval(TimeInterval(reply.expiresIn))
        guard
            let rotated = record.rotated(
                accessToken: reply.accessToken, refreshToken: reply.refreshToken,
                expiresAtMilliseconds: Int64(expiresAt.timeIntervalSince1970 * 1000))
        else { return nil }
        var result = credentials
        result = AIUsageCredentials(
            accessToken: reply.accessToken, accountID: credentials.accountID, expiresAt: expiresAt,
            identity: credentials.identity, oauth: rotated)
        return result
    }
}
