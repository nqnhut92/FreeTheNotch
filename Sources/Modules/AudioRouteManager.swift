// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// managers/AudioRouteManager.swift (output device list + switching).

import CoreAudio
import Foundation
import os

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    var iconName: String {
        let normalizedName = name.lowercased()
        if normalizedName.contains("airpods") { return "airpodspro" }
        if normalizedName.contains("macbook") { return "laptopcomputer" }
        if normalizedName.contains("headphone") || normalizedName.contains("headset") { return "headphones" }
        if normalizedName.contains("beats") { return "headphones" }
        if normalizedName.contains("homepod") { return "hifispeaker.2" }

        switch transportType {
        case kAudioDeviceTransportTypeBluetooth:
            return normalizedName.contains("speaker") ? "speaker.wave.2" : "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        // macOS's Sound menu draws monitors with the display glyph.
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI:
            return "display"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeFireWire:
            return "hifispeaker.2"
        case kAudioDeviceTransportTypeBuiltIn:
            return normalizedName.contains("display") ? "display" : "speaker.wave.2"
        default:
            return "speaker.wave.2"
        }
    }
}

final class AudioRouteManager: ObservableObject {
    static let shared = AudioRouteManager()

    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var activeDeviceID: AudioDeviceID = 0

    private let queue = DispatchQueue(label: "FreeTheNotch.audio-route", qos: .userInitiated)

    private init() {
        refreshDevices()
        // Atoll listens for its own route-change notification; the CoreAudio
        // default-output and device-list listeners are the source of that.
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main) { [weak self] _, _ in
                self?.refreshDevices()
            }
        }
    }

    func refreshDevices() {
        queue.async { [weak self] in
            guard let self else { return }
            let defaultID = self.fetchDefaultOutputDevice()
            let sorted = self.fetchOutputDeviceIDs().compactMap(self.makeDeviceInfo).sorted { lhs, rhs in
                if lhs.id == defaultID { return true }
                if rhs.id == defaultID { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            DispatchQueue.main.async {
                self.activeDeviceID = defaultID
                self.devices = sorted
            }
        }
    }

    func select(device: AudioOutputDevice) {
        queue.async { [weak self] in
            self?.setDefaultOutputDevice(device.id)
        }
    }

    // MARK: - CoreAudio

    private func fetchOutputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address, 0, nil, &dataSize) == noErr
        else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address, 0, nil, &dataSize, &ids) == noErr
        else { return [] }
        return ids
    }

    private func makeDeviceInfo(for deviceID: AudioDeviceID) -> AudioOutputDevice? {
        guard deviceHasOutputChannels(deviceID), canBeDefaultOutput(deviceID) else { return nil }
        return AudioOutputDevice(
            id: deviceID,
            name: deviceName(for: deviceID) ?? "Unknown Device",
            transportType: transportType(for: deviceID))
    }

    /// The macOS Sound menu leaves out outputs that cannot be the default
    /// one, such as Microsoft Teams Audio (a virtual device only Teams uses).
    /// Our addition; Atoll lists every output.
    private func canBeDefaultOutput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return true }
        var value: UInt32 = 1
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return true }
        return value != 0
    }

    private func deviceHasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, buffer) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name) == noErr,
            let name
        else { return nil }
        return name.takeRetainedValue() as String
    }

    private func transportType(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var type: UInt32 = kAudioDeviceTransportTypeUnknown
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &type)
        return status == noErr ? type : kAudioDeviceTransportTypeUnknown
    }

    private func fetchDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &deviceID)
        return status == noErr ? deviceID : 0
    }

    private func setDefaultOutputDevice(_ deviceID: AudioDeviceID) {
        var target = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &target)
        if status == noErr {
            DispatchQueue.main.async { [weak self] in self?.activeDeviceID = deviceID }
            refreshDevices()
        }
    }
}

// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// managers/AppleMusicAirPlayManager.swift — Music's own AirPlay devices
// (HomePod, Apple TV, AirPlay TVs…) over AppleScript, with multi-room
// selection and per-device volume.

struct AirPlayDevice: Identifiable, Equatable {
    let id: String  // network address, or name as fallback
    let name: String
    let kind: String
    var isSelected: Bool
    var volume: Int  // 0-100

    var iconName: String {
        switch kind {
        case "HomePod": return "homepodmini"
        case "AirPort Express": return "airport.express"
        case "computer": return "laptopcomputer"
        // Not in Atoll: Music reports AirPlay TVs/monitors as "TV".
        case "TV", "Apple TV": return "tv"
        case "AirPlay device":
            let lower = name.lowercased()
            if lower.contains("tv") || lower.contains("theatre") || lower.contains("theater") { return "appletv" }
            return "airplayaudio"
        default: return "airplayaudio"
        }
    }
}

/// Atoll's AppleScriptHelper: run scripts off the main thread, one at a time.
enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "FreeTheNotch.applescript", qos: .userInitiated)

    static func execute(_ source: String) async -> NSAppleEventDescriptor? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error { Logger.media.error("[FreeTheNotch] AppleScript failed: \(error, privacy: .public)") }
                continuation.resume(returning: error == nil ? result : nil)
            }
        }
    }
}

@MainActor
final class AppleMusicAirPlayManager: ObservableObject {
    static let shared = AppleMusicAirPlayManager()

    @Published private(set) var devices: [AirPlayDevice] = []
    @Published private(set) var isLoading = false

    private var isBusy = false

    // Volume pipeline (Atoll): slider writes go to a non-published buffer and
    // are drained into a serialized AppleScript queue, so the slider is not
    // re-rendered (and reset) mid-drag.
    private var userSetVolume: [String: Int] = [:]
    private var throttleActive: [String: Bool] = [:]
    private var lastCommittedVolume: [String: Int] = [:]
    private var isCommittingVolume = false
    private var pendingVolumeCommits: [(volume: Int, deviceName: String, deviceID: String)] = []

    func refreshDevices() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        isLoading = true
        defer { isLoading = false }

        let script = """
            tell application "Music"
                try
                    set deviceList to {}
                    set allDevices to AirPlay devices
                    repeat with d in allDevices
                        set deviceName to name of d
                        set deviceKind to kind of d as string
                        set deviceActive to selected of d
                        set deviceAddr to network address of d
                        set deviceVol to sound volume of d
                        set end of deviceList to {deviceName, deviceKind, deviceActive, deviceAddr, deviceVol}
                    end repeat
                    return deviceList
                on error
                    return {}
                end try
            end tell
            """
        guard let result = await AppleScriptRunner.execute(script), result.numberOfItems > 0 else { return }

        var fetched: [AirPlayDevice] = []
        for i in 1...result.numberOfItems {
            guard let item = result.atIndex(i) else { continue }
            let name = item.atIndex(1)?.stringValue ?? "Unknown"
            let kind = item.atIndex(2)?.stringValue ?? "AirPlay device"
            let selected = item.atIndex(3)?.booleanValue ?? false
            let addr = item.atIndex(4)?.stringValue ?? ""
            let volume = Int(item.atIndex(5)?.int32Value ?? 50)
            fetched.append(
                AirPlayDevice(
                    id: addr.isEmpty ? name : addr, name: name, kind: kind,
                    isSelected: selected, volume: volume))
        }
        devices = fetched
        for device in fetched { lastCommittedVolume[device.id] = device.volume }
    }

    func toggleDevice(_ device: AirPlayDevice) async {
        guard !isBusy else { return }
        isBusy = true
        let escapedName = device.name.replacingOccurrences(of: "\"", with: "\\\"")
        _ = await AppleScriptRunner.execute(
            """
            tell application "Music"
                try
                    set targetDevice to first AirPlay device whose name is "\(escapedName)"
                    set selected of targetDevice to \(!device.isSelected)
                end try
            end tell
            """)
        try? await Task.sleep(for: .milliseconds(200))
        isBusy = false
        await refreshDevices()
    }

    func currentVolume(for deviceID: String) -> Int {
        if let pending = userSetVolume[deviceID] { return pending }
        if let committed = lastCommittedVolume[deviceID] { return committed }
        return devices.first { $0.id == deviceID }?.volume ?? 0
    }

    func setVolume(_ volume: Int, for deviceID: String) {
        let clamped = min(max(volume, 0), 100)
        guard let device = devices.first(where: { $0.id == deviceID }) else { return }
        userSetVolume[deviceID] = clamped
        guard throttleActive[deviceID] != true else { return }
        throttleActive[deviceID] = true
        Task { [weak self] in
            guard let self else { return }
            if let first = self.userSetVolume.removeValue(forKey: deviceID) {
                await self.enqueueVolumeCommit(volume: first, deviceName: device.name, deviceID: deviceID)
            }
            while true {
                try? await Task.sleep(for: .milliseconds(150))
                guard let pending = self.userSetVolume.removeValue(forKey: deviceID) else { break }
                await self.enqueueVolumeCommit(volume: pending, deviceName: device.name, deviceID: deviceID)
            }
            self.throttleActive[deviceID] = false
        }
    }

    private func enqueueVolumeCommit(volume: Int, deviceName: String, deviceID: String) async {
        if isCommittingVolume {
            pendingVolumeCommits.removeAll { $0.deviceID == deviceID }
            pendingVolumeCommits.append((volume: volume, deviceName: deviceName, deviceID: deviceID))
            return
        }
        isCommittingVolume = true
        await commitVolume(volume: volume, deviceName: deviceName, deviceID: deviceID)
        while !pendingVolumeCommits.isEmpty {
            var latest: [String: (volume: Int, deviceName: String, deviceID: String)] = [:]
            for entry in pendingVolumeCommits { latest[entry.deviceID] = entry }
            pendingVolumeCommits.removeAll()
            for (_, entry) in latest {
                await commitVolume(volume: entry.volume, deviceName: entry.deviceName, deviceID: entry.deviceID)
            }
        }
        isCommittingVolume = false
    }

    /// Music rebalances other selected devices when one drops past them in a
    /// single call; Atoll steps through the highest other volume first.
    private func commitVolume(volume: Int, deviceName: String, deviceID: String) async {
        let escapedName = deviceName.replacingOccurrences(of: "\"", with: "\\\"")
        let current = lastCommittedVolume[deviceID] ?? volume
        let otherMax =
            devices
            .filter { $0.id != deviceID && $0.isSelected }
            .map { lastCommittedVolume[$0.id] ?? $0.volume }
            .max() ?? 0
        if current > otherMax && volume < otherMax && otherMax > 0 {
            await sendVolume(escapedName: escapedName, volume: otherMax)
        }
        await sendVolume(escapedName: escapedName, volume: volume)
        lastCommittedVolume[deviceID] = volume
    }

    private func sendVolume(escapedName: String, volume: Int) async {
        _ = await AppleScriptRunner.execute(
            """
            tell application "Music"
                try
                    set targetDevice to first AirPlay device whose name is "\(escapedName)"
                    set sound volume of targetDevice to \(volume)
                end try
            end tell
            """)
    }
}
