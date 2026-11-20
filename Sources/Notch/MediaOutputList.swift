// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// NotchHomeView.swift — MediaOutputPickerButton, MediaOutputSelectorPopover, AirPlaySelectorPopover and
// AirPlayVolumeSlider. The list is drawn like Music's own AirPlay menu instead of Atoll's.

import SwiftUI

/// Where the sound goes, laid out like the AirPlay menu in Music: an icon, the name, the device's own volume while
/// it is on, and a checkbox. For Music the devices are Music's AirPlay outputs (several at once); for every other
/// source they are the CoreAudio outputs (one at a time).
struct MediaOutputList: View {
    let usesMusicAirPlay: Bool

    @ObservedObject private var routeManager = AudioRouteManager.shared
    @ObservedObject private var airPlayManager = AppleMusicAirPlayManager.shared

    static let width: CGFloat = 420
    private static let rowSpacing: CGFloat = 14
    private static let padding: CGFloat = 16
    private static let scrollsFromRows = 6
    private static let maxScrollHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            if usesMusicAirPlay {
                airPlayRows
            } else {
                routeRows
            }
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .onAppear(perform: refresh)
        .onChange(of: usesMusicAirPlay) { _, _ in refresh() }
    }

    private func refresh() {
        if usesMusicAirPlay {
            Task { await airPlayManager.refreshDevices() }
        } else {
            routeManager.refreshDevices()
        }
    }

    @ViewBuilder
    private var airPlayRows: some View {
        if airPlayManager.devices.isEmpty {
            emptyText(airPlayManager.isLoading ? "Searching…" : "No AirPlay Devices")
        } else {
            FittingScrollView(
                scrolls: airPlayManager.devices.count > Self.scrollsFromRows, maxHeight: Self.maxScrollHeight
            ) {
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(airPlayManager.devices) { device in
                        OutputRow(symbol: device.iconName, name: device.name, isOn: device.isSelected) {
                            AirPlayVolumeSlider(airPlayManager: airPlayManager, deviceID: device.id)
                        } toggle: {
                            Task { await airPlayManager.toggleDevice(device) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var routeRows: some View {
        if routeManager.devices.isEmpty {
            emptyText("No audio outputs available")
        } else {
            FittingScrollView(
                scrolls: routeManager.devices.count > Self.scrollsFromRows, maxHeight: Self.maxScrollHeight
            ) {
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(routeManager.devices) { device in
                        OutputRow(
                            symbol: device.iconName, name: device.name, isOn: device.id == routeManager.activeDeviceID
                        ) {
                            SystemVolumeSlider()
                        } toggle: {
                            routeManager.select(device: device)
                        }
                    }
                }
            }
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum OutputRowMetrics {
    static let iconWidth: CGFloat = 30
    static let sliderWidth: CGFloat = 100
}

/// One output: icon, name, the volume slider while it is on, and the checkbox.
private struct OutputRow<Volume: View>: View {
    let symbol: String
    let name: String
    let isOn: Bool
    @ViewBuilder var volume: Volume
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: OutputRowMetrics.iconWidth)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.system(size: 14))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if isOn {
                volume
                    .frame(width: OutputRowMetrics.sliderWidth)
            }
            OutputCheckbox(isOn: isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

/// The rounded square of Music's AirPlay menu: filled with a check while the output is on.
struct OutputCheckbox: View {
    let isOn: Bool

    static let tint = Color(red: 0.20, green: 0.55, blue: 1.0)
    private static let side: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isOn ? Self.tint : Color.primary.opacity(0.14))
            .frame(width: Self.side, height: Self.side)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
    }
}

/// Local @State slider, decoupled from the manager's published state so a
/// refresh mid-drag does not reset it (Atoll).
private struct AirPlayVolumeSlider: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager
    let deviceID: String

    @State private var sliderValue: Double = 0
    @State private var isSyncing = false

    var body: some View {
        Slider(value: $sliderValue, in: 0...100)
            .controlSize(.small)
            .tint(OutputCheckbox.tint)
            .onAppear {
                isSyncing = true
                sliderValue = Double(airPlayManager.currentVolume(for: deviceID))
                isSyncing = false
            }
            .onChange(of: sliderValue) { _, newValue in
                guard !isSyncing else { return }
                airPlayManager.setVolume(Int(newValue), for: deviceID)
            }
    }
}

/// The output volume of the Mac, for the output that is on.
private struct SystemVolumeSlider: View {
    @State private var level: Double = 0
    @State private var isSyncing = false

    var body: some View {
        Slider(value: $level, in: 0...1)
            .controlSize(.small)
            .tint(OutputCheckbox.tint)
            .onAppear {
                isSyncing = true
                level = Double(HUDController.outputVolume().0)
                isSyncing = false
            }
            .onChange(of: level) { _, newValue in
                guard !isSyncing else { return }
                HUDController.setVolume(Float(newValue))
                if HUDController.outputVolume().1, newValue > 0 { HUDController.setMuted(false) }
            }
    }
}

/// Plain content for short lists (so a popover sizes to it), a fixed-height
/// ScrollView for long ones.
struct FittingScrollView<Content: View>: View {
    let scrolls: Bool
    let maxHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if scrolls {
            ScrollView { content }.frame(height: maxHeight)
        } else {
            content
        }
    }
}

/// The output button of the notch player: a popover with the list.
struct MediaOutputPickerButton: View {
    var useMusicAirPlay = false
    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 14))
                .foregroundStyle(isPopoverPresented ? OutputCheckbox.tint : .white)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(useMusicAirPlay ? "AirPlay" : "Audio output")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            MediaOutputList(usesMusicAirPlay: useMusicAirPlay)
        }
        // The popover is its own window: hovering it must not close the notch.
        .onChange(of: isPopoverPresented) { _, open in
            NotchPopoverTracker.shared.isOpen = open
        }
        .onDisappear { NotchPopoverTracker.shared.isOpen = false }
    }
}
