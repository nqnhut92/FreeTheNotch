import CoreGraphics
import Foundation

/// Rules for the device-sync live activity: how a sync is recognised, what
/// the island says and how wide it gets. No reference equivalent in Atoll or
/// Vorssaint.
enum DeviceSyncActivity {
    /// Name of the sleep assertion AMPDevicesAgent (Finder's device sync)
    /// holds from the start of a sync to its end.
    static let syncAssertionName = "com.apple.AMPDevicesAgent.syncing"
    /// `kIOPMAssertionNameKey`, the assertion dictionary's name entry.
    static let assertionNameKey = "AssertName"
    /// When the assertion was taken: the sync's start.
    static let assertionStartKey = "AssertStartWhen"
    /// Shown when the device's name is not known.
    static let fallbackLabel = "Syncing"

    static let labelFontSize: CGFloat = 11
    /// The ear never gets wider than this; a longer name is truncated.
    static let maximumEarWidth: CGFloat = 170
    /// Room beside the name: the island's edge padding and a gap to the camera.
    static let earInset: CGFloat = 20

    /// When the sync these power assertions show started, or nil when none
    /// of them is the device-sync one. `now` stands in for a missing date.
    static func syncStart(in assertions: [[String: Any]], now: Date) -> Date? {
        guard let assertion = assertions.first(where: { $0[assertionNameKey] as? String == syncAssertionName })
        else { return nil }
        return assertion[assertionStartKey] as? Date ?? now
    }

    /// Whether the activity shows. The assertion outlives the last device's
    /// sync by a second or two, so once the log has named devices, the
    /// activity ends when the log says none is left.
    static func showsActivity(isAssertionHeld: Bool, hasLogReport: Bool, syncingDeviceCount: Int) -> Bool {
        guard isAssertionHeld else { return false }
        return !hasLogReport || syncingDeviceCount > 0
    }

    /// What the island says when the log tells which devices sync: the
    /// device's name for one, a count for several. Nil when the log told
    /// nothing or the one device's name is not known; `label(candidates:)`
    /// decides then.
    static func label(syncingDeviceIDs: [String], namesByDeviceID: [String: String]) -> String? {
        guard let first = syncingDeviceIDs.first else { return nil }
        guard syncingDeviceIDs.count == 1 else {
            return "Syncing \(syncingDeviceIDs.count.formatted()) devices"
        }
        let name = namesByDeviceID[first]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// A device that just connected is taken to be the one syncing:
    /// Finder wakes a Wi-Fi device right before it syncs it.
    static let recentConnectionWindow: TimeInterval = 20

    /// A connected device that may be the one syncing.
    struct Candidate: Equatable {
        let name: String
        /// How long before the sync started it connected; nil when unknown.
        let secondsSinceConnection: TimeInterval?
    }

    /// The syncing device's name. The assertion does not say which device
    /// syncs: with one device connected it is that one; with several, the
    /// only one that connected within `recentConnectionWindow` of the sync
    /// starting. Otherwise the island does not guess.
    static func label(candidates: [Candidate]) -> String {
        let named = candidates.compactMap { candidate -> Candidate? in
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return Candidate(name: name, secondsSinceConnection: candidate.secondsSinceConnection)
        }
        if named.count == 1 { return named[0].name }
        let recent = named.filter { candidate in
            candidate.secondsSinceConnection.map { $0 <= recentConnectionWindow } ?? false
        }
        return recent.count == 1 ? recent[0].name : fallbackLabel
    }

    /// Width of each ear beside the camera: wide enough for the name, never
    /// narrower than the other live activities' ear.
    static func earWidth(labelWidth: CGFloat) -> CGFloat {
        min(max(labelWidth.rounded(.up) + earInset, DisplayGeometry.liveActivityEar), maximumEarWidth)
    }

    /// Width the name itself gets inside its ear.
    static func labelSlotWidth(labelWidth: CGFloat) -> CGFloat {
        earWidth(labelWidth: labelWidth) - earInset
    }

    static func islandWidth(notchWidth: CGFloat, labelWidth: CGFloat) -> CGFloat {
        notchWidth + 2 * earWidth(labelWidth: labelWidth)
    }
}
