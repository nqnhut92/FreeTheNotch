import Foundation
import os

/// Follows `DeviceSyncLog`'s lines for as long as a sync runs: one
/// `log show` for what was written since the sync started, then a
/// `log stream` for what follows. Nothing runs between syncs. Without access
/// to the log (the tool needs an administrator account) it reports no
/// devices and the activity falls back to its other rules.
@MainActor
final class DeviceSyncLogReader {
    /// Called on the main actor when the set of syncing devices changes.
    var onChange: (() -> Void)?
    /// Chip IDs of the devices syncing now, in the order they started.
    private(set) var syncingDeviceIDs: [String] = []

    private static let logTool = "/usr/bin/log"
    /// The stream ends by itself after this long, so a copy that outlives
    /// the app cannot run forever. A sync still going then gets a new one.
    private static let streamTimeout = "2h"
    private static let catchUpTimeout: TimeInterval = 20
    /// The sync's first line is written just after its assertion appears.
    private static let catchUpMargin: TimeInterval = 2
    /// A stream that ends sooner than this did not work; it is not restarted.
    private static let minimumHealthyRun: TimeInterval = 10

    private var stream: Process?
    private var streamStart = Date.distantPast
    private var syncStart = Date.distantPast
    /// Bumped by every start and stop, so late results are dropped.
    private var generation = 0
    /// Stream events held back until the catch-up read has been applied.
    private var heldEvents: [DeviceSyncLog.Event]?

    func start(syncStart: Date) {
        stop()
        self.syncStart = syncStart
        generation += 1
        let generation = generation
        heldEvents = []
        startStream(generation: generation)
        let arguments = [
            "show", "--style", "compact", "--start", Self.logDate(syncStart.addingTimeInterval(-Self.catchUpMargin)),
            "--predicate", DeviceSyncLog.predicate,
        ]
        let tool = Self.logTool
        let timeout = Self.catchUpTimeout
        Task { [weak self] in
            let output = await Task.detached(priority: .utility) {
                Subprocess.run(tool, arguments: arguments, timeout: timeout)
            }.value
            guard let self, self.generation == generation else { return }
            let earlier = output.map { DeviceSyncLog.events(in: $0.text) } ?? []
            let held = self.heldEvents ?? []
            self.heldEvents = nil
            self.apply(earlier + held)
        }
    }

    func stop() {
        generation += 1
        heldEvents = nil
        if let stream {
            (stream.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            stream.terminationHandler = nil
            if stream.isRunning { stream.terminate() }
        }
        stream = nil
        if !syncingDeviceIDs.isEmpty {
            syncingDeviceIDs = []
            onChange?()
        }
    }

    private func startStream(generation: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.logTool)
        process.arguments = [
            "stream", "--style", "compact", "--timeout", Self.streamTimeout, "--predicate", DeviceSyncLog.predicate,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let lines = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let events = lines.append(handle.availableData).compactMap(DeviceSyncLog.event(in:))
            guard !events.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(events, generation: generation) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.streamEnded(generation: generation) }
            }
        }
        do {
            try process.run()
            stream = process
            streamStart = Date()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            Logger.modules.error("[FreeTheNotch] Device sync log stream did not start")
        }
    }

    private func receive(_ events: [DeviceSyncLog.Event], generation: Int) {
        guard generation == self.generation else { return }
        if heldEvents != nil {
            heldEvents?.append(contentsOf: events)
        } else {
            apply(events)
        }
    }

    private func apply(_ events: [DeviceSyncLog.Event]) {
        let devices = DeviceSyncLog.syncingDevices(syncingDeviceIDs, applying: events)
        guard devices != syncingDeviceIDs else { return }
        syncingDeviceIDs = devices
        Logger.modules.notice("[FreeTheNotch] Devices syncing: \(devices.count, privacy: .public)")
        onChange?()
    }

    /// The stream ran into its own timeout while a sync is still going.
    private func streamEnded(generation: Int) {
        guard generation == self.generation else { return }
        stream = nil
        guard Date().timeIntervalSince(streamStart) >= Self.minimumHealthyRun else {
            Logger.modules.notice("[FreeTheNotch] Device sync log is not readable")
            return
        }
        start(syncStart: syncStart)
    }

    /// `log show --start` takes local time in this form.
    private static func logDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Cuts the stream's output into lines. Used only by the pipe's
    /// handler, which the file handle calls one at a time.
    private final class LineBuffer: @unchecked Sendable {
        private static let newline = UInt8(ascii: "\n")
        private var pending = Data()

        func append(_ data: Data) -> [String] {
            pending.append(data)
            var lines: [String] = []
            while let end = pending.firstIndex(of: Self.newline) {
                lines.append(String(decoding: pending[pending.startIndex..<end], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...end)
            }
            return lines
        }
    }
}
