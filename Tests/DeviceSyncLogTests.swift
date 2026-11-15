import Foundation
import Testing

/// DeviceSyncLog against lines in the form `log show --style compact` prints
/// for AMPDevicesAgent.
struct DeviceSyncLogTests {
    private typealias Event = DeviceSyncLog.Event

    private static let phone = "001620963C84401C"
    private static let tablet = "000930C42185001C"

    private static func line(_ time: String, _ state: String, _ device: String) -> String {
        "2026-11-15 \(time) Df AMPDevicesAgent[3687:5de2] [com.apple.AMPDevicesAgent:device] "
            + "sync> setting syncInProgress to \(state) for device id \(device)"
    }

    @Test func aLineReportsADeviceStartingOrFinishing() {
        #expect(
            DeviceSyncLog.event(in: Self.line("14:59:07.485", "true", Self.tablet))
                == Event(deviceID: Self.tablet, isSyncing: true))
        #expect(
            DeviceSyncLog.event(in: Self.line("14:59:42.456", "false", Self.tablet))
                == Event(deviceID: Self.tablet, isSyncing: false))
        #expect(
            DeviceSyncLog.event(in: "sync> setting syncInProgress to true for device id 000930c42185001c (retry)")
                == Event(deviceID: Self.tablet, isSyncing: true))
    }

    @Test(arguments: [
        "",
        #"Filtering the log data using "process == "AMPDevicesAgent" AND composedMessage CONTAINS "syncInProgress"""#,
        "Timestamp               Ty Process[PID:TID]",
        "2026-11-15 14:59:07.484 Df AMPDevicesAgent[3687:14d47be] pm) sys-prevent      1 1 'syncing'",
        "sync> setting syncInProgress to maybe for device id 000930C42185001C",
        "sync> setting syncInProgress to true for device id ",
        "sync> setting syncInProgress to true",
    ])
    func otherLinesReportNothing(line: String) {
        #expect(DeviceSyncLog.event(in: line) == nil)
    }

    /// Two syncs that overlap: the tablet starts, the phone joins, the
    /// tablet finishes first.
    @Test func overlappingSyncsAreFollowedDeviceByDevice() {
        let text = [
            "Timestamp               Ty Process[PID:TID]",
            Self.line("14:59:07.485", "true", Self.tablet),
            Self.line("14:59:23.249", "true", Self.phone),
            Self.line("14:59:42.456", "false", Self.tablet),
            Self.line("14:59:56.165", "false", Self.phone),
        ].joined(separator: "\n")
        let events = DeviceSyncLog.events(in: text)
        #expect(events.count == 4)
        #expect(DeviceSyncLog.syncingDevices(applying: Array(events.prefix(1))) == [Self.tablet])
        #expect(DeviceSyncLog.syncingDevices(applying: Array(events.prefix(2))) == [Self.tablet, Self.phone])
        #expect(DeviceSyncLog.syncingDevices(applying: Array(events.prefix(3))) == [Self.phone])
        #expect(DeviceSyncLog.syncingDevices(applying: events).isEmpty)
    }

    /// The catch-up read and the stream overlap, so events arrive twice.
    @Test func applyingTheSameEventsAgainChangesNothing() {
        let started = [Event(deviceID: Self.tablet, isSyncing: true), Event(deviceID: Self.phone, isSyncing: true)]
        let finished = [Event(deviceID: Self.tablet, isSyncing: false)]
        let once = DeviceSyncLog.syncingDevices(applying: started + finished)
        #expect(once == [Self.phone])
        #expect(DeviceSyncLog.syncingDevices(once, applying: finished) == [Self.phone])
        #expect(DeviceSyncLog.syncingDevices(once, applying: [started[1]] + finished) == [Self.phone])
        #expect(
            DeviceSyncLog.syncingDevices([Self.phone], applying: [Event(deviceID: "FFFF", isSyncing: false)]) == [
                Self.phone
            ])
    }

    @Test(
        arguments: [
            ("00008140-001620963C84401C", "001620963C84401C"),
            ("00008140-001620963c84401c", "001620963C84401C"),
            // A 40-digit UDID does not contain the chip ID.
            ("c7a6eb7081410e6cfe9189573f0a768b643ce19b", nil),
            ("00008140-", nil),
            ("00008140-not-hex", nil),
            ("", nil),
        ] as [(String, String?)])
    func theLogsDeviceIDIsTheEndOfTheUDID(udid: String, expected: String?) {
        #expect(DeviceSyncLog.deviceID(forUDID: udid) == expected)
    }
}
