import Foundation
import Testing

@Suite struct ClaudeTokenRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// An expired login as read from a credentials file, carrying fields the app does not use.
    private func expiredLogin(refreshToken: String) throws -> AIUsageCredentials {
        let json = """
            {"claudeAiOauth":{"accessToken":"old","refreshToken":"\(refreshToken)","expiresAt":1699999000000,\
            "scopes":["user:inference"],"subscriptionType":"max"},"other":1}
            """
        var login = try AIUsageCredentials.parse(Data(json.utf8), provider: .claude)
        login.oauth?.source = .file(URL(fileURLWithPath: "/fixture/.credentials.json"))
        return login
    }

    private func service(
        sink: ClaudeCredentialSink, loader: @escaping AIUsageService.CredentialLoader
    ) -> (AIUsageService, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        return (AIUsageService(session: session, logRoots: [:], credentialSink: sink, credentials: loader), session)
    }

    @Test func anExpiredLoginIsRefreshedAndTheRotatedPairIsStoredWithTheOtherFieldsIntact() async throws {
        let token = "good-" + UUID().uuidString
        let login = try expiredLogin(refreshToken: token)
        let stored = StoredLogins()
        let sink = ClaudeCredentialSink(canStore: { _ in true }, store: { await stored.add($0) })
        let (service, session) = service(sink: sink) { _, _ in login }
        defer { session.invalidateAndCancel() }
        let snapshot = await service.snapshot(
            AIUsageAccount(provider: .claude), allowPrompt: false, now: now, calendar: .current)
        #expect(snapshot.sessionLimit?.usedPercent == 25)
        #expect(snapshot.quotaMessage == nil)
        let requests = RefreshFixtureProtocol.bodies(containing: token)
        #expect(requests.count == 1)
        let body = try #require(requests.first)
        #expect(body["grant_type"] as? String == "refresh_token")
        #expect(body["client_id"] as? String == "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        let saved = try #require(await stored.logins.first)
        #expect(saved.accessToken == "fixture")
        #expect(saved.expiresAt == now.addingTimeInterval(3600))
        #expect(saved.oauth?.refreshToken == "rotated-" + token)
        let savedRecord = try #require(saved.oauth)
        let raw = try #require(try JSONSerialization.jsonObject(with: savedRecord.raw) as? [String: Any])
        let oauth = try #require(raw["claudeAiOauth"] as? [String: Any])
        #expect(oauth["refreshToken"] as? String == "rotated-" + token)
        #expect(oauth["expiresAt"] as? Int64 == 1_700_003_600_000)
        #expect(oauth["subscriptionType"] as? String == "max")
        #expect((oauth["scopes"] as? [String]) == ["user:inference"])
        #expect(raw["other"] as? Int == 1)
        #expect(saved.oauth?.source == .file(URL(fileURLWithPath: "/fixture/.credentials.json")))
    }

    @Test func aPairClaudeCodeAlreadyRotatedIsUsedWithoutSpendingTheRefreshToken() async throws {
        let token = "good-" + UUID().uuidString
        let login = try expiredLogin(refreshToken: token)
        let rotated = AIUsageCredentials(
            accessToken: "fixture", accountID: nil, expiresAt: now.addingTimeInterval(3600))
        let reads = ReadCounter()
        let stored = StoredLogins()
        let sink = ClaudeCredentialSink(canStore: { _ in true }, store: { await stored.add($0) })
        let (service, session) = service(sink: sink) { _, _ in await reads.next() == 1 ? login : rotated }
        defer { session.invalidateAndCancel() }
        let snapshot = await service.snapshot(
            AIUsageAccount(provider: .claude), allowPrompt: false, now: now, calendar: .current)
        #expect(snapshot.sessionLimit?.usedPercent == 25)
        #expect(RefreshFixtureProtocol.bodies(containing: token).isEmpty)
        #expect(await stored.logins.isEmpty)
    }

    @Test func aLoginThatCannotBeStoredIsNeverRefreshed() async throws {
        let token = "good-" + UUID().uuidString
        let login = try expiredLogin(refreshToken: token)
        let (service, session) = service(sink: ClaudeCredentialSink(canStore: { _ in false }, store: { _ in false })) {
            _, _ in login
        }
        defer { session.invalidateAndCancel() }
        let snapshot = await service.snapshot(
            AIUsageAccount(provider: .claude), allowPrompt: false, now: now, calendar: .current)
        #expect(snapshot.sessionLimit == nil)
        #expect(snapshot.requiresConnection)
        #expect(snapshot.quotaMessage == AIUsageError.claudeSignInInstruction)
        #expect(RefreshFixtureProtocol.bodies(containing: token).isEmpty)
    }

    @Test func aRefusedRefreshStoresNothingAndAsksForSignIn() async throws {
        let token = "bad-" + UUID().uuidString
        let login = try expiredLogin(refreshToken: token)
        let stored = StoredLogins()
        let sink = ClaudeCredentialSink(canStore: { _ in true }, store: { await stored.add($0) })
        let (service, session) = service(sink: sink) { _, _ in login }
        defer { session.invalidateAndCancel() }
        let snapshot = await service.snapshot(
            AIUsageAccount(provider: .claude), allowPrompt: false, now: now, calendar: .current)
        #expect(snapshot.sessionLimit == nil)
        #expect(snapshot.quotaMessage == AIUsageError.claudeSignInInstruction)
        #expect(RefreshFixtureProtocol.bodies(containing: token).count == 1)
        #expect(await stored.logins.isEmpty)
    }

    @Test func rotatedRecordKeepsEverythingButTheTokenPair() throws {
        let raw = Data(#"{"claudeAiOauth":{"accessToken":"a","refreshToken":"r","expiresAt":1,"scopes":["x"]}}"#.utf8)
        let record = ClaudeOAuthRecord(refreshToken: "r", raw: raw, source: .keychain(service: "s", account: "u"))
        let rotated = try #require(record.rotated(accessToken: "a2", refreshToken: "r2", expiresAtMilliseconds: 5))
        #expect(rotated.refreshToken == "r2")
        #expect(rotated.source == .keychain(service: "s", account: "u"))
        let object = try #require(try JSONSerialization.jsonObject(with: rotated.raw) as? [String: Any])
        let oauth = try #require(object["claudeAiOauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "a2")
        #expect(oauth["expiresAt"] as? Int == 5)
        #expect(oauth["scopes"] as? [String] == ["x"])
        #expect(
            ClaudeOAuthRecord(refreshToken: "r", raw: Data("[]".utf8), source: nil).rotated(
                accessToken: "a", refreshToken: "b", expiresAtMilliseconds: 1) == nil)
    }

    @Test func keychainUpdateCommandQuotesValuesAndRefusesUnsafeOrOversizedInput() throws {
        let command = try #require(
            ClaudeKeychainStore.updateCommand(
                service: "Claude Code-credentials", account: "me", secret: #"{"a":"b\c"}"#))
        #expect(
            String(decoding: command, as: UTF8.self)
                == "add-generic-password -U -s \"Claude Code-credentials\" -a \"me\" -w \"{\\\"a\\\":\\\"b\\\\c\\\"}\"\n"
        )
        #expect(ClaudeKeychainStore.updateCommand(service: "s", account: nil, secret: "x") == nil)
        #expect(ClaudeKeychainStore.updateCommand(service: "s", account: "a", secret: "line\nbreak") == nil)
        let oversized = String(repeating: "x", count: ClaudeKeychainStore.maximumCommandBytes)
        #expect(ClaudeKeychainStore.updateCommand(service: "s", account: "a", secret: oversized) == nil)
    }
}

private actor StoredLogins {
    private(set) var logins: [AIUsageCredentials] = []
    func add(_ login: AIUsageCredentials) -> Bool {
        logins.append(login)
        return true
    }
}

private actor ReadCounter {
    private var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}

/// Answers the token endpoint and the usage endpoint; no real network is available. A refresh token starting with
/// "bad" is refused. Request bodies are kept so each test can look for its own unique token.
private final class RefreshFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [[String: Any]] = []

    static func bodies(containing token: String) -> [[String: Any]] {
        lock.withLock { recorded.filter { $0["refresh_token"] as? String == token } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        var status = 200
        let body: String
        switch url.host {
        case "platform.claude.com":
            let object = Self.requestBody(request)
            Self.lock.withLock { Self.recorded.append(object) }
            let token = object["refresh_token"] as? String ?? ""
            if token.hasPrefix("bad") {
                status = 400
                body = #"{"error":"invalid_grant"}"#
            } else {
                body = #"{"access_token":"fixture","refresh_token":"rotated-\#(token)","expires_in":3600}"#
            }
        case "api.anthropic.com":
            body = #"{"five_hour":{"utilization":25,"resets_at":null}}"#
            status = request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture" ? 200 : 401
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func requestBody(_ request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
