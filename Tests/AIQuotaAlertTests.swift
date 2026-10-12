import Foundation
import Testing

struct AIQuotaAlertTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func thresholdIsInclusiveAndEachWindowWarnsOnce() {
        var policy = AIQuotaAlertPolicy()
        var snapshot = AIUsageSnapshot()
        snapshot.updatedAt = Self.now
        snapshot.sessionLimit = AIUsageLimit(usedPercent: 79.99, resetsAt: Self.now.addingTimeInterval(3600))
        #expect(policy.alerts(provider: .codex, snapshot: snapshot, now: Self.now).isEmpty)
        snapshot.sessionLimit = AIUsageLimit(usedPercent: 80, resetsAt: Self.now.addingTimeInterval(3600))
        snapshot.weekLimit = AIUsageLimit(usedPercent: 90, resetsAt: Self.now.addingTimeInterval(86400))
        let alerts = policy.alerts(provider: .codex, snapshot: snapshot, now: Self.now)
        #expect(alerts.map(\.window) == [.session, .week])
        #expect(policy.alerts(provider: .codex, snapshot: snapshot, now: Self.now).isEmpty)
        snapshot.sessionLimit = AIUsageLimit(usedPercent: 82, resetsAt: Self.now.addingTimeInterval(3601))
        #expect(policy.alerts(provider: .codex, snapshot: snapshot, now: Self.now).isEmpty)
        #expect(policy.alerts(provider: .claude, snapshot: snapshot, now: Self.now).count == 2)
        snapshot.sessionLimit = AIUsageLimit(usedPercent: 81, resetsAt: Self.now.addingTimeInterval(7200))
        #expect(policy.alerts(provider: .codex, snapshot: snapshot, now: Self.now).map(\.window) == [.session])
    }

    @Test func futureDatedFetchDoesNotRaiseAWarning() {
        var policy = AIQuotaAlertPolicy()
        var snapshot = AIUsageSnapshot()
        snapshot.updatedAt = Self.now.addingTimeInterval(1)
        snapshot.sessionLimit = AIUsageLimit(usedPercent: 90, resetsAt: Self.now.addingTimeInterval(3600))
        #expect(policy.alerts(provider: .codex, snapshot: snapshot, now: Self.now).isEmpty)
    }

    @Test func oldCacheExpiredResetAndFailedFetchNeverWarn() {
        var policy = AIQuotaAlertPolicy()
        var snapshot = AIUsageSnapshot()
        snapshot.updatedAt = Self.now
        snapshot.sessionLimit = AIUsageLimit(usedPercent: 95, resetsAt: Self.now.addingTimeInterval(3600))
        snapshot.quotaCapturedAt = Self.now.addingTimeInterval(-1800)
        #expect(policy.alerts(provider: .claude, snapshot: snapshot, now: Self.now).isEmpty)
        snapshot.quotaCapturedAt = Self.now
        snapshot.quotaMessage = "Unavailable"
        #expect(policy.alerts(provider: .claude, snapshot: snapshot, now: Self.now).isEmpty)
        snapshot.quotaMessage = nil
        snapshot.sessionLimit = AIUsageLimit(usedPercent: 95, resetsAt: Self.now)
        #expect(policy.alerts(provider: .claude, snapshot: snapshot, now: Self.now).isEmpty)
        snapshot.sessionLimit = AIUsageLimit(usedPercent: .nan, resetsAt: nil)
        #expect(policy.alerts(provider: .claude, snapshot: snapshot, now: Self.now).isEmpty)
        snapshot.sessionLimit = AIUsageLimit(usedPercent: 80, resetsAt: nil)
        #expect(policy.alerts(provider: .claude, snapshot: snapshot, now: Self.now).count == 1)
        #expect(policy.alerts(provider: .claude, snapshot: snapshot, now: Self.now).isEmpty)
    }
}
