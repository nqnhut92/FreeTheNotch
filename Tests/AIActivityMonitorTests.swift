import Foundation
import Testing

@MainActor
struct AIActivityMonitorTests {
    @Test func cancellingAPreviewRestoresRealActivityAfterReenabling() async throws {
        let suite = "AIActivityMonitorTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let real = AIActivity(id: "real", provider: .codex, state: .working, changedAt: Date())
        let monitor = AIActivityMonitor(settings: settings, pollingInterval: .milliseconds(5)) { providers, _ in
            providers.contains(.codex) ? [real] : []
        }
        monitor.triggerTest(provider: .codex)
        #expect(monitor.activities.first?.id == "preview.codex")
        settings.aiLiveActivitiesEnabled = false
        #expect(monitor.activities.isEmpty)
        settings.aiLiveActivitiesEnabled = true
        for _ in 0..<20 where monitor.activities != [real] { try await Task.sleep(for: .milliseconds(5)) }
        #expect(monitor.activities == [real])
        settings.codexUsageEnabled = false
        for _ in 0..<20 where !monitor.activities.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(monitor.activities.isEmpty)
        settings.aiLiveActivitiesEnabled = false
    }
}
