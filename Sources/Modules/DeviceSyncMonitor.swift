import AppKit
import Combine
import IOKit.pwr_mgt
import os

/// Watches for an iPhone or iPad syncing with this Mac, for the island's
/// device-sync live activity. macOS has no public sync API; AMPDevicesAgent
/// holds a named sleep assertion for as long as any device syncs, and the
/// public `IOPMCopyAssertionsByProcess` lists it. Which devices sync comes
/// from its log lines (`DeviceSyncLogReader`), their names from
/// `MobileDeviceNames`. No reference equivalent in Atoll or Vorssaint.
@MainActor
final class DeviceSyncMonitor: ObservableObject {
    /// True while a device syncs (or the Settings test runs).
    @Published private(set) var isSyncing = false
    /// The syncing device's name, or the fallback label.
    @Published private(set) var label = DeviceSyncActivity.fallbackLabel
    /// Drawn width of `label`, which sets the island's width.
    @Published private(set) var labelWidth = DeviceSyncMonitor.width(of: DeviceSyncActivity.fallbackLabel)

    /// A sync runs for tens of seconds, so a few seconds' delay is not
    /// seen. Change notifications for single assertions need a private
    /// registration and fire for every app's assertions, which would wake
    /// the app far more often than this.
    private static let pollInterval: Duration = .seconds(3)
    private static let pollTolerance: Duration = .seconds(1)
    private static let testDuration: Duration = .seconds(5)
    /// A device can join the list a moment after its sync starts, so the
    /// name is asked for a few times before the fallback label stays.
    private static let nameLookupAttempts = 6
    private static let nameLookupInterval: Duration = .milliseconds(1500)
    private static let testLabel = "iPhone"

    private let connections = MobileDeviceConnections()
    private let logReader = DeviceSyncLogReader()
    /// Names learned so far, by the device ID the sync log uses.
    private var namesByDeviceID: [String: String] = [:]
    /// The label worked out from the connected devices, used when the log
    /// does not say which device syncs.
    private var guessedLabel = DeviceSyncActivity.fallbackLabel
    /// True once the log has named a device in the running sync.
    private var hasLogReport = false
    private var isDeviceSyncing = false
    private var isTesting = false
    private var pollTask: Task<Void, Never>?
    private var nameTask: Task<Void, Never>?
    private var testTask: Task<Void, Never>?
    private var enabledObserver: AnyCancellable?

    /// Polls only while Settings → Live Activities → Device sync is on.
    func configure(with settings: SettingsStore) {
        enabledObserver = settings.$deviceSyncEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                if isEnabled { self?.startPolling() } else { self?.stopPolling() }
            }
    }

    /// Shows the activity for a few seconds (Settings → Live Activities).
    func showTest() {
        testTask?.cancel()
        isTesting = true
        setLabel(Self.testLabel)
        publish()
        testTask = Task { [weak self] in
            try? await Task.sleep(for: Self.testDuration)
            guard !Task.isCancelled, let self else { return }
            self.isTesting = false
            self.setLabel(DeviceSyncActivity.fallbackLabel)
            if self.isDeviceSyncing { self.refreshLabel() }
            self.publish()
        }
    }

    /// Stops the log stream before the app quits.
    func shutdown() {
        logReader.stop()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        logReader.onChange = { [weak self] in self?.syncingDevicesChanged() }
        Task { [connections] in
            await Task.detached(priority: .utility) { MobileDeviceNames.preload() }.value
            connections.start()
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let syncStart = await Task.detached(priority: .utility) { Self.syncStart() }.value
                guard !Task.isCancelled, let self else { return }
                self.update(syncStart: syncStart)
                try? await Task.sleep(for: Self.pollInterval, tolerance: Self.pollTolerance)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        update(syncStart: nil)
    }

    private func update(syncStart: Date?) {
        let syncing = syncStart != nil
        guard syncing != isDeviceSyncing else { return }
        isDeviceSyncing = syncing
        Logger.modules.notice("[FreeTheNotch] Device sync \(syncing ? "started" : "ended", privacy: .public)")
        if let syncStart {
            guessedLabel = DeviceSyncActivity.fallbackLabel
            hasLogReport = false
            logReader.start(syncStart: syncStart)
            refreshLabel()
            lookUpDevices(syncStart: syncStart)
        } else {
            nameTask?.cancel()
            logReader.stop()
        }
        publish()
    }

    private func publish() {
        let showsSync = DeviceSyncActivity.showsActivity(
            isAssertionHeld: isDeviceSyncing, hasLogReport: hasLogReport,
            syncingDeviceCount: logReader.syncingDeviceIDs.count)
        let shows = showsSync || isTesting
        if shows != isSyncing { isSyncing = shows }
    }

    /// A device started or finished: the label follows, and a device not
    /// seen before gets its name looked up.
    private func syncingDevicesChanged() {
        guard isDeviceSyncing else { return }
        if !logReader.syncingDeviceIDs.isEmpty { hasLogReport = true }
        refreshLabel()
        publish()
        if logReader.syncingDeviceIDs.contains(where: { namesByDeviceID[$0] == nil }) {
            lookUpDevices(syncStart: Date())
        }
    }

    /// The log's answer when it has one (a name, or a count for several
    /// devices), else the guess from the connected devices.
    private func refreshLabel() {
        // The last device has finished: the label stays as it is while
        // the island closes, instead of falling back to the guess.
        guard !isTesting, !(hasLogReport && logReader.syncingDeviceIDs.isEmpty) else { return }
        setLabel(
            DeviceSyncActivity.label(syncingDeviceIDs: logReader.syncingDeviceIDs, namesByDeviceID: namesByDeviceID)
                ?? guessedLabel)
    }

    /// Reads the connected devices' names. The island opens with the
    /// fallback label and takes the name once the device has answered.
    private func lookUpDevices(syncStart: Date) {
        nameTask?.cancel()
        nameTask = Task { [weak self] in
            for attempt in 1...Self.nameLookupAttempts {
                let devices = await Task.detached(priority: .utility) { MobileDeviceNames.connected() }.value
                guard !Task.isCancelled, let self, self.isDeviceSyncing else { return }
                if !devices.isEmpty {
                    self.remember(devices, syncStart: syncStart)
                    self.refreshLabel()
                }
                let isComplete =
                    !devices.isEmpty && self.logReader.syncingDeviceIDs.allSatisfy { self.namesByDeviceID[$0] != nil }
                guard !isComplete, attempt < Self.nameLookupAttempts else { return }
                try? await Task.sleep(for: Self.nameLookupInterval)
            }
        }
    }

    private func remember(_ devices: [MobileDeviceNames.Device], syncStart: Date) {
        for device in devices {
            guard let deviceID = DeviceSyncLog.deviceID(forUDID: device.identifier) else { continue }
            namesByDeviceID[deviceID] = device.name
        }
        let candidates = devices.map { device in
            DeviceSyncActivity.Candidate(
                name: device.name,
                secondsSinceConnection: connections.connectedAt[device.identifier].map {
                    syncStart.timeIntervalSince($0)
                })
        }
        guessedLabel = DeviceSyncActivity.label(candidates: candidates)
    }

    private func setLabel(_ newLabel: String) {
        guard newLabel != label else { return }
        labelWidth = Self.width(of: newLabel)
        label = newLabel
    }

    private static func width(of label: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: DeviceSyncActivity.labelFontSize, weight: .semibold)
        return (label as NSString).size(withAttributes: [.font: font]).width
    }

    /// When the running sync started, or nil when no device syncs.
    private nonisolated static func syncStart() -> Date? {
        var assertionsByProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertionsByProcess) == kIOReturnSuccess,
            let processes = assertionsByProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return nil }
        let now = Date()
        return processes.values.lazy.compactMap { DeviceSyncActivity.syncStart(in: $0, now: now) }.first
    }
}
