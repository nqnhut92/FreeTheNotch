// Ported from Vorssaint (vorssaint/vorssaint-utils), GPL-3.0-or-later:
// MaxCapacityProbe.

import Foundation

/// Reads "Maximum Capacity" exactly as System Information shows it. On Apple
/// Silicon it is a smoothed value Apple computes, so IORegistry capacity
/// ratios never quite match; `system_profiler SPPowerDataType` does. Slow
/// (about a second) and changes over weeks, so it runs off the main thread at
/// most every 30 minutes.
final class MaxCapacityProbe {
    static let shared = MaxCapacityProbe()

    private let queue = DispatchQueue(label: "FreeTheNotch.maxcapacity", qos: .utility)
    private let lock = NSLock()
    private var lastRefresh: TimeInterval = -.greatestFiniteMagnitude
    private var running = false
    private let interval: TimeInterval = 1800

    /// Calls `completion` (on a background queue) with 1...100 when a fresh
    /// value was read; does nothing when not stale or unavailable.
    func refreshIfStale(_ completion: @escaping (Int) -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !running, now - lastRefresh >= interval else {
            lock.unlock()
            return
        }
        running = true
        lastRefresh = now
        lock.unlock()
        queue.async { [weak self] in
            let value = Self.read()
            self?.lock.lock()
            self?.running = false
            self?.lock.unlock()
            if let value { completion(value) }
        }
    }

    private static func read() -> Int? {
        guard
            let output = Subprocess.run(
                "/usr/sbin/system_profiler", arguments: ["SPPowerDataType", "-json"], timeout: 30),
            output.succeeded,
            let root = try? JSONSerialization.jsonObject(with: output.data)
        else { return nil }
        return percent(in: root)
    }

    /// `sppower_battery_health_maximum_capacity`, a string ("98%") or a number,
    /// possibly nested under `_items`.
    static func percent(in value: Any) -> Int? {
        if let dict = value as? [String: Any] {
            for (key, raw) in dict where key.lowercased().filter(\.isLetter).contains("maximumcapacity") {
                if let p = percent(fromRaw: raw) { return p }
            }
            for raw in dict.values { if let p = percent(in: raw) { return p } }
        } else if let array = value as? [Any] {
            for raw in array { if let p = percent(in: raw) { return p } }
        }
        return nil
    }

    private static func percent(fromRaw raw: Any) -> Int? {
        let value: Int?
        switch raw {
        case is Bool: value = nil
        case let n as NSNumber: value = n.intValue
        case let s as String:
            guard let r = s.range(of: #"[0-9]{1,3}"#, options: .regularExpression) else { return nil }
            value = Int(s[r])
        default: value = nil
        }
        guard let value, value > 0, value <= 100 else { return nil }
        return value
    }
}
