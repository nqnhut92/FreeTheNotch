import Foundation
import Testing

struct AIActivityTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func codexChildCompletionDoesNotCompleteTheTurn() throws {
        let data = Data(
            """
            {"type":"event_msg","payload":{"type":"task_started"}}
            {"type":"event_msg","payload":{"type":"item_completed"}}
            """.utf8)
        #expect(AIActivityParser.codex(data)?.state == .working)
        #expect(
            AIActivityParser.codex(
                data + Data("\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}".utf8))?.state
                == .completed)
        #expect(
            AIActivityParser.codex(
                data + Data("\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_aborted\"}}".utf8))?.state
                == .stopped)
    }

    @Test(arguments: ["end_turn", "stop_sequence", "max_tokens", "tool_use"])
    func claudeOnlyExplicitEndReasonsCompleteAParentTurn(_ reason: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["type": "assistant", "message": ["stop_reason": reason]])
        #expect(AIActivityParser.claude(data)?.state == (reason == "tool_use" ? .working : .completed))
        let bookkeeping = Data(
            "\n{\"type\":\"custom-title\"}\n{\"type\":\"assistant\",\"isSidechain\":true,\"message\":{\"stop_reason\":\"end_turn\"}}"
                .utf8)
        #expect(AIActivityParser.claude(data + bookkeeping) == AIActivityParser.claude(data))
    }

    @Test func claudeInterruptionAndPartialAssistantNeverPretendCompletion() {
        #expect(
            AIActivityParser.claude(
                Data("{\"type\":\"user\",\"message\":{\"content\":\"[Request interrupted by user]\"}}".utf8))?.state
                == .stopped)
        #expect(
            AIActivityParser.claude(Data("{\"type\":\"assistant\",\"message\":{\"stop_reason\":null}}".utf8)) == nil)
    }

    @Test func silenceIsNotCompletionAndCompletedActivityExpires() {
        let busy = AIActivity(id: "x", provider: .codex, state: .working, changedAt: Self.now.addingTimeInterval(-3600))
        #expect(busy.isVisible(at: Self.now, isLive: true))
        #expect(!busy.isVisible(at: Self.now, isLive: false))
        let done = AIActivity(id: "x", provider: .codex, state: .completed, changedAt: Self.now)
        #expect(done.isVisible(at: Self.now.addingTimeInterval(3.9), isLive: false))
        #expect(!done.isVisible(at: Self.now.addingTimeInterval(4), isLive: true))
    }

    @Test func registryReportsPermissionWaitAndUsesStableTimestamp() throws {
        let record = try #require(
            AIActivityParser.claudeRegistry(
                Data("{\"pid\":123,\"sessionId\":\"s\",\"tempo\":\"blocked\",\"statusUpdatedAt\":1800000000000}".utf8),
                fallback: .distantPast))
        #expect(record.pid == 123)
        #expect(record.activity.id == "claude.s")
        #expect(record.activity.state == .waiting)
        #expect(record.activity.changedAt == Self.now)
        #expect(
            AIActivityParser.claudeRegistry(Data("{\"pid\":-1,\"status\":\"busy\"}".utf8), fallback: Self.now) == nil)
    }

    @Test func waitingRegistryTakesPriorityOverAnActiveTempo() throws {
        let data = Data("{\"pid\":123,\"sessionId\":\"s\",\"tempo\":\"active\",\"status\":\"waiting\"}".utf8)
        #expect(AIActivityParser.claudeRegistry(data, fallback: Self.now)?.activity.state == .waiting)
    }

    @Test func completedClaudeTurnCannotBeResurrectedByAnOlderBusyRegistry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projects = root.appendingPathComponent("projects")
        let registry = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = projects.appendingPathComponent("s.jsonl")
        let timestamp = Self.now.formatted(.iso8601)
        try Data(
            "{\"type\":\"assistant\",\"timestamp\":\"\(timestamp)\",\"message\":{\"stop_reason\":\"end_turn\"}}\n".utf8
        ).write(to: transcript)
        try FileManager.default.setAttributes([.modificationDate: Self.now], ofItemAtPath: transcript.path)
        let record = registry.appendingPathComponent("123.json")
        func writeRegistry(_ status: String, at date: Date) throws {
            let json: [String: Any] = [
                "pid": 123, "sessionId": "s", "status": status, "statusUpdatedAt": date.timeIntervalSince1970 * 1000,
            ]
            try JSONSerialization.data(withJSONObject: json).write(to: record)
        }
        try writeRegistry("busy", at: Self.now.addingTimeInterval(-60))
        let reader = AIActivityReader(roots: [.claude: projects], claudeSessions: registry)
        let completed = await reader.read(providers: [.claude], now: Self.now, processLiveness: { _, _ in true })
        #expect(completed.first?.state == .completed)
        let expired = await reader.read(
            providers: [.claude], now: Self.now.addingTimeInterval(5), processLiveness: { _, _ in true })
        #expect(expired.isEmpty)
        try writeRegistry("busy", at: Self.now.addingTimeInterval(6))
        let resumed = await reader.read(
            providers: [.claude], now: Self.now.addingTimeInterval(6), processLiveness: { _, _ in true })
        #expect(resumed.first?.state == .working)
        try writeRegistry("idle", at: Self.now.addingTimeInterval(7))
        let idle = await reader.read(
            providers: [.claude], now: Self.now.addingTimeInterval(7), processLiveness: { _, _ in true })
        #expect(idle.isEmpty)
    }

    @Test func providerDirectoriesRespectInjectedProfiles() {
        let home = URL(fileURLWithPath: "/fixture/home")
        let defaults = AIUsageDirectories(home: home, environment: [:])
        #expect(defaults.logRoots[.codex]?.path == "/fixture/home/.codex/sessions")
        #expect(defaults.claudeSessions.path == "/fixture/home/.claude/sessions")
        let custom = AIUsageDirectories(
            home: home, environment: ["CODEX_HOME": "/profiles/codex", "CLAUDE_CONFIG_DIR": "/profiles/claude"])
        #expect(custom.logRoots[.codex]?.path == "/profiles/codex/sessions")
        #expect(custom.logRoots[.claude]?.path == "/profiles/claude/projects")
    }

    @Test func aLongCodexTurnWithoutLifecycleInItsTailStaysVisibleWhileOpen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("long.jsonl")
        try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\"}}\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Self.now.addingTimeInterval(-60)], ofItemAtPath: url.path)
        let reader = AIActivityReader(roots: [.codex: root], claudeSessions: root.appendingPathComponent("none"))
        let found = await reader.read(providers: [.codex], now: Self.now, openCodexFiles: [url])
        #expect(found.first?.state == .working)
        let stopped = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_aborted\"}}\n"
        try Data(stopped.utf8).write(to: url)
        let aborted = await reader.read(providers: [.codex], now: Self.now, openCodexFiles: [url])
        #expect(aborted.isEmpty)
    }

    @Test(arguments: [0, -1])
    func tailRejectsNonpositiveBounds(_ bytes: Int) {
        #expect(AIActivityReader.tail(URL(fileURLWithPath: "/fixture/unused"), bytes: bytes) == nil)
    }

    @Test func boundedTailIgnoresTruncatedPrefix() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let record = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}\n"
        try Data((String(repeating: "x", count: 4096) + "\n" + record).utf8).write(to: url)
        let data = try #require(AIActivityReader.tail(url, bytes: 1024))
        #expect(data.count <= 1024)
        #expect(AIActivityParser.codex(data)?.state == .completed)
    }

    @Test func readerKeepsAnOpenQuietTurnAndDropsItWhenItsProcessCloses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("turn.jsonl")
        let timestamp = Self.now.addingTimeInterval(-60).formatted(.iso8601)
        try Data(
            "{\"type\":\"event_msg\",\"timestamp\":\"\(timestamp)\",\"payload\":{\"type\":\"task_started\"}}\n".utf8
        ).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Self.now.addingTimeInterval(-60)], ofItemAtPath: url.path)
        let reader = AIActivityReader(roots: [.codex: root], claudeSessions: root.appendingPathComponent("registry"))
        let open = await reader.read(providers: [.codex], now: Self.now, openCodexFiles: [url])
        #expect(open.count == 1)
        #expect(open.first?.state == .working)
        let closed = await reader.read(providers: [.codex], now: Self.now, openCodexFiles: [])
        #expect(closed.isEmpty)
    }
}
