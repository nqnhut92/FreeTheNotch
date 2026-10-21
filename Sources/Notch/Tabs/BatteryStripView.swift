import SwiftUI

/// Battery strip at the bottom of the Home page: two cards like the iOS
/// Batteries widget. The Mac on the left (ring, status, health, cycles,
/// temperature, power) and one ring per Bluetooth battery on the right
/// (`BatteryTile`). Not in Atoll; reads the same SystemMonitor /
/// BluetoothMonitor data as the menu-bar Power tab.
struct BatteryStripView: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var bluetooth: BluetoothMonitor

    var body: some View {
        HStack(spacing: 12) {
            macSection
                .padding(.horizontal, 16)
                .frame(width: 330, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(cardBackground)
            devicesCard(
                tiles: BatteryTile.tiles(
                    connected: bluetooth.devices.filter(\.isConnected), nearby: bluetooth.nearbyDevices)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardBackground)
        }
        .foregroundStyle(.white)
        // The battery temperature is read only while something shows it.
        .onAppear { system.setTemperaturesNeeded(true, by: .batteryStrip) }
        .onDisappear { system.setTemperaturesNeeded(false, by: .batteryStrip) }
    }

    @ViewBuilder
    private func devicesCard(tiles: [BatteryTile]) -> some View {
        if tiles.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .medium))
                Text("No devices reporting battery")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color(white: 0.72))
        } else {
            HStack(spacing: 0) {
                ForEach(tiles) { tile in
                    tileView(tile)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            .animation(.smooth(duration: 0.3), value: tiles.map(\.id))
        }
    }

    private var cardBackground: some View {
        // Dark backing first: with Liquid Glass the island fades out at the
        // bottom, and a white-only tint let the windows behind show through.
        NotchStyle.cardShape
            .fill(Color.black.opacity(0.55))
            .overlay(NotchCardBackground())
    }

    private var macSection: some View {
        HStack(spacing: 14) {
            BatteryRing(
                percent: system.batteryPercent,
                color: BatteryRingTint(percent: system.batteryPercent, charging: system.isCharging).color,
                lineWidth: 5
            ) {
                Text("\(system.batteryPercent)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(width: 56, height: 56)
            .overlay(alignment: .top) { chargingBolt(system.isCharging) }

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacBook")
                        .font(.system(size: 14, weight: .semibold))
                    Text(statusLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(system.isCharging ? Color.green : Color(white: 0.8))
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    detail("heart.fill", "\(system.batteryHealthPercent)%", help: "Health")
                    detail("arrow.triangle.2.circlepath", "\(system.batteryCycleCount)", help: "Cycles")
                    detail(
                        "thermometer.medium",
                        system.batteryTemperature.map { "\($0.formatted(.number.precision(.fractionLength(0))))°C" }
                            ?? "—", help: "Temperature")
                    detail("powerplug.fill", powerText, help: "Power")
                }
            }
        }
    }

    private func tileView(_ tile: BatteryTile) -> some View {
        VStack(spacing: 5) {
            BatteryRing(
                percent: tile.percent,
                color: BatteryRingTint(percent: tile.percent, charging: false).color,
                lineWidth: 4
            ) {
                Image(systemName: tile.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 44, height: 44)
            VStack(spacing: 0) {
                Text("\(tile.percent)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(tile.label)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 4)
        .help("\(tile.label): \(tile.percent)%")
    }

    /// iOS puts the bolt on top of the ring, cutting through it.
    @ViewBuilder
    private func chargingBolt(_ charging: Bool) -> some View {
        if charging {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.green)
                .padding(1.5)
                .background(Circle().fill(Color(white: 0.11)))
                .offset(y: -5)
        }
    }

    private var statusLine: String {
        if system.isCharging {
            if let m = system.minutesToFull, m > 0 { return "Charging · \(BatteryTile.duration(minutes: m)) to full" }
            return "Charging"
        }
        if system.isOnACPower { return system.batteryPercent >= 100 ? "Fully charged" : "On power adapter" }
        if let m = system.batteryTimeRemainingMinutes, m > 0 {
            return "On battery · \(BatteryTile.duration(minutes: m)) left"
        }
        return "On battery"
    }

    private var powerText: String {
        if system.isOnACPower, let max = system.adapterMaxWatts {
            return "\(max.formatted(.number.precision(.fractionLength(0)))) W"
        }
        if let w = system.systemWatts { return "\(w.formatted(.number.precision(.fractionLength(1)))) W" }
        return "—"
    }

    private func detail(_ icon: String, _ value: String, help: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color(white: 0.72))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .help(help)
    }
}

/// iOS Batteries-widget ring: dim track, colored arc, content in the middle.
struct BatteryRing<Content: View>: View {
    let percent: Int
    let color: Color
    var lineWidth: CGFloat = 6
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, percent))) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.4), value: percent)
            content()
        }
        .padding(lineWidth / 2)
    }
}
