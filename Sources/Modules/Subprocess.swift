import Foundation

/// Runs a command-line tool to completion and returns its standard output.
///
/// The pipe is drained before waiting: a tool that writes more than the pipe
/// buffer (about 64 KB, easily reached by `system_profiler -json`) blocks
/// until someone reads, so waiting first would deadlock. A tool still running
/// after `timeout` is terminated, then killed if it ignores that. Blocking:
/// never call this on the main thread.
enum Subprocess {
    struct Output {
        let status: Int32
        let data: Data
        /// True when the tool had to be stopped because it ran past the timeout.
        let timedOut: Bool

        var succeeded: Bool { status == 0 && !timedOut }
        var text: String { String(decoding: data, as: UTF8.self) }
    }

    /// How long a terminated tool gets to exit before it is killed.
    private static let terminationGrace: TimeInterval = 2

    /// Returns nil when the tool cannot be launched.
    static func run(_ path: String, arguments: [String] = [], timeout: TimeInterval) -> Output? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        let timedOut = TimeoutFlag()
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + terminationGrace) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return Output(status: process.terminationStatus, data: data, timedOut: timedOut.isSet)
    }

    /// Set by the watchdog queue, read by the caller once the tool has exited.
    private final class TimeoutFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }
}
