import SwiftUI

// The "Power" tab: battery charge (with the energy-hungry apps list), battery
// temperature, and how much the Mac draws overall, from the adapter, and
// to/from the battery. Rows the hardware cannot report are hidden; a Mac that
// reports nothing shows a short note instead.
// Ported from Vorssaint's PowerSection (vorssaint/vorssaint-utils,
// GPL-3.0-or-later).
struct PanelPowerSection: View {
    @EnvironmentObject var system: SystemMonitor

    private enum Block: CaseIterable {
        case charge, temperature, system, adapter, battery, remaining, health
    }

    /// SystemMonitor has no explicit "has internal battery" flag; the signed
    /// battery power is only ever set when AppleSmartBattery reports a voltage,
    /// so it doubles as one.
    private var hasBattery: Bool { system.batteryWatts != nil }

    private var blocks: [Block] { Block.allCases.filter(isVisible) }

    private func isVisible(_ block: Block) -> Bool {
        switch block {
        case .charge: return hasBattery
        case .temperature: return hasBattery && system.batteryTemperature != nil
        case .system: return system.systemWatts != nil
        case .adapter: return system.isOnACPower && system.adapterWatts != nil
        case .battery: return hasBattery
        case .remaining: return hasBattery && !system.isOnACPower && !system.isCharging
        case .health: return hasBattery
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if blocks.isEmpty {
                Text("Power metrics unavailable on this Mac")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.panelTertiary)
            }
            ForEach(Array(blocks.enumerated()), id: \.element) { index, block in
                if index > 0 { Divider() }
                blockContent(block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .panelCard()
    }

    @ViewBuilder
    private func blockContent(_ block: Block) -> some View {
        switch block {
        case .charge:
            chargeBlock
        case .temperature:
            PanelMetricRow(
                icon: "thermometer.medium", label: "Battery temperature",
                value: PanelFormat.temperature(celsius: system.batteryTemperature))
        case .system:
            if let watts = system.systemWatts {
                VStack(alignment: .leading, spacing: 6) {
                    PanelMetricRow(
                        icon: "bolt.fill", iconColor: PanelMetricColor.orange,
                        label: "System", value: PanelFormat.watts(watts))
                    if system.systemPowerHistory.count >= 2 {
                        let peak = PanelFormat.graphCeiling(
                            max(system.systemPowerHistory.max() ?? 0, 1),
                            unitStep: 1000)
                        PanelSparkline(
                            values: system.systemPowerHistory,
                            color: PanelMetricColor.orange,
                            maxValue: peak,
                            showsZeroBaseline: true,
                            ceilingLabel: PanelFormat.watts(peak))
                    }
                }
            }
        case .adapter:
            if let adapter = system.adapterWatts {
                PanelMetricRow(
                    icon: "powerplug.fill", iconColor: .accentColor,
                    label: "Adapter", caption: adapterCaption,
                    value: PanelFormat.watts(adapter))
            }
        case .battery:
            if let flow = system.batteryWatts {
                PanelMetricRow(
                    icon: flow >= 0 ? "battery.100.bolt" : "battery.50",
                    iconColor: flow >= 0 ? PanelMetricColor.green : .secondary,
                    label: "Battery",
                    caption: flow >= 0 ? "Charging" : "On battery",
                    value: PanelFormat.watts(abs(flow)))
            }
        case .remaining:
            let value = remainingText
            PanelMetricRow(
                icon: "clock", iconColor: PanelMetricColor.green,
                label: "Battery time remaining",
                caption: value == nil ? "Calculating…" : "System estimate",
                value: value ?? "...")
        case .health:
            PanelMetricRow(
                icon: "heart.fill", iconColor: PanelMetricColor.pink,
                label: "Battery health",
                caption: "\(system.batteryCycleCount) Cycles",
                value: "\(system.batteryHealthPercent)%")
        }
    }

    // MARK: - Charge

    /// External power earns the bolt whether or not a charge is running, so a
    /// Mac held at a limit is not drawn as one on its own battery.
    private var chargeSymbol: String {
        system.isCharging || system.isOnACPower ? "bolt.fill" : "battery.100"
    }

    private var chargeBlock: some View {
        let charge = system.batteryPercent
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: chargeSymbol)
                    .font(.system(size: 9))
                    .foregroundStyle(.panelSecondary)
                    .frame(width: 10)
                Text("Battery")
                    .font(.system(size: 11))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 52, alignment: .leading)
                // warn/critical thresholds above 1 disable UsageBar's own
                // high-usage coloring; the tint below is charge-based.
                UsageBar(
                    fraction: Double(charge) / 100, warnAt: 2, criticalAt: 2,
                    normalColor: chargeTint(charge))
                Text("\(charge)%")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            if system.batteryHistory.count >= 2 {
                // No ceiling label: a constant "100%" says nothing.
                PanelSparkline(
                    values: system.batteryHistory,
                    color: PanelMetricColor.green,
                    maxValue: 1,
                    showsZeroBaseline: true)
            }
            EnergyAppsBreakdown()
        }
    }

    private func chargeTint(_ charge: Int) -> Color {
        if charge < 20 { return PanelMetricColor.red }
        if charge < 40 { return PanelMetricColor.yellow }
        return PanelMetricColor.green
    }

    // MARK: - Captions / formatting

    private var adapterCaption: String {
        if let rated = system.adapterMaxWatts {
            return "\(PanelFormat.watts(rated)) max"
        }
        return "Plugged in"
    }

    /// "0h 42m" style, like Vorssaint's BatteryTimeSupport; nil until macOS
    /// has an estimate (or when it is implausible, a week or more).
    private var remainingText: String? {
        guard let minutes = system.batteryTimeRemainingMinutes,
            (1..<(7 * 24 * 60)).contains(minutes)
        else { return nil }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - Energy breakdown

/// Collapsible "Apps using significant energy" list inside the charge block.
private struct EnergyAppsBreakdown: View {
    @EnvironmentObject var processes: ProcessMonitor
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Apps using significant energy")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                if processes.topEnergy.isEmpty {
                    Text(processes.hasSamples ? "No significant energy use" : "Measuring…")
                        .foregroundStyle(.panelTertiary)
                } else {
                    ForEach(processes.topEnergy.prefix(15), id: \.name) { row in
                        ProcessRowView(
                            row: row,
                            valueText: String(format: "%.1f%%", locale: .current, row.value)
                        )
                        .padding(.leading, 16)
                    }
                }
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.panelSecondary)
        .onDisappear { expanded = false }
    }
}
