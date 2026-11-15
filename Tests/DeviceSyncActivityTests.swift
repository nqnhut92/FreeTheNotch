import Foundation
import Testing

/// DeviceSyncActivity: recognising the sync assertion, choosing the label
/// and sizing the island.
struct DeviceSyncActivityTests {
    private static func assertion(named name: String) -> [String: Any] {
        ["AssertName": name, "AssertType": "PreventUserIdleSystemSleep", "AssertPID": NSNumber(value: 3687)]
    }

    @Test func theSyncingAssertionGivesTheSyncsStart() {
        let start = Date(timeIntervalSince1970: 1_794_000_000)
        var syncing = Self.assertion(named: "com.apple.AMPDevicesAgent.syncing")
        syncing["AssertStartWhen"] = start
        let assertions = [Self.assertion(named: "com.apple.AMPDevicesAgent.common"), syncing]
        #expect(DeviceSyncActivity.syncStart(in: assertions, now: start.addingTimeInterval(30)) == start)
    }

    @Test func aSyncingAssertionWithoutADateStartsNow() {
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        let assertions = [Self.assertion(named: "com.apple.AMPDevicesAgent.syncing")]
        #expect(DeviceSyncActivity.syncStart(in: assertions, now: now) == now)
    }

    @Test(
        arguments: [
            [],
            [["AssertName": "com.apple.AMPDevicesAgent.common"]],
            [["AssertName": "com.example.app.syncing"]],
            [["AssertType": "PreventUserIdleSystemSleep"]],
            [["AssertName": NSNumber(value: 1)]],
        ] as [[[String: Any]]])
    func otherAssertionsAreNotASync(assertions: [[String: Any]]) {
        #expect(DeviceSyncActivity.syncStart(in: assertions, now: Date(timeIntervalSince1970: 0)) == nil)
    }

    @Test(
        arguments: [
            // The log says which devices sync: one is named, several are counted.
            (["001620963C84401C"], "Work iPhone"),
            (["000930C42185001C"], "Family iPad"),
            (["000930C42185001C", "001620963C84401C"], "Syncing 2 devices"),
            (["000930C42185001C", "001620963C84401C", "00021D063EDB401E"], "Syncing 3 devices"),
            // Nothing from the log, or a device whose name is not known: no answer.
            ([], nil),
            (["00021D063EDB401E"], nil),
            (["0004AAAA00000000"], nil),
        ] as [([String], String?)])
    func theLogNamesOneDeviceAndCountsSeveral(syncing: [String], expected: String?) {
        let names = [
            "001620963C84401C": "Work iPhone", "000930C42185001C": " Family iPad ", "0004AAAA00000000": "  ",
        ]
        #expect(DeviceSyncActivity.label(syncingDeviceIDs: syncing, namesByDeviceID: names) == expected)
    }

    @Test(
        arguments: [
            // assertion held, log has named a device, devices syncing, shows
            (false, false, 0, false),
            (false, true, 1, false),
            // Before the log has said anything, the assertion alone decides.
            (true, false, 0, true),
            (true, true, 1, true),
            (true, true, 2, true),
            // The last device finished while the assertion is still held.
            (true, true, 0, false),
        ] as [(Bool, Bool, Int, Bool)])
    func theActivityEndsWhenTheLogSaysTheLastDeviceFinished(
        isAssertionHeld: Bool, hasLogReport: Bool, count: Int, expected: Bool
    ) {
        #expect(
            DeviceSyncActivity.showsActivity(
                isAssertionHeld: isAssertionHeld, hasLogReport: hasLogReport, syncingDeviceCount: count) == expected)
    }

    private typealias Candidate = DeviceSyncActivity.Candidate

    @Test(
        arguments: [
            // One device connected: it is the one syncing, however long ago it joined.
            ([Candidate(name: "Work iPhone", secondsSinceConnection: 3600)], "Work iPhone"),
            ([Candidate(name: "  Work iPhone \n", secondsSinceConnection: nil)], "Work iPhone"),
            ([], "Syncing"),
            ([Candidate(name: "", secondsSinceConnection: 1)], "Syncing"),
            // Two devices: the one that joined within 20 s of the sync starting.
            (
                [
                    Candidate(name: "Work iPhone", secondsSinceConnection: 46),
                    Candidate(name: "Family iPad", secondsSinceConnection: 2),
                ], "Family iPad"
            ),
            (
                [
                    Candidate(name: "Work iPhone", secondsSinceConnection: 20),
                    Candidate(name: "Family iPad", secondsSinceConnection: 21),
                ], "Work iPhone"
            ),
            // Joined after the sync was noticed.
            (
                [
                    Candidate(name: "Work iPhone", secondsSinceConnection: 900),
                    Candidate(name: "Family iPad", secondsSinceConnection: -1.5),
                ], "Family iPad"
            ),
            // Nothing tells them apart: both old, both new, or unknown.
            (
                [
                    Candidate(name: "Work iPhone", secondsSinceConnection: 900),
                    Candidate(name: "Family iPad", secondsSinceConnection: 300),
                ], "Syncing"
            ),
            (
                [
                    Candidate(name: "Work iPhone", secondsSinceConnection: 4),
                    Candidate(name: "Family iPad", secondsSinceConnection: 2),
                ], "Syncing"
            ),
            (
                [
                    Candidate(name: "Work iPhone", secondsSinceConnection: nil),
                    Candidate(name: "Family iPad", secondsSinceConnection: nil),
                ], "Syncing"
            ),
        ] as [([DeviceSyncActivity.Candidate], String)])
    func theLabelNamesTheDeviceThatIsSyncing(candidates: [DeviceSyncActivity.Candidate], expected: String) {
        #expect(DeviceSyncActivity.label(candidates: candidates) == expected)
    }

    @Test(
        arguments: [
            // label width, ear width: label + 20 inset, at least 62, at most 170
            (0, 62),
            (42, 62),
            (42.5, 63),
            (100, 120),
            (150, 170),
            (400, 170),
        ] as [(CGFloat, CGFloat)])
    func theEarFitsTheNameWithinItsLimits(labelWidth: CGFloat, expected: CGFloat) {
        #expect(DeviceSyncActivity.earWidth(labelWidth: labelWidth) == expected)
    }

    @Test func theIslandGrowsByOneEarOnEachSideOfTheCamera() {
        // 185 + 2 × (100 + 20)
        #expect(DeviceSyncActivity.islandWidth(notchWidth: 185, labelWidth: 100) == 425)
        // A long name is cut to the 170 pt ear, less the 20 pt inset.
        #expect(DeviceSyncActivity.labelSlotWidth(labelWidth: 400) == 150)
        #expect(DeviceSyncActivity.islandWidth(notchWidth: 185, labelWidth: 400) == 525)
    }
}
