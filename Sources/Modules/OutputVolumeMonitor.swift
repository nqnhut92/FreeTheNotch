// Volume listeners adapted from DuoBar (github.com/Mikeli7666/DuoBar), MIT:
// Services/AudioOutputService.swift (default output device + volume/mute
// property listeners).

import Combine
import CoreAudio
import Foundation

/// Read-only output volume for the Duo dots. Values come from
/// `HUDController.outputVolume()`; CoreAudio listeners on the default output
/// device catch changes made anywhere (keys, Control Center, other apps).
final class OutputVolumeMonitor: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var isMuted = false
    /// False for outputs with no software volume (most HDMI/DisplayPort
    /// displays): the Sound tab dims its slider, as macOS does.
    @Published private(set) var canSetVolume = true

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var deviceAddresses: [AudioObjectPropertyAddress] = []

    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard systemListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.rebindDevice() }
        var address = Self.defaultOutputAddress
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address,
            .main, listener) == noErr
        {
            systemListener = listener
        }
        rebindDevice()
    }

    func stop() {
        removeDeviceListeners()
        if let systemListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address,
                .main, systemListener)
        }
        systemListener = nil
    }

    private func rebindDevice() {
        removeDeviceListeners()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.defaultOutputAddress
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        deviceID = id
        if id != kAudioObjectUnknown {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.read() }
            // Same elements HUDController reads: main, then left/right channels.
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
                    var address = AudioObjectPropertyAddress(
                        mSelector: selector,
                        mScope: kAudioDevicePropertyScopeOutput,
                        mElement: element)
                    guard AudioObjectHasProperty(id, &address),
                        AudioObjectAddPropertyListenerBlock(id, &address, .main, listener) == noErr
                    else { continue }
                    deviceAddresses.append(address)
                }
            }
            deviceListener = listener
        }
        read()
    }

    private func removeDeviceListeners() {
        if let deviceListener {
            for var address in deviceAddresses {
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, deviceListener)
            }
        }
        deviceAddresses = []
        deviceListener = nil
    }

    private func read() {
        let (level, muted) = HUDController.outputVolume()
        if self.level != level { self.level = level }
        if isMuted != muted { isMuted = muted }
        // HUDController.setVolume writes the main element.
        var settable: DarwinBoolean = false
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        let canSet =
            deviceID != kAudioObjectUnknown && AudioObjectHasProperty(deviceID, &address)
            && AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
        if canSetVolume != canSet { canSetVolume = canSet }
    }
}
