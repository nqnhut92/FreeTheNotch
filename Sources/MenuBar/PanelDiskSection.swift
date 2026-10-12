import AppKit
import SwiftUI

// The "Disks" tab: volume picker, usage, live I/O, SMART health, eject and
// tools. Layout, sizes and wording are ported from Vorssaint's DiskSection
// (vorssaint/vorssaint-utils, GPL-3.0-or-later).
struct PanelDiskSection: View {
    @EnvironmentObject var disks: DiskMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if disks.volumes.isEmpty {
                Text("No mounted disks found.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.panelTertiary)
            } else {
                diskSelector
                if let volume = disks.selected {
                    Divider()
                    usageBlock(volume)
                    Divider()
                    activityBlock(volume)
                    Divider()
                    smartBlock(volume)
                    Divider()
                    protectionBlock(volume)
                    Divider()
                    toolsBlock(volume)
                }
            }
        }
        .panelCard()
    }

    // MARK: - Selector

    private var diskSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Select disk")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.panelTertiary)
            LazyVGrid(columns: diskSelectorColumns, alignment: .leading, spacing: 6) {
                ForEach(disks.volumes) { volume in
                    diskSelectorButton(for: volume)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var diskSelectorColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96, maximum: 138), spacing: 6, alignment: .leading)]
    }

    private func diskSelectorButton(for volume: DiskVolume) -> some View {
        HStack(spacing: 0) {
            Button {
                disks.selectedID = volume.id
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                        .font(.system(size: 10, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(volume.name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(PanelFormat.percent(volume.usedFraction)) used")
                            .font(.system(size: 9))
                            .foregroundStyle(.panelSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
                .padding(.trailing, volume.isEjectable ? 2 : 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if volume.isEjectable {
                DiskSelectorEjectButton(state: disks.ejectStates[volume.id] ?? .idle) {
                    disks.eject(volume)
                }
                .padding(.trailing, 5)
            }
        }
        .background(selectorBackground(for: volume))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func selectorBackground(for volume: DiskVolume) -> some ShapeStyle {
        volume.id == disks.selected?.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)
    }

    // MARK: - Usage

    private func usageBlock(_ volume: DiskVolume) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            blockHeader("Disk usage")
            VStack(alignment: .leading, spacing: 5) {
                diskTitleRow(volume)
                DiskBar(fraction: volume.usedFraction)
                HStack(spacing: 6) {
                    Text("\(PanelFormat.percent(volume.usedFraction)) used")
                    Spacer()
                    Text("\(DiskFormat.diskBytes(volume.freeBytes)) available")
                }
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.panelSecondary)
                HStack(spacing: 6) {
                    Text("\(DiskFormat.diskBytes(volume.usedBytes)) / \(DiskFormat.diskBytes(volume.totalBytes))")
                    if volume.purgeableBytes >= 500_000_000 {
                        Spacer()
                        Text("\(DiskFormat.diskBytes(volume.purgeableBytes)) purgeable")
                    }
                }
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.panelTertiary)
            }
        }
    }

    // MARK: - Live activity

    private func activityBlock(_ volume: DiskVolume) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            blockHeader("Live activity")
            HStack(spacing: 10) {
                rateColumn(
                    icon: "arrow.down", label: "Read",
                    value: volume.readBps, color: .accentColor)
                Divider().frame(height: 28)
                rateColumn(
                    icon: "arrow.up", label: "Write",
                    value: volume.writeBps, color: PanelMetricColor.pink)
            }
            if disks.readHistory.count >= 2 {
                graph
            }
            HStack(spacing: 6) {
                Text("This session")
                    .font(.system(size: 10))
                    .foregroundStyle(.panelTertiary)
                Spacer()
                Text(
                    "↓ \(DiskFormat.diskBytes(volume.sessionReadBytes))  ↑ \(DiskFormat.diskBytes(volume.sessionWriteBytes))"
                )
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.panelSecondary)
            }
        }
    }

    private var graph: some View {
        let read = disks.readHistory
        let write = disks.writeHistory
        let peak = PanelFormat.graphCeiling(max(read.max() ?? 0, write.max() ?? 0, 1), unitStep: 1024)
        return PanelDualSparkline(
            first: read, firstColor: .accentColor,
            second: write, secondColor: PanelMetricColor.pink,
            maxValue: peak,
            ceilingLabel: DiskFormat.bytesPerSec(peak))
    }

    private func rateColumn(icon: String, label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(DiskFormat.bytesPerSec(value))
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.panelSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - SMART

    private func smartBlock(_ volume: DiskVolume) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            blockHeader("SMART")
            VStack(alignment: .leading, spacing: 5) {
                // The usage block above already shows the tags.
                diskTitleRow(volume, showsTags: false)
                if let smart = volume.smart, hasAnySMART(smart) {
                    smartRows(smart)
                } else {
                    Text("SMART unavailable for this disk")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.panelTertiary)
                }
            }
        }
    }

    private func hasAnySMART(_ smart: DiskSMART) -> Bool {
        smart.status != nil || smart.totalWrittenBytes != nil || smart.totalReadBytes != nil
            || smart.temperatureC != nil || smart.healthPercent != nil
            || smart.powerCycles != nil || smart.powerOnHours != nil
    }

    @ViewBuilder
    private func smartRows(_ smart: DiskSMART) -> some View {
        if let status = smart.status {
            smartRow("Status", status)
        }
        if let written = smart.totalWrittenBytes {
            smartRow("Total written", PanelFormat.diskBytesPrecise(Double(written)))
        }
        if let read = smart.totalReadBytes {
            smartRow("Total read", PanelFormat.diskBytesPrecise(Double(read)))
        }
        if let temp = smart.temperatureC {
            smartRow("Temperature", PanelFormat.temperature(celsius: temp))
        }
        if let health = smart.healthPercent {
            smartRow("Health", "\(health)%")
        }
        if let cycles = smart.powerCycles {
            smartRow("Power cycles", "\(cycles)")
        }
        if let hours = smart.powerOnHours {
            smartRow("Power on hours", "\(hours)")
        }
    }

    private func smartRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.panelSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    // MARK: - External protection

    private func protectionBlock(_ volume: DiskVolume) -> some View {
        let state = disks.ejectStates[volume.id] ?? .idle
        return VStack(alignment: .leading, spacing: 7) {
            blockHeader("External protection")
            HStack(spacing: 7) {
                Button {
                    disks.eject(volume)
                } label: {
                    Label("Eject", systemImage: "eject.fill")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(PanelButtonStyle())
                .controlSize(.small)
                .disabled(!volume.isEjectable || state == .ejecting)

                Button {
                    disks.ejectAll()
                } label: {
                    Label("Eject all", systemImage: "eject.fill")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(PanelButtonStyle())
                .controlSize(.small)
                .disabled(!disks.canEjectAny)
            }
            Text(volume.isEjectable ? ejectCaption(state) : "No external disk ready to eject.")
                .font(.system(size: 9.5))
                .foregroundStyle(
                    volume.isEjectable ? AnyShapeStyle(ejectCaptionColor(state)) : AnyShapeStyle(.panelSecondary)
                )
                .lineLimit(2)
        }
    }

    private func ejectCaption(_ state: DiskEjectState) -> String {
        switch state {
        case .ejecting: return "Ejecting…"
        case .ready: return "Ready to remove"
        case .failed: return "Could not eject"
        case .idle: return "Eject before unplugging."
        }
    }

    private func ejectCaptionColor(_ state: DiskEjectState) -> Color {
        switch state {
        case .ready: return PanelMetricColor.green
        case .failed: return PanelMetricColor.red
        default: return .secondary
        }
    }

    // MARK: - Tools

    private func toolsBlock(_ volume: DiskVolume) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            blockHeader("Tools")
            HStack(spacing: 8) {
                Text(volume.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    disks.openInFinder(volume)
                } label: {
                    Label("Open", systemImage: "folder")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(PanelButtonStyle())
                .controlSize(.small)
            }
            Button {
                SystemSettings.open(.storage)
            } label: {
                Label("Storage", systemImage: "gearshape")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(PanelButtonStyle())
            .controlSize(.small)
        }
    }

    // MARK: - Shared rows

    private func diskTitleRow(_ volume: DiskVolume, showsTags: Bool = true) -> some View {
        HStack(spacing: 6) {
            Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Text(volume.name)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if showsTags {
                if !volume.fileSystem.isEmpty {
                    titleTag(volume.fileSystem)
                }
                titleTag(volume.isInternal ? "Internal" : "External")
            }
        }
    }

    private func titleTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.panelSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private func blockHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.panelTertiary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Eject mini button (Vorssaint DiskSelectorEjectButton)

private struct DiskSelectorEjectButton: View {
    let state: DiskEjectState
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(hovering && !busy ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .ejecting:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.55)
        case .ready:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PanelMetricColor.green)
        case .failed:
            Image(systemName: "eject.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PanelMetricColor.red)
        case .idle:
            Image(systemName: "eject.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.panelSecondary))
        }
    }

    private var busy: Bool { state == .ejecting }

    private var help: String {
        switch state {
        case .ejecting: return "Ejecting…"
        case .ready: return "Ready to remove"
        case .failed: return "Could not eject"
        case .idle: return "Eject"
        }
    }
}

// MARK: - Usage bar (Vorssaint DiskUsageBar, animated)

private struct DiskBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(3, proxy.size.width * min(1, max(0, fraction))))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 6)
    }

    private var color: Color {
        switch fraction {
        case ..<0.75: return .accentColor
        case ..<0.9: return PanelMetricColor.yellow
        default: return PanelMetricColor.red
        }
    }
}

// MARK: - Formatting (Vorssaint MetricFormat port)

private enum DiskFormat {
    /// 1000-based disk sizes: one decimal under 10, none above; whole bytes.
    static func diskBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if index == 0 { return String(format: "%.0f B", locale: .current, value) }
        return value < 10
            ? String(format: "%.1f %@", locale: .current, value, units[index])
            : String(format: "%.0f %@", locale: .current, value, units[index])
    }

    /// 1024-based throughput, promoted when the rounded value reaches 1024: "1.2 MB/s".
    static func bytesPerSec(_ bytesPerSecond: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        while index < units.count - 1, value.rounded() >= 1024, index == 0 || value >= 10 {
            value /= 1024
            index += 1
        }
        let number: String
        if index == 0 {
            number = String(format: "%.0f", locale: .current, value)
        } else {
            number =
                value < 10
                ? String(format: "%.1f", locale: .current, value)
                : String(format: "%.0f", locale: .current, value)
        }
        return "\(number) \(units[index])/s"
    }
}
