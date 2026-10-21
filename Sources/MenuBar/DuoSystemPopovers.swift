import CoreAudio
import SwiftUI

// MARK: - Battery popover

/// Battery popover laid out like the macOS Battery menu (Control Center →
/// Battery). "Charge to Full Now" is left out: macOS has no public API for it.
struct DuoBatteryPopover: View {
    @ObservedObject var battery: BatteryHUDController
    @ObservedObject var system: SystemMonitor
    @ObservedObject var processes: ProcessMonitor
    @ObservedObject var energy: EnergyModeController
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Battery")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
            Text("Power Source: \(battery.isPluggedIn ? "Power Adapter" : "Battery")")
                .modifier(StatusLine())
            if let status = statusText {
                Text(status).modifier(StatusLine())
            }

            DuoMenuSeparator()
            DuoMenuSectionTitle("Energy Mode")
            ForEach(energyModes) { mode in
                DuoMenuRow {
                    energy.set(mode, onACPower: battery.isPluggedIn)
                } content: {
                    DuoCircleIcon(symbol: symbol(for: mode), isActive: energy.mode == mode)
                    Text(mode.title).font(.system(size: 13))
                    Spacer()
                }
                .disabled(energy.isChanging)
            }

            DuoMenuSeparator()
            DuoMenuSectionTitle("Using Significant Energy")
            if significantApps.isEmpty {
                Text(processes.hasSamples ? "No Apps Using Significant Energy" : "Measuring\u{2026}")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
            } else {
                ForEach(significantApps, id: \.name) { row in
                    HStack(spacing: 8) {
                        if let icon = row.icon {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "app").frame(width: 18, height: 18)
                        }
                        Text(row.name).font(.system(size: 13)).lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
            }

            DuoMenuSeparator()
            DuoMenuRow {
                onClose()
                SystemSettings.open(.battery)
            } content: {
                Text("Battery Settings\u{2026}").font(.system(size: 13))
                Spacer()
            }
        }
        .padding(.bottom, 6)
        .frame(width: 316)
    }

    private var energyModes: [EnergyMode] {
        energy.supportsHighPower ? EnergyMode.allCases : [.automatic, .low]
    }

    private func symbol(for mode: EnergyMode) -> String {
        switch mode {
        case .automatic: return "battery.100percent"
        case .low: return "battery.25percent"
        case .high: return DuoCircleIcon.highPower
        }
    }

    /// macOS wording: "Charging On Hold" when plugged in but held below full.
    private var statusText: String? {
        let level = Int(battery.level.rounded())
        if battery.isCharging {
            if let minutes = system.minutesToFull, minutes > 0, minutes < 0x7fff {
                return "\(Self.duration(minutes)) until full"
            }
            return "Charging"
        }
        if battery.isPluggedIn {
            return level >= 100 ? "Battery Is Charged" : "Charging On Hold"
        }
        if let minutes = system.batteryTimeRemainingMinutes {
            return "\(Self.duration(minutes)) remaining"
        }
        return nil
    }

    /// Join and leave thresholds: `SignificantEnergyFilter`.
    private var significantApps: [ProcessRow] { processes.significantEnergy }

    private static func duration(_ minutes: Int) -> String {
        "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }
}

private struct StatusLine: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 1)
    }
}

// MARK: - Bluetooth popover (side notch)

/// Bluetooth popover laid out like the macOS Bluetooth menu (Control
/// Center → Bluetooth): header switch, paired devices with no section
/// title, then Bluetooth Settings…. No reference equivalent in Atoll; the
/// device data is BluetoothMonitor's (Atoll-ported).
struct DuoBluetoothPopover: View {
    @ObservedObject var bluetooth: BluetoothMonitor
    let onClose: () -> Void

    /// Rows clicked to connect or disconnect, spinning until the next refresh.
    @State private var pendingIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bluetooth").font(.system(size: 13, weight: .bold))
                Spacer()
                Toggle("", isOn: Binding(get: { bluetooth.isPoweredOn }, set: { bluetooth.setPower($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
            if bluetooth.isPoweredOn, !shownDevices.isEmpty {
                DuoMenuSeparator()
                ForEach(shownDevices) { device in
                    deviceRow(device)
                }
            }
            DuoMenuSeparator()
            DuoMenuRow {
                onClose()
                SystemSettings.open(.bluetooth)
            } content: {
                Text("Bluetooth Settings\u{2026}").font(.system(size: 13))
                Spacer()
            }
        }
        .padding(.bottom, 6)
        .frame(width: 316)
        .onReceive(bluetooth.$devices) { _ in
            // Published on every refresh, including the one `toggle` schedules.
            if !pendingIDs.isEmpty { pendingIDs = [] }
        }
    }

    /// Like the macOS menu: accessories only. iPhone, iPad, Watch, HomePod
    /// and Apple TV are paired through iCloud and cannot be connected from
    /// here. Connected devices always show. Before system_profiler has
    /// answered, the names are the only clue.
    private var shownDevices: [BTDevice] {
        bluetooth.devices.filter { device in
            if device.isConnected { return true }
            let name = device.name.lowercased()
            if let accessories = bluetooth.accessoryNames { return accessories.contains(name) }
            return !["iphone", "ipad", "watch", "homepod", "apple tv"].contains { name.contains($0) }
        }
    }

    private func deviceRow(_ device: BTDevice) -> some View {
        let nearby = !device.isConnected && isNearby(device)
        return DuoMenuRow {
            pendingIDs.insert(device.id)
            bluetooth.toggle(device)
        } content: {
            DuoCircleIcon(symbol: device.kind.symbolName, isActive: device.isConnected)
            Text(device.name)
                .font(.system(size: 13))
                .foregroundStyle(device.isConnected || nearby ? .primary : .tertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if pendingIDs.contains(device.id) {
                ProgressView().controlSize(.small)
            } else if device.isConnected, let level = Self.level(of: device) {
                HStack(spacing: 4) {
                    Text("\(level)%")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Image(systemName: Self.batterySymbol(level))
                        .font(.system(size: 13))
                        .foregroundStyle(level <= 20 ? Color.red : Color.secondary)
                }
            }
        }
    }

    /// AirPods resting in their case: system_profiler sees them, IOBluetooth
    /// calls them disconnected.
    private func isNearby(_ device: BTDevice) -> Bool {
        let name = device.name.lowercased()
        return bluetooth.nearbyDevices.contains { $0.name.lowercased() == name }
    }

    /// One level, as the macOS menu shows: the lower bud for AirPods. Nil
    /// when the device reports none (Keychron): never faked.
    static func level(of device: BTDevice) -> Int? {
        if let parts = device.parts {
            let buds = [parts.left, parts.right].compactMap { $0 }
            if let lowest = buds.min() { return lowest }
        }
        return device.batteryPercent
    }

    private static func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Sound popover laid out like the macOS Sound menu (Control Center →
/// Sound): volume slider, Output devices, Sound Settings…. Devices and
/// switching come from AudioRouteManager (Atoll port). AirPlay speakers
/// macOS has not connected to yet (a HomePod) are not CoreAudio devices,
/// so they are not listed: macOS finds those through private APIs.
struct DuoSoundPopover: View {
    @ObservedObject var volume: OutputVolumeMonitor
    @ObservedObject var routes: AudioRouteManager
    let onClose: () -> Void

    /// Built-in first, then by name: rows do not jump when the active one
    /// changes (AudioRouteManager puts the active device first).
    private var devices: [AudioOutputDevice] {
        routes.devices.sorted { lhs, rhs in
            let lBuiltIn = lhs.transportType == kAudioDeviceTransportTypeBuiltIn
            let rBuiltIn = rhs.transportType == kAudioDeviceTransportTypeBuiltIn
            if lBuiltIn != rBuiltIn { return lBuiltIn }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sound")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { volume.isMuted ? 0 : Double(volume.level) },
                        set: { newValue in
                            HUDController.setVolume(Float(newValue))
                            if volume.isMuted, newValue > 0 { HUDController.setMuted(false) }
                        }
                    ), in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .disabled(!volume.canSetVolume)
            .opacity(volume.canSetVolume ? 1 : 0.4)
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
            DuoMenuSeparator()
            Text("Output")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
            ForEach(devices) { device in
                DuoMenuRow {
                    routes.select(device: device)
                } content: {
                    DuoCircleIcon(symbol: device.iconName, isActive: device.id == routes.activeDeviceID)
                    Text(device.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                }
            }
            DuoMenuSeparator()
            DuoMenuRow {
                onClose()
                SystemSettings.open(.sound)
            } content: {
                Text("Sound Settings\u{2026}").font(.system(size: 13))
                Spacer()
            }
        }
        .padding(.bottom, 6)
        .frame(width: 316)
    }
}
