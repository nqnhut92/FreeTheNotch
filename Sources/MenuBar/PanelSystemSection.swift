import AppKit
import SwiftUI

// The "System" tab: temperatures, hardware usage, memory pressure, uptime.
// Ported from Vorssaint's SystemSection, CPUCoreMatrix and ActivityMonitorButton
// (vorssaint/vorssaint-utils, GPL-3.0-or-later).
struct PanelSystemSection: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var processes: ProcessMonitor

    private enum Breakdown { case cpu, gpu, memory }
    @State private var expanded: Breakdown?
    /// The CPU apps list folds under the per-core bars; open by default.
    @AppStorage("panelSystemCPUAppsExpanded") private var cpuAppsExpanded = true
    private let breakdownLimit = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            temperatureGrid
            Divider()
            usageRows
            Divider()
            memoryRows
            Divider()
            uptimeRow
        }
        .panelCard()
        .onDisappear { expanded = nil }
    }

    private func toggle(_ kind: Breakdown) {
        expanded = expanded == kind ? nil : kind
    }

    private func subsectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.panelSecondary)
    }

    private func chevron(open: Bool) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.panelSecondary)
            .rotationEffect(.degrees(open ? 90 : 0))
    }

    // MARK: - Temperatures

    private var temperatureGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                subsectionLabel("Temperatures")
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if system.cpuTemperature != nil {
                    temperatureCell(icon: "cpu", label: "CPU", value: system.cpuTemperature)
                }
                if system.gpuTemperature != nil {
                    temperatureCell(icon: "memorychip", label: "GPU", value: system.gpuTemperature)
                }
            }
            if system.cpuTemperature == nil, system.gpuTemperature == nil {
                Text("Sensors unavailable on this Mac")
                    .font(.system(size: 10))
                    .foregroundStyle(.panelTertiary)
            }
        }
    }

    private func temperatureCell(icon: String, label: String, value: Double?) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.panelSecondary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.panelSecondary)
            }
            Text(value.map { PanelFormat.temperature(celsius: $0) } ?? "-")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    // MARK: - Hardware usage

    private var usageRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                subsectionLabel("Hardware usage")
                Spacer(minLength: 0)
                ActivityMonitorButton()
            }
            usageRow(label: "CPU", fraction: system.cpuUsage, kind: .cpu)
            if system.cpuHistory.count >= 2 {
                PanelSparkline(values: system.cpuHistory, color: .accentColor, maxValue: 1)
            }
            if expanded == .cpu {
                if !system.cpuCoreUsages.isEmpty {
                    CPUCoreMatrix(
                        usage: system.cpuCoreUsages.map { Optional($0) },
                        groups: system.cpuCoreGroups)
                }
                Button {
                    cpuAppsExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        chevron(open: cpuAppsExpanded)
                        subsectionLabel("Apps using CPU")
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if cpuAppsExpanded {
                breakdownList(for: .cpu)
            }
            usageRow(label: "GPU", fraction: system.gpuUsage, kind: .gpu)
            if system.gpuHistory.count >= 2 {
                PanelSparkline(values: system.gpuHistory, color: PanelMetricColor.cyan, maxValue: 1)
            }
            breakdownList(for: .gpu)
        }
    }

    private func usageRow(label: String, fraction: Double?, kind: Breakdown) -> some View {
        Button {
            toggle(kind)
        } label: {
            HStack(spacing: 8) {
                chevron(open: expanded == kind)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 52, alignment: .leading)
                UsageBar(fraction: fraction ?? 0, normalColor: .accentColor)
                Text(fraction.map { String(format: "%.0f%%", locale: .current, $0 * 100) } ?? "-")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Per-app breakdown

    private func rows(for kind: Breakdown) -> [ProcessRow] {
        let rows: [ProcessRow]
        switch kind {
        case .cpu: rows = processes.topCPU
        case .gpu: rows = processes.topGPU
        case .memory: rows = processes.topMemory
        }
        return Array(rows.prefix(breakdownLimit))
    }

    private func breakdownValue(_ row: ProcessRow, for kind: Breakdown) -> String {
        kind == .memory
            ? PanelFormat.memory(UInt64(max(0, row.value)))
            : String(format: "%.1f%%", locale: .current, row.value)
    }

    @ViewBuilder
    private func breakdownList(for kind: Breakdown) -> some View {
        if expanded == kind {
            let rows = processes.hasSamples ? rows(for: kind) : []
            VStack(alignment: .leading, spacing: 4) {
                if rows.isEmpty {
                    Text("Measuring…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.panelTertiary)
                        .padding(.leading, 38)
                } else {
                    ForEach(rows) { row in
                        ProcessRowView(row: row, valueText: breakdownValue(row, for: kind))
                            .padding(.leading, 38)
                    }
                }
            }
        }
    }

    // MARK: - Memory

    private var memoryRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                subsectionLabel("Memory")
                Spacer(minLength: 0)
            }
            Button {
                toggle(.memory)
            } label: {
                HStack(spacing: 8) {
                    chevron(open: expanded == .memory)
                    Text("Pressure")
                        .font(.system(size: 11))
                        .foregroundStyle(.panelSecondary)
                    PressurePill(level: system.memoryPressureLevel)
                    Spacer()
                    if system.memoryTotalBytes > 0 {
                        Text(
                            "\(PanelFormat.memory(system.memoryUsedBytes)) / \(PanelFormat.memory(system.memoryTotalBytes))"
                        )
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.panelSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Our readings are non-optional; before the first sample
            // (total == 0) they count as missing, as nil does in Vorssaint.
            let sampled = system.memoryTotalBytes > 0
            memorySecondaryRow("Compressed", sampled ? system.memoryCompressedBytes : nil)
            memorySecondaryRow("Cached files", sampled ? system.memoryCachedBytes : nil)
            memorySecondaryRow("Swap used", sampled ? system.memorySwapBytes : nil)
            if system.memoryHistory.count >= 2 {
                PanelSparkline(values: system.memoryHistory, color: PanelMetricColor.mint, maxValue: 1)
            }
            breakdownList(for: .memory)
        }
    }

    @ViewBuilder
    private func memorySecondaryRow(_ title: String, _ bytes: UInt64?) -> some View {
        if let bytes {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.panelSecondary)
                Spacer()
                Text(PanelFormat.memory(bytes))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.panelSecondary)
            }
            .padding(.leading, 16)
        }
    }

    // MARK: - Uptime

    private var uptimeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 9))
                .foregroundStyle(.panelSecondary)
            Text("Up for \(PanelFormat.uptime(system.uptimeSeconds))")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.panelSecondary)
            Spacer()
        }
    }
}

// MARK: - Activity Monitor button

private struct ActivityMonitorButton: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            let fallback = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
            let url =
                NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") ?? fallback
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open Activity Monitor")
        .accessibilityLabel("Open Activity Monitor")
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - CPU core matrix

/// One bar per logical core, grouped by core class (Performance, Efficiency…)
/// and wrapped to the available width.
private struct CPUCoreMatrix: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var width: CGFloat = 280
    let usage: [Double?]
    let groups: [CPUCoreGroup]

    var body: some View {
        let layout = CPUCoreLayout.rows(groups: groups, width: max(70, width - 16))
        let rowCount = CGFloat(layout.count)
        let height: CGFloat = rowCount * 88 + max(0, rowCount - 1) * 12 + 16
        GeometryReader { proxy in
            grid(layout)
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, value in width = value }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Logical CPU cores")
        .accessibilityHint(
            "Each bar is one logical core. Its fill height shows utilization, not remaining performance.")
    }

    private func grid(_ layout: [[CPUCoreSegment]]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(layout.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(layout[row].indices, id: \.self) { index in
                        coreGroup(layout[row][index])
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func coreGroup(_ segment: CPUCoreSegment) -> some View {
        let name =
            switch segment.group.name.lowercased() {
            case "super": "Super"
            case "performance": "Performance"
            case "efficiency": "Efficiency"
            default: segment.group.name
            }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(segment.group.indices, id: \.self) { index in
                    coreBar(index, width: segment.barWidth)
                }
            }
            Text("\(name) ×\(segment.group.indices.count)")
                .font(.subheadline)
                .foregroundStyle(.panelSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 22, alignment: .topLeading)
        }
        .frame(width: segment.width, alignment: .leading)
    }

    private func coreBar(_ index: Int, width: Double) -> some View {
        let value: Double? = index < usage.count ? usage[index].map { min(1, max(0, $0)) } : nil
        let increasedContrast = contrast == .increased
        return GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.035))
                if let value {
                    Rectangle()
                        .fill(Color.primary.opacity(0.78))
                        .frame(height: proxy.size.height * value)
                } else {
                    Text("–").font(.subheadline).foregroundStyle(.panelSecondary)
                        .frame(maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        Color.primary.opacity(increasedContrast ? 0.65 : 0.25),
                        style: StrokeStyle(
                            lineWidth: increasedContrast ? 1.5 : 0.75,
                            dash: value == nil ? [2, 2] : []))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value)
        }
        .frame(width: width, height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Core \(index + 1)")
        .accessibilityValue(value.map { PanelFormat.percent($0) } ?? "–")
    }
}

private struct CPUCoreSegment {
    let group: CPUCoreGroup
    let width: Double
    /// Every bar shares one scale, so a class that wraps onto a row of its
    /// own never gets wider bars than faster cores.
    var barWidth: Double = 14
}

private enum CPUCoreLayout {
    /// Packs groups side by side into rows of `width` points, splitting a group
    /// that cannot keep 14 pt bars into balanced chunks. Groups sit 12 pt apart
    /// and bars 4 pt apart; spare width goes to groups by weighted core count,
    /// and the tightest group sets the bar scale for all of them.
    static func rows(groups: [CPUCoreGroup], width: Double) -> [[CPUCoreSegment]] {
        guard width.isFinite, width >= 70 else { return [] }
        func minimum(_ group: CPUCoreGroup) -> Double {
            max(70, Double(group.indices.count) * 14 * group.weight + Double(group.indices.count - 1) * 4)
        }
        var packed: [[CPUCoreGroup]] = []
        var row: [CPUCoreGroup] = []
        var used = 0.0
        for group in groups where !group.indices.isEmpty {
            let limit = min(12, max(1, Int((width + 4) / (14 * group.weight + 4))))
            let chunkCount = (group.indices.count + limit - 1) / limit
            let baseCount = group.indices.count / chunkCount
            let remainder = group.indices.count % chunkCount
            var offset = 0
            for part in 0..<chunkCount {
                let count = baseCount + (part < remainder ? 1 : 0)
                let chunk = CPUCoreGroup(name: group.name, indices: Array(group.indices[offset..<(offset + count)]))
                offset += count
                let required = minimum(chunk)
                if !row.isEmpty, used + 12 + required > width {
                    packed.append(row)
                    row = []
                    used = 0
                }
                used += (row.isEmpty ? 0 : 12) + required
                row.append(chunk)
            }
        }
        if !row.isEmpty { packed.append(row) }
        let sized = packed.map { row in
            let available = width - Double(row.count - 1) * 12
            let minimums = row.map(minimum)
            let extra = max(0, available - minimums.reduce(0, +))
            let weights = row.map { Double($0.indices.count) * $0.weight }
            let total = weights.reduce(0, +)
            return row.indices.map { index in
                CPUCoreSegment(group: row[index], width: minimums[index] + extra * weights[index] / total)
            }
        }
        let scale =
            sized.joined().map { segment -> Double in
                let count = Double(segment.group.indices.count)
                return (segment.width - (count - 1) * 4) / count / (14 * segment.group.weight)
            }.min() ?? 1
        return sized.map { row in
            row.map { CPUCoreSegment(group: $0.group, width: $0.width, barWidth: 14 * $0.group.weight * scale) }
        }
    }
}
