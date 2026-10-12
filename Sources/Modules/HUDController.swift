import AppKit
import Combine
import CoreAudio
import SwiftUI
import os

/// Atoll-style inline HUD: volume/backlight changes show INSIDE the notch
/// (icon + level bar + numeric %), not in a separate window.
///
/// To avoid duplicating macOS's native volume bezel, we intercept the media
/// keys with a CGEvent tap (requires Accessibility permission), swallow them,
/// and adjust the volume ourselves via CoreAudio. The system never sees the
/// key press, so only our notch HUD appears.
final class HUDController: ObservableObject {
    enum Kind { case volume, backlight }

    @Published private(set) var isHUDVisible = false
    @Published private(set) var kind: Kind = .volume
    @Published private(set) var level: Double = 0.5
    @Published private(set) var isMuted = false

    private var hideTimer: Timer?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// The HUD switches, copied from SettingsStore (main thread) for the
    /// key-work queue.
    private let switches = HUDSwitches()
    private var cancellables = Set<AnyCancellable>()

    private var backlightEstimate: Double = 0.5

    @MainActor
    func start(settings: SettingsStore) {
        settings.$hudVolume.sink { [switches] in switches.volume = $0 }.store(in: &cancellables)
        settings.$hudBacklight.sink { [switches] in switches.backlight = $0 }.store(in: &cancellables)
        let (level, muted) = Self.outputVolume()
        self.level = Double(level)
        self.isMuted = muted
        setupEventTap()
    }

    // MARK: Event tap

    private func setupEventTap() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            Logger.hud.notice("[FreeTheNotch] Accessibility not granted — volume keys will show native OSD too")
            return
        }
        let mask = CGEventMask(1) << SystemDefinedEvent.type.rawValue
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let controller = Unmanaged<HUDController>.fromOpaque(refcon).takeUnretainedValue()
                    return controller.handleTapEvent(event, type: type)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Logger.hud.error("[FreeTheNotch] Failed to create event tap")
            return
        }
        eventTap = tap
        // Checked here, on the main thread, before the tap thread starts.
        rawFieldsWork = Self.verifyRawSystemDefinedFields()
        if !rawFieldsWork {
            Logger.hud.error(
                "[FreeTheNotch] media-key tap: CGEvent field layout changed; media keys pass through to macOS")
        }
        // The tap runs on its own thread, not the main run loop. An active tap
        // holds the session's input queue until it answers, so a stalled main
        // thread would freeze every key and mouse event on the Mac until
        // macOS disabled the tap.
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "FreeTheNotch.mediaKeyTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
        Logger.hud.notice("[FreeTheNotch] Media-key event tap installed")
    }

    private var tapThread: Thread?

    /// Set once on the main thread before the tap starts; false if a macOS
    /// update moved the fields, and the tap then swallows nothing.
    private var rawFieldsWork = false

    private static func verifyRawSystemDefinedFields() -> Bool {
        let data1 = 0x7B0A00  // a distinctive value: keyCode 0x7B, key down
        guard
            let probe = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: Int16(SystemDefinedEvent.auxControlButtonsSubtype), data1: data1, data2: -1)?.cgEvent
        else { return false }
        return probe.getIntegerValueField(SystemDefinedEvent.subtypeField)
            == SystemDefinedEvent.auxControlButtonsSubtype
            && probe.getIntegerValueField(SystemDefinedEvent.data1Field) == Int64(data1)
    }
    /// Atoll's MediaKeyInterceptor rule: no CoreAudio work inside the tap
    /// callback. The callback only decides to swallow the key and returns;
    /// the volume change runs here, in key order. Inline, a slow coreaudiod
    /// would hold the session input queue and every key and click on the
    /// Mac would wait. A serial queue, not main (Atoll uses main), so a
    /// main-thread stall cannot delay the volume either.
    private let keyWorkQueue = DispatchQueue(label: "FreeTheNotch.mediaKeyWork", qos: .userInteractive)

    /// Atoll's MediaKeyInterceptor.handleEvent order: re-enable a tap macOS
    /// disabled, and only read real system-defined events (the disabled
    /// notifications carry type 0xFFFFFFFE). Events pass through
    /// unretained: the tap does not own them.
    private func handleTapEvent(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            guard let eventTap else { return Unmanaged.passUnretained(event) }
            if type == .tapDisabledByTimeout, shouldBackOff() {
                // Safety valve (not in Atoll, which always re-enables): a
                // timeout means we could not answer within ~1 s, and every
                // special-key event (and input queued behind it) waits for
                // us. Re-enabling at once keeps a slow Mac stalling, so stay
                // off for 2 minutes; macOS handles the keys (its own OSD).
                Logger.hud.notice("[FreeTheNotch] media-key tap timed out twice within 60 s; off for 120 s")
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120) {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                    Logger.hud.notice("[FreeTheNotch] media-key tap back on")
                }
                return Unmanaged.passUnretained(event)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            Logger.hud.notice(
                "[FreeTheNotch] media-key tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public); re-enabled"
            )
            return Unmanaged.passUnretained(event)
        }
        guard type == SystemDefinedEvent.type else { return Unmanaged.passUnretained(event) }
        return handleSystemDefined(event) ? nil : Unmanaged.passUnretained(event)
    }

    /// Timeouts in the last 60 s (tap thread only).
    private var recentTimeouts: [Date] = []

    /// Records a timeout; true when it is the second within 60 s.
    private func shouldBackOff() -> Bool {
        let now = Date()
        recentTimeouts = recentTimeouts.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard recentTimeouts.count >= 2 else { return false }
        recentTimeouts = []
        return true
    }

    /// Returns true if the event was swallowed.
    private func handleSystemDefined(_ event: CGEvent) -> Bool {
        // NSEvent.subtype / data1, read straight from the CGEvent: no NSEvent
        // off the main thread (see SystemDefinedEvent.subtypeField).
        guard rawFieldsWork,
            event.getIntegerValueField(SystemDefinedEvent.subtypeField) == SystemDefinedEvent.auxControlButtonsSubtype
        else { return false }
        let data1 = Int(event.getIntegerValueField(SystemDefinedEvent.data1Field))
        // data1 layout for aux control buttons: keyCode in bits 16-23, keyDown in bit 8
        let keyCode = Int((data1 >> 16) & 0xFF)
        let keyDown = ((data1 >> 8) & 0xFF) == 0xA  // 0xA = key down, 0xB = key up
        guard keyDown else { return false }

        // NX key types
        switch keyCode {
        case 0:  // NX_KEYTYPE_SOUND_UP
            keyWorkQueue.async { [weak self] in self?.adjustVolume(by: 0.0625) }
            return true
        case 1:  // NX_KEYTYPE_SOUND_DOWN
            keyWorkQueue.async { [weak self] in self?.adjustVolume(by: -0.0625) }
            return true
        case 7:  // NX_KEYTYPE_MUTE
            keyWorkQueue.async { [weak self] in self?.toggleMute() }
            return true
        case 20:  // NX_KEYTYPE_ILLUMINATION_DOWN
            keyWorkQueue.async { [weak self] in self?.nudgeBacklight(by: -0.1) }
            return true
        case 21:  // NX_KEYTYPE_ILLUMINATION_UP
            keyWorkQueue.async { [weak self] in self?.nudgeBacklight(by: 0.1) }
            return true
        default:
            return false
        }
    }

    // MARK: Volume control

    private func adjustVolume(by delta: Float) {
        guard switches.volume else { return }
        let (current, muted) = Self.outputVolume()
        var newLevel = current + delta
        newLevel = min(1, max(0, newLevel))
        // Unmute on volume change (macOS behavior).
        if muted { Self.setMuted(false) }
        Self.setVolume(newLevel)
        flash(kind: .volume, level: Double(newLevel), muted: false)
    }

    private func toggleMute() {
        guard switches.volume else { return }
        let (_, muted) = Self.outputVolume()
        Self.setMuted(!muted)
        let (level, newMuted) = Self.outputVolume()
        flash(kind: .volume, level: Double(level), muted: newMuted)
    }

    static func outputVolume() -> (Float, Bool) {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address, 0, nil, &size, &deviceID) == noErr
        else {
            return (0.5, false)
        }
        var level: Float32 = 0.5
        size = UInt32(MemoryLayout<Float32>.size)
        address.mSelector = kAudioDevicePropertyVolumeScalar
        address.mScope = kAudioDevicePropertyScopeOutput
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &level) != noErr {
            level = 0.5
        }
        // Atoll-style: check mute on each element, not just main.
        let elements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]
        var retrieved = false
        var allMuted = true
        for element in elements {
            var elemAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            guard AudioObjectHasProperty(deviceID, &elemAddress) else { continue }
            var value: UInt32 = 0
            var valSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(deviceID, &elemAddress, 0, nil, &valSize, &value) == noErr {
                retrieved = true
                if value == 0 { allMuted = false }
            }
        }
        let isMuted = retrieved ? allMuted : false
        return (level, isMuted)
    }

    static func setVolume(_ level: Float) {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address, 0, nil, &size, &deviceID) == noErr
        else { return }
        var vol = Float32(level)
        size = UInt32(MemoryLayout<Float32>.size)
        address.mSelector = kAudioDevicePropertyVolumeScalar
        address.mScope = kAudioDevicePropertyScopeOutput
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
    }

    static func setMuted(_ muted: Bool) {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address, 0, nil, &size, &deviceID) == noErr
        else { return }
        // Atoll: try each element (main, 1, 2), not just main.
        let elements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]
        let muteValue: UInt32 = muted ? 1 : 0
        for element in elements {
            var elemAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            guard AudioObjectHasProperty(deviceID, &elemAddress) else { continue }
            var value = muteValue
            let status = AudioObjectSetPropertyData(
                deviceID, &elemAddress, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), &value)
            if status != noErr {
                Logger.hud.error(
                    "[FreeTheNotch] setMuted element \(element, privacy: .public) failed: \(status, privacy: .public)")
            }
        }
    }

    // MARK: Backlight

    private func nudgeBacklight(by delta: Double) {
        guard switches.backlight else { return }
        backlightEstimate = min(1, max(0, backlightEstimate + delta))
        flash(kind: .backlight, level: backlightEstimate, muted: false)
    }

    // MARK: Flash

    /// Called from the tap thread; the HUD state is UI, so it moves to main.
    private func flash(kind: Kind, level: Double, muted: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.flash(kind: kind, level: level, muted: muted) }
            return
        }
        self.kind = kind
        self.level = level
        self.isMuted = muted
        self.isHUDVisible = true
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            self?.isHUDVisible = false
        }
    }

    /// SF Symbol for the current HUD.
    var icon: String {
        switch kind {
        case .volume:
            if isMuted { return "speaker.slash.fill" }
            if level < 0.33 { return "speaker.wave.1.fill" }
            if level < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .backlight:
            return level < 0.05 ? "keyboard" : "keyboard.fill"
        }
    }
}

/// `kCGEventSystemDefined` events: media, volume, brightness and Caps Lock
/// keys. The SDK no longer exports `CGEventType.systemDefined`.
enum SystemDefinedEvent {
    static let type = CGEventType(rawValue: 14)!
    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS: the media and volume keys.
    static let auxControlButtonsSubtype: Int64 = 8
    /// Undocumented CGEvent fields holding `NSEvent.subtype` and `data1`
    /// (a round trip of `NSEvent.otherEvent` through `cgEvent` shows them). The
    /// media-key tap reads them instead of building an `NSEvent`, which must
    /// happen on the main thread on macOS 27 (off it, `dispatch_assert_queue`
    /// crashes on Caps Lock). Atoll builds the NSEvent because its tap runs
    /// on the main run loop; ours does not (see HUDController.setupEventTap).
    static let subtypeField = CGEventField(rawValue: 99)!
    static let data1Field = CGEventField(rawValue: 149)!
}

/// HUD switches readable from any thread.
private final class HUDSwitches: @unchecked Sendable {
    private let lock = NSLock()
    private var volumeValue = true
    private var backlightValue = true

    var volume: Bool {
        get { lock.withLock { volumeValue } }
        set { lock.withLock { volumeValue = newValue } }
    }
    var backlight: Bool {
        get { lock.withLock { backlightValue } }
        set { lock.withLock { backlightValue = newValue } }
    }
}
