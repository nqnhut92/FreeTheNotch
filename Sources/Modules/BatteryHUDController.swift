// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// BatteryActivityManager.swift (IOPS monitoring) and
// BatteryStatusViewModel.swift (temporary charging / low / full HUDs).

import AppKit
import IOKit.ps
import os

enum BatteryHUDKind: Equatable {
    case charging
    case lowBattery
    case fullBattery
}

/// Watches the Mac battery and shows a short HUD in the notch when the
/// charger is plugged in, the level falls to the low threshold, or it
/// reaches full — Atoll's "Power status notifications".
@MainActor
final class BatteryHUDController: ObservableObject {
    /// Atoll's default duration for all three HUDs.
    static let duration: TimeInterval = 3

    @Published private(set) var activeKind: BatteryHUDKind?
    /// Changes on every presentation so the view restarts its animations.
    @Published private(set) var token = UUID()
    @Published private(set) var displayedLevel: Int = 0
    @Published private(set) var displayedLowPowerMode = false

    /// Published for DuoGlyph (DuoGlyphView).
    @Published private(set) var level: Float = 0
    @Published private(set) var isPluggedIn = false
    @Published private(set) var isCharging = false
    @Published private(set) var isInLowPowerMode = false
    /// Running on the internal battery. False on a Mac without one.
    @Published private(set) var isOnBattery = false

    private weak var settings: SettingsStore?
    private var source: CFRunLoopSource?
    private var hideWork: DispatchWorkItem?

    func start(settings: SettingsStore) {
        self.settings = settings
        if let info = Self.readBattery() {
            level = info.level
            isPluggedIn = info.isPluggedIn
            isCharging = info.isCharging
            isOnBattery = !info.isPluggedIn
        }
        isInLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else { return }
                Unmanaged<BatteryHUDController>.fromOpaque(context).takeUnretainedValue().powerSourceChanged()
            }, context)?.takeRetainedValue()
        {
            source = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerSourceChanged),
            name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    // MARK: Events (Atoll's handleBatteryEvent)

    /// The IOPS run-loop source (main run loop) and
    /// NSProcessInfoPowerStateDidChange, which arrives off the main thread.
    @objc private nonisolated func powerSourceChanged() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { handlePowerSourceChange() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.handlePowerSourceChange() }
        }
    }

    private func handlePowerSourceChange() {
        guard let info = Self.readBattery() else { return }

        let wasPluggedIn = isPluggedIn
        isPluggedIn = info.isPluggedIn
        isCharging = info.isCharging
        isOnBattery = !info.isPluggedIn
        if !wasPluggedIn && isPluggedIn {
            present(.charging)
        }

        if info.level != level {
            let previous = level
            level = info.level
            handleLowBattery(previous: previous, new: info.level)
            handleFullBattery(previous: previous, new: info.level)
        }

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let wasLowPower = isInLowPowerMode
        isInLowPowerMode = lowPower
        if !wasLowPower && lowPower {
            present(.lowBattery)
        }
    }

    private func handleLowBattery(previous: Float, new: Float) {
        guard !isPluggedIn, !isCharging, new < previous else { return }
        let threshold = Float(settings?.lowBatteryThreshold ?? 20)
        guard previous > threshold && new <= threshold else { return }
        present(.lowBattery)
        if settings?.lowBatterySound ?? true, settings?.batteryHUDEnabled ?? true,
            settings?.batteryHUDLow ?? true
        {
            playLowBatterySound()
        }
    }

    private func handleFullBattery(previous: Float, new: Float) {
        // Atoll's fullBatteryHUDThreshold default is 100.
        guard new > previous, previous < 100, new >= 100 else { return }
        present(.fullBattery)
    }

    // MARK: Presentation

    /// Atoll's triggerTestHUD: same animation, preview level.
    func triggerTest(_ kind: BatteryHUDKind) {
        let previewLevel: Int
        switch kind {
        case .charging: previewLevel = max(12, min(95, Int(level.rounded())))
        case .lowBattery: previewLevel = max(5, min(20, settings?.lowBatteryThreshold ?? 20))
        case .fullBattery: previewLevel = 100
        }
        present(kind, force: true, levelOverride: previewLevel)
        // Atoll's test stays silent; this one plays the alert too.
        // The "Low battery sound" switch still decides.
        if kind == .lowBattery, settings?.lowBatterySound ?? true {
            playLowBatterySound()
        }
    }

    private func present(_ kind: BatteryHUDKind, force: Bool = false, levelOverride: Int? = nil) {
        if !force {
            guard let settings, settings.batteryHUDEnabled else { return }
            switch kind {
            case .charging: guard settings.batteryHUDCharging else { return }
            case .lowBattery: guard settings.batteryHUDLow else { return }
            case .fullBattery: guard settings.batteryHUDFull else { return }
            }
        }
        displayedLevel = levelOverride ?? Int(level.rounded())
        displayedLowPowerMode = isInLowPowerMode
        token = UUID()
        activeKind = kind

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.activeKind = nil }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    /// The user's alert sound (System Settings → Sound). Atoll bundles its
    /// own lowbattery.mp3; that file is Atoll's asset, so it is not shipped.
    private func playLowBatterySound() {
        NSSound.beep()
    }

    // MARK: IOPS (Atoll's getBatteryInfo)

    private struct Info {
        let level: Float
        let isPluggedIn: Bool
        let isCharging: Bool
    }

    private static func readBattery() -> Info? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
            let current = description[kIOPSCurrentCapacityKey] as? Int,
            let state = description[kIOPSPowerSourceStateKey] as? String
        else { return nil }
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let percent = max > 0 ? Float(current) * 100 / Float(max) : Float(current)
        return Info(
            level: percent,
            isPluggedIn: state == kIOPSACPowerValue,
            isCharging: description[kIOPSIsChargingKey] as? Bool ?? false)
    }
}

// MARK: - Energy Mode (Duo battery popover)
//
// The administrator prompt is ported from Vorssaint
// (github.com/vorssaint/vorssaint-utils), GPL-3.0-or-later:
// Sources/Vorssaint/Services/ShellSupport.swift (AdminShell). The pmset
// reading and writing has no reference equivalent.

enum EnergyMode: Int, CaseIterable, Identifiable {
    case automatic = 0
    case low = 1
    case high = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .low: return "Low Power"
        case .high: return "High Power"
        }
    }
}

/// Reads and sets the macOS Energy Mode with `pmset`. Reading needs no
/// rights; setting asks for an administrator password every time (pmset
/// needs root), like any app outside System Settings.
final class EnergyModeController: ObservableObject {
    @Published private(set) var mode: EnergyMode = .automatic
    /// The Mac has a `powermode` setting (High Power capable); otherwise
    /// only `lowpowermode` exists.
    @Published private(set) var supportsHighPower = false
    @Published private(set) var isChanging = false

    private let queue = DispatchQueue(label: "FreeTheNotch.energyMode", qos: .userInitiated)

    func refresh() {
        queue.async { [weak self] in
            guard let output = Subprocess.run("/usr/bin/pmset", arguments: ["-g"], timeout: 5)?.text else { return }
            var powerMode: Int?
            var lowPower: Int?
            for line in output.split(separator: "\n") {
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count >= 2, let value = Int(parts[1]) else { continue }
                if parts[0] == "powermode" { powerMode = value }
                if parts[0] == "lowpowermode" { lowPower = value }
            }
            let mode: EnergyMode =
                powerMode.flatMap(EnergyMode.init(rawValue:))
                ?? (lowPower == 1 ? .low : .automatic)
            DispatchQueue.main.async {
                self?.supportsHighPower = powerMode != nil
                self?.mode = mode
            }
        }
    }

    /// Applies to the current power source, like the Control Center menu.
    func set(_ newMode: EnergyMode, onACPower: Bool) {
        guard newMode != mode, !isChanging else { return }
        isChanging = true
        let source = onACPower ? "-c" : "-b"
        let command =
            supportsHighPower
            ? "/usr/bin/pmset \(source) powermode \(newMode.rawValue)"
            : "/usr/bin/pmset \(source) lowpowermode \(newMode == .low ? 1 : 0)"
        // Vorssaint: bring the agent app forward so SecurityAgent's password
        // dialog opens in focus instead of behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        queue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            let script =
                "do shell script \(Self.appleScriptString(command)) with administrator privileges"
                + " with prompt \(Self.appleScriptString("FreeTheNotch wants to change the Energy Mode."))"
            // The password dialog waits for the user, hence the long timeout.
            let ok = Subprocess.run("/usr/bin/osascript", arguments: ["-e", script], timeout: 600)?.succeeded ?? false
            if !ok {
                Logger.modules.notice(
                    "[FreeTheNotch] Energy Mode change to \(newMode.rawValue, privacy: .public) cancelled or failed")
            }
            DispatchQueue.main.async {
                self?.isChanging = false
                self?.refresh()
            }
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        "\""
            + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
