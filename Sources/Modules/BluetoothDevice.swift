import Foundation

// MARK: - Model

enum BTKind {
    case airpods, headphones, speaker, mouse, keyboard, trackpad
    case watch, pencil, gamepad, phone, generic

    var symbolName: String {
        switch self {
        case .airpods: return "airpodspro"
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker"
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .watch: return "applewatch"
        case .pencil: return "applepencil"
        case .gamepad: return "gamecontroller"
        case .phone: return "iphone"
        // No "bluetooth" SF Symbol exists; use radiowaves as the generic fallback.
        case .generic: return "antenna.radiowaves.left.and.right"
        }
    }

    /// Kind from a system_profiler entry, where there is no class of device
    /// to ask: the name for AirPods and trackpads, then the stored type.
    init(name: String, minorType: String?) {
        let n = name.lowercased()
        if n.contains("airpod") || n.contains("beats") {
            self = .airpods
            return
        }
        if n.contains("trackpad") {
            self = .trackpad
            return
        }
        switch minorType?.lowercased() {
        case "mouse": self = .mouse
        case "keyboard": self = .keyboard
        case "headphones", "headset": self = .headphones
        case "speaker": self = .speaker
        case "trackpad": self = .trackpad
        case "gamepad", "game controller", "joystick": self = .gamepad
        default: self = n.contains("mouse") || n.contains("mx ") ? .mouse : .generic
        }
    }
}

struct BTDevice: Identifiable {
    /// The device address, or a name-based key for a device without one.
    let id: String
    let name: String
    var kind: BTKind
    var isConnected: Bool
    /// Best effort; many devices never publish a level.
    var batteryPercent: Int?
    /// AirPods-style per-part levels (system_profiler), for the Batteries page.
    var parts: BTBatteryParts?
}

/// Left bud, right bud and case levels. The case only reports while it is
/// open or recently closed, so any of them can be missing.
struct BTBatteryParts: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    var isEmpty: Bool { left == nil && right == nil && caseLevel == nil }

    /// Field by field, the higher known level wins.
    func merged(with other: BTBatteryParts) -> BTBatteryParts {
        func pick(_ a: Int?, _ b: Int?) -> Int? { [a, b].compactMap { $0 }.max() }
        return BTBatteryParts(
            left: pick(left, other.left), right: pick(right, other.right),
            caseLevel: pick(caseLevel, other.caseLevel))
    }
}

// MARK: - Tool output parsing

/// Battery levels and device types from `system_profiler SPBluetoothDataType
/// -json` and `pmset -g accps`, after Atoll's batteryFetchQueue fallbacks.
enum BluetoothToolParser {
    /// Atoll's extractSystemProfilerBatteryPercentage target: the level of
    /// the connected device whose name matches `name` (loosely).
    static func batteryPercent(name: String, systemProfiler data: Data) -> Int? {
        guard !name.isEmpty else { return nil }
        let target = name.lowercased()
        for (rawName, payload) in entries(in: data, sections: ["device_connected"]) {
            let ln = rawName.lowercased()
            guard ln.contains(target) || target.contains(ln) else { continue }
            if let pct = combinedBattery(in: payload) { return pct }
        }
        return nil
    }

    /// Left / right / case levels of one connected device (our addition;
    /// Atoll folds them into one max value). The same AirPods can be listed
    /// twice, the first entry without the right bud, so every match merges.
    static func batteryParts(name: String, systemProfiler data: Data) -> BTBatteryParts? {
        var merged = BTBatteryParts()
        for (rawName, payload) in entries(in: data, sections: ["device_connected"])
        where namesMatch(rawName, name) {
            merged = merged.merged(with: parts(in: payload))
        }
        return merged.isEmpty ? nil : merged
    }

    /// Devices system_profiler reports with a battery level, for the
    /// Batteries strip. `device_connected` entries include devices IOBluetooth
    /// reports as disconnected (AirPods in an open case nearby). AirPods in a
    /// closed case are under `device_not_connected` but keep their bud and case
    /// levels, which the macOS Batteries widget also shows; from that list only
    /// entries with per-part levels count. Not in Atoll (it reads
    /// `device_connected` only).
    static func nearbyDevices(systemProfiler data: Data) -> [BTDevice] {
        // AirPods can be listed twice under one name (two addresses, one of
        // them with only some parts); they merge into one device.
        var result: [String: BTDevice] = [:]
        for section in ["device_connected", "device_not_connected"] {
            for (name, payload) in entries(in: data, sections: [section]) {
                let parts = parts(in: payload)
                let percent = combinedBattery(in: payload)
                if section == "device_not_connected" {
                    guard !parts.isEmpty else { continue }
                } else {
                    guard percent != nil || !parts.isEmpty else { continue }
                }
                let id = "nearby." + name.lowercased()
                if var existing = result[id] {
                    let merged = (existing.parts ?? BTBatteryParts()).merged(with: parts)
                    existing.parts = merged.isEmpty ? nil : merged
                    existing.batteryPercent = [existing.batteryPercent, percent].compactMap { $0 }.max()
                    result[id] = existing
                } else {
                    result[id] = BTDevice(
                        id: id, name: name,
                        kind: BTKind(name: name, minorType: payload["device_minorType"] as? String),
                        isConnected: false, batteryPercent: percent,
                        parts: parts.isEmpty ? nil : parts)
                }
            }
        }
        return result.values.sorted { $0.name < $1.name }
    }

    /// `device_minorType` of every paired device, connected or not, by
    /// lowercased name.
    static func accessoryTypes(systemProfiler data: Data) -> [String: String] {
        var types: [String: String] = [:]
        for (name, payload) in entries(in: data, sections: ["device_connected", "device_not_connected"]) {
            if let type = payload["device_minorType"] as? String { types[name.lowercased()] = type }
        }
        return types
    }

    /// Atoll-style `pmset -g accps` lines: "- Device Name (optional info) 85%".
    static func batteryPercent(name: String, pmset data: Data) -> Int? {
        guard !name.isEmpty, let output = String(data: data, encoding: .utf8) else { return nil }
        let target = name.lowercased()
        let pattern = #"^\s*-\s*(.+?)\s*(?:\(.+?\))?\s+(\d+)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
        let nsOutput = output as NSString
        var result: Int?
        regex.enumerateMatches(in: output, range: NSRange(location: 0, length: nsOutput.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let rawName = nsOutput.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let ln = rawName.lowercased()
            guard ln.contains(target) || target.contains(ln),
                let pct = Int(nsOutput.substring(with: match.range(at: 2))), (0...100).contains(pct)
            else { return }
            result = pct
        }
        return result
    }

    /// Same device under two spellings: case, curly vs straight apostrophe,
    /// or one name containing the other ("AirPods Pro" / "Nick's AirPods Pro").
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        }
        let x = norm(a)
        let y = norm(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x.contains(y) || y.contains(x)
    }

    // MARK: Helpers

    /// (name, payload) pairs of the given sections. system_profiler nests
    /// them as `SPBluetoothDataType[].<section>[] { name: payload }`.
    private static func entries(in data: Data, sections: [String]) -> [(String, [String: Any])] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let controllers = json["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }
        var result: [(String, [String: Any])] = []
        for controller in controllers {
            for section in sections {
                for group in controller[section] as? [[String: [String: Any]]] ?? [] {
                    result += group.map { ($0.key, $0.value) }
                }
            }
        }
        return result
    }

    private static func parts(in payload: [String: Any]) -> BTBatteryParts {
        BTBatteryParts(
            left: payload["device_batteryLevelLeft"].flatMap(batteryValue),
            right: payload["device_batteryLevelRight"].flatMap(batteryValue),
            caseLevel: payload["device_batteryLevelCase"].flatMap(batteryValue))
    }

    /// Atoll's extractSystemProfilerBatteryPercentage: the known keys first,
    /// then any key mentioning "battery"; the highest level wins.
    private static func combinedBattery(in payload: [String: Any]) -> Int? {
        let preferredKeys = [
            "device_batteryLevelCase",
            "device_batteryLevelLeft",
            "device_batteryLevelRight",
            "device_batteryLevelMain",
            "device_batteryLevel",
            "device_batteryLevelCombined",
            "device_batteryPercentCombined",
        ]
        var values = preferredKeys.compactMap { payload[$0].flatMap(batteryValue) }
        if values.isEmpty {
            for (key, raw) in payload where key.lowercased().contains("battery") {
                if let v = batteryValue(raw) { values.append(v) }
            }
        }
        return values.max()
    }

    /// 85, 85.0, "85%" or "85" -> 85; anything outside 0…100 -> nil.
    static func batteryValue(_ raw: Any) -> Int? {
        if let n = raw as? Int, (0...100).contains(n) { return n }
        if let n = raw as? Double, (0...100).contains(Int(n)) { return Int(n) }
        if let s = raw as? String, let n = Int(s.filter(\.isNumber)), (0...100).contains(n) { return n }
        return nil
    }
}
