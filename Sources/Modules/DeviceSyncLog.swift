import Foundation

/// Reads which devices are syncing from AMPDevicesAgent's unified-log lines
/// ("sync> setting syncInProgress to true for device id 001620963C84401C").
/// The sleep assertion only says that some device syncs; these lines say
/// which, and when each one finishes. No reference equivalent in Atoll or
/// Vorssaint.
enum DeviceSyncLog {
    /// Limits `log show` and `log stream` to the lines parsed here.
    static let predicate = #"process == "AMPDevicesAgent" AND eventMessage CONTAINS "syncInProgress""#

    /// One device starting or finishing its sync.
    struct Event: Equatable {
        /// The device's chip ID as the log prints it: 16 hex digits.
        let deviceID: String
        let isSyncing: Bool
    }

    private static let statePrefix = "setting syncInProgress to "
    private static let deviceInfix = " for device id "
    private static let udidSeparator: Character = "-"

    /// The event a log line reports, or nil for any other line (the tool's
    /// header lines included).
    static func event(in line: String) -> Event? {
        guard let prefix = line.range(of: statePrefix),
            let infix = line.range(of: deviceInfix, range: prefix.upperBound..<line.endIndex)
        else { return nil }
        let isSyncing: Bool
        switch line[prefix.upperBound..<infix.lowerBound] {
        case "true": isSyncing = true
        case "false": isSyncing = false
        default: return nil
        }
        let deviceID = line[infix.upperBound...].prefix(while: \.isHexDigit)
        guard !deviceID.isEmpty else { return nil }
        return Event(deviceID: deviceID.uppercased(), isSyncing: isSyncing)
    }

    static func events(in text: String) -> [Event] {
        text.split(whereSeparator: \.isNewline).compactMap { event(in: String($0)) }
    }

    /// The devices syncing after `events`, in the order they started.
    /// Repeating an event changes nothing, so overlapping reads of the log
    /// can be applied one after the other.
    static func syncingDevices(_ current: [String] = [], applying events: [Event]) -> [String] {
        var devices = current
        for event in events {
            if !event.isSyncing {
                devices.removeAll { $0 == event.deviceID }
            } else if !devices.contains(event.deviceID) {
                devices.append(event.deviceID)
            }
        }
        return devices
    }

    /// The log's device ID for a device with this UDID. Current UDIDs are
    /// "<chip>-<chip ID>"; the older 40-digit ones do not contain it.
    static func deviceID(forUDID udid: String) -> String? {
        guard let separator = udid.lastIndex(of: udidSeparator) else { return nil }
        let deviceID = udid[udid.index(after: separator)...]
        guard !deviceID.isEmpty, deviceID.allSatisfy(\.isHexDigit) else { return nil }
        return deviceID.uppercased()
    }
}
