// Layout copies the macOS Wi-Fi menu (Control Center → Wi-Fi).

import AppKit
import SwiftUI

/// Wi-Fi popover opened from DuoGlyph.
struct DuoGlyphPopover: View {
    @ObservedObject var wifi: WiFiMonitor
    /// Closes the popover (before a System Settings pane opens).
    let onClose: () -> Void

    /// Secured network whose password field is open.
    @State private var passwordSSID: String?
    @State private var password = ""
    @State private var showsOtherNetworks = false

    private static let rowHeight: CGFloat = 34  // 26 pt icon + 2 × 4 pt
    private static let maxListHeight: CGFloat = 288

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let ethernet = wifi.ethernetLabel {
                Text(ethernet)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
            if wifi.isPoweredOn {
                if wifi.isLocationAuthorized {
                    knownNetworks
                    otherNetworks
                } else {
                    if wifi.isConnected {
                        DuoMenuSeparator()
                        DuoMenuSectionTitle("Known Networks")
                        currentNetworkRow
                    }
                    DuoMenuSeparator()
                    locationNotice
                }
                if let error = wifi.joinError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                }
            }
            DuoMenuSeparator()
            DuoMenuRow {
                open(.network)
            } content: {
                Text("Network Settings\u{2026}").font(.system(size: 13))
                Spacer()
            }
            DuoMenuRow {
                open(.wifi)
            } content: {
                Text("Wi-Fi Settings\u{2026}").font(.system(size: 13))
                Spacer()
            }
        }
        .padding(.bottom, 6)
        .frame(width: 316)
        .onChange(of: wifi.passwordNeededSSID) { _, ssid in
            guard let ssid else { return }
            password = ""
            passwordSSID = ssid
            // Not inside this view update (see the tab switch below).
            DispatchQueue.main.async { wifi.passwordNeededSSID = nil }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("Wi-Fi").font(.system(size: 13, weight: .bold))
            Spacer()
            Toggle("", isOn: Binding(get: { wifi.isPoweredOn }, set: { wifi.setPower($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!wifi.hasInterface)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// Current network first (blue), then saved networks in range.
    @ViewBuilder
    private var knownNetworks: some View {
        let known = wifi.networks.filter { wifi.knownSSIDs.contains($0.ssid) && $0.ssid != wifi.ssid }
        if wifi.isConnected || !known.isEmpty {
            DuoMenuSeparator()
            DuoMenuSectionTitle("Known Networks")
            if wifi.isConnected { currentNetworkRow }
            ForEach(known) { networkRow($0) }
        }
    }

    private var currentNetworkRow: some View {
        DuoMenuRow {
            open(.wifi)
        } content: {
            NetworkIcon(bars: wifi.bars, isActive: true)
            Text(wifi.ssid ?? "Wi-Fi").font(.system(size: 13)).lineLimit(1)
            Spacer()
            if wifi.networks.first(where: { $0.ssid == wifi.ssid })?.isSecure ?? true {
                lockIcon
            }
        }
    }

    @ViewBuilder
    private var otherNetworks: some View {
        let others = wifi.networks.filter { !wifi.knownSSIDs.contains($0.ssid) && $0.ssid != wifi.ssid }
        DuoMenuSeparator()
        DuoMenuRow {
            withAnimation(.easeInOut(duration: 0.2)) { showsOtherNetworks.toggle() }
            if showsOtherNetworks { wifi.scan() }
        } content: {
            Text("Other Networks")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            if showsOtherNetworks, wifi.isScanning {
                ProgressView().controlSize(.mini)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(showsOtherNetworks ? 90 : 0))
        }
        if showsOtherNetworks {
            if others.isEmpty {
                Text(wifi.isScanning ? "Searching\u{2026}" : "No other networks")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(others) { networkRow($0) }
                    }
                }
                // A bare ScrollView takes all offered height; give it exactly
                // its rows (capped) so the popover hugs short lists.
                .frame(height: min(listHeight(others), Self.maxListHeight))
            }
        }
    }

    private func listHeight(_ networks: [WiFiNetworkItem]) -> CGFloat {
        let passwordRow: CGFloat = networks.contains { $0.ssid == passwordSSID } ? 34 : 0
        return CGFloat(networks.count) * Self.rowHeight + passwordRow
    }

    private func networkRow(_ network: WiFiNetworkItem) -> some View {
        VStack(spacing: 0) {
            DuoMenuRow {
                select(network)
            } content: {
                NetworkIcon(bars: network.bars, isActive: false)
                Text(network.ssid).font(.system(size: 13)).lineLimit(1)
                Spacer()
                if wifi.joiningSSID == network.ssid {
                    ProgressView().controlSize(.small)
                } else if network.isSecure {
                    lockIcon
                }
            }
            if passwordSSID == network.ssid {
                HStack(spacing: 6) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { join(network) }
                    Button("Join") { join(network) }
                        .controlSize(.small)
                        .disabled(password.isEmpty || wifi.joiningSSID != nil)
                }
                .frame(height: 34)
                .padding(.leading, 56)
                .padding(.trailing, 14)
            }
        }
    }

    private var lockIcon: some View {
        Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.tertiary)
    }

    private var locationNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Network names need Location access.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if wifi.authorization == .notDetermined {
                Button("Allow Location Access") { wifi.requestLocationAccess() }
                    .controlSize(.small)
            } else {
                Button("Open Location Services Settings") { open(.locationServices) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }

    // MARK: Actions

    /// Known networks try to join directly (macOS menu behaviour); other
    /// secured networks ask for the password first.
    private func select(_ network: WiFiNetworkItem) {
        guard wifi.joiningSSID == nil else { return }
        if network.isSecure, !wifi.knownSSIDs.contains(network.ssid) {
            password = ""
            passwordSSID = passwordSSID == network.ssid ? nil : network.ssid
        } else {
            passwordSSID = nil
            wifi.join(network, password: nil)
        }
    }

    private func join(_ network: WiFiNetworkItem) {
        guard !password.isEmpty else { return }
        wifi.join(network, password: password)
        password = ""
        passwordSSID = nil
    }

    private func open(_ pane: SystemSettings.Pane) {
        onClose()
        SystemSettings.open(pane)
    }
}

/// Round badge with the Wi-Fi symbol: blue for the joined network, grey otherwise.
private struct NetworkIcon: View {
    let bars: Int
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle().fill(isActive ? Color.accentColor : Color.primary.opacity(0.1))
            Image(systemName: "wifi", variableValue: DuoGlyphCanvas.wifiVariableValue(bars: bars))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .frame(width: 26, height: 26)
    }
}

/// Full-width row with the menu-style hover highlight.
struct DuoMenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content }
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Shared menu pieces

/// Full-width hairline between menu sections.
struct DuoMenuSeparator: View {
    var body: some View {
        Divider().padding(.horizontal, 14).padding(.vertical, 5)
    }
}

/// Grey section heading ("Known Networks", "Energy Mode").
struct DuoMenuSectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 3)
    }
}

/// Round badge with a symbol: blue when selected, grey otherwise.
struct DuoCircleIcon: View {
    /// No SF Symbol matches macOS's High Power glyph (a battery holding
    /// ▸▸▸), so this name draws one from an empty battery and triangles.
    static let highPower = "ftn.highpower"

    let symbol: String
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle().fill(isActive ? Color.accentColor : Color.primary.opacity(0.1))
            Group {
                if symbol == Self.highPower {
                    ZStack {
                        Image(systemName: "battery.0percent")
                        HStack(spacing: 0.5) {
                            ForEach(0..<3, id: \.self) { _ in
                                Image(systemName: "play.fill").font(.system(size: 3.5, weight: .bold))
                            }
                        }
                        .offset(x: -1)
                    }
                } else {
                    Image(systemName: symbol)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Combined DuoGlyph popover (Wi-Fi | Battery | Sound)

/// The DuoGlyph shows three things (Wi-Fi, battery, volume) but has one
/// click, so its popover holds the three macOS menus behind a segmented
/// switch, like Control Center's modules. No reference equivalent: one
/// left click instead of left/right/other clicks.
enum DuoGlyphTab: String, CaseIterable {
    case wifi, battery, sound

    var title: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .battery: return "Battery"
        case .sound: return "Sound"
        }
    }
}

/// Selected tab, owned by SideNotchWindowController so it can refresh the
/// tab that is about to show. Kept for the session: the popover reopens on
/// the last tab used.
final class DuoGlyphPopoverState: ObservableObject {
    @Published var tab: DuoGlyphTab = .wifi
}

struct DuoGlyphCombinedPopover: View {
    @ObservedObject var state: DuoGlyphPopoverState
    @ObservedObject var wifi: WiFiMonitor
    @ObservedObject var battery: BatteryHUDController
    @ObservedObject var system: SystemMonitor
    @ObservedObject var processes: ProcessMonitor
    @ObservedObject var energy: EnergyModeController
    @ObservedObject var volume: OutputVolumeMonitor
    let onClose: () -> Void
    /// Called when the user switches tab, to refresh what it shows.
    let onTabChange: (DuoGlyphTab) -> Void

    /// The segmented Picker writes here, not to `state.tab`: bound straight
    /// to a `@Published` property, the AppKit-backed segmented control sets
    /// it inside the view update and SwiftUI logs "Publishing changes from
    /// within view updates". `state.tab` follows on the next turn.
    @State private var tab: DuoGlyphTab?

    private var shownTab: DuoGlyphTab { tab ?? state.tab }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(get: { shownTab }, set: { tab = $0 })) {
                ForEach(DuoGlyphTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.top, 12)
            switch shownTab {
            case .wifi:
                DuoGlyphPopover(wifi: wifi, onClose: onClose)
            case .battery:
                DuoBatteryPopover(
                    battery: battery, system: system, processes: processes,
                    energy: energy, onClose: onClose)
            case .sound:
                DuoSoundPopover(volume: volume, routes: AudioRouteManager.shared, onClose: onClose)
            }
        }
        .frame(width: 316)
        // Next run-loop turn: state.tab and the refresh (Wi-Fi clears
        // joinError and starts a scan) publish at once.
        .onChange(of: tab) { _, tab in
            guard let tab else { return }
            DispatchQueue.main.async {
                state.tab = tab
                onTabChange(tab)
            }
        }
    }
}
