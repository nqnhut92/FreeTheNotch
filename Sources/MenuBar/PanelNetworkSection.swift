import Darwin
import SwiftUI
import SystemConfiguration

// The "Network" tab: live speeds, per-app usage, session totals, local
// address and a Cloudflare speed test. Layout, sizes and formatting are
// ported from Vorssaint's NetworkSection, MetricFormat and
// NetworkAddressService (vorssaint/vorssaint-utils, GPL-3.0-or-later).
struct PanelNetworkSection: View {
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var processes: ProcessMonitor
    @EnvironmentObject var speedTest: SpeedTest

    /// Bits or bytes per second for every live speed in this card.
    @AppStorage("panelNetworkSpeedInBits") private var speedInBits = false
    @State private var localAddresses: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            speedBlock
            Divider()
            appsBlock
            Divider()
            totalsRow
            Divider()
            addressRow
            Divider()
            speedTestRow
        }
        // SideNotchWindowController samples per-app traffic while this shows.
        .panelCard()
    }

    // MARK: - Speed

    private var speedBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                rateColumn(
                    icon: "arrow.down", label: "Download",
                    value: hasSample ? system.downloadBps : nil,
                    color: .accentColor)
                Divider().frame(height: 28)
                rateColumn(
                    icon: "arrow.up", label: "Upload",
                    value: hasSample ? system.uploadBps : nil,
                    color: PanelMetricColor.green)
                speedUnitToggle
            }
            if system.downloadHistory.count >= 2 {
                graph
            }
        }
    }

    /// The first sample needs two readings; until then the columns say "Measuring…".
    private var hasSample: Bool { !system.downloadHistory.isEmpty }

    /// Flips every live speed in this card between bits and bytes per second.
    /// The label shows the unit in use.
    private var speedUnitToggle: some View {
        let symbol = speedInBits ? "bit/s" : "B/s"
        return Button {
            speedInBits.toggle()
        } label: {
            Text(symbol)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.panelSecondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Network speed unit · \(speedInBits ? "bit/s → B/s" : "B/s → bit/s")")
        .accessibilityLabel("Network speed unit")
        .accessibilityValue(symbol)
    }

    private func rateColumn(icon: String, label: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.map { NetFormat.networkRate($0, inBits: speedInBits) } ?? "Measuring…")
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

    /// Download (filled) and upload (line) share one scale so they compare fairly.
    private var graph: some View {
        let down = system.downloadHistory
        let up = system.uploadHistory
        let peak = NetFormat.networkGraphCeiling(
            max(down.max() ?? 0, up.max() ?? 0, 1),
            inBits: speedInBits)
        return PanelDualSparkline(
            first: down, firstColor: .accentColor,
            second: up, secondColor: PanelMetricColor.green,
            maxValue: peak,
            ceilingLabel: NetFormat.networkRate(peak, inBits: speedInBits))
    }

    // MARK: - Apps

    private var appsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Apps using network")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.panelTertiary)
                Spacer(minLength: 0)
            }
            if processes.topNetwork.isEmpty {
                Text(processes.hasNetworkSamples ? "No apps using network now" : "Measuring…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.panelTertiary)
            } else {
                ForEach(processes.topNetwork) { row in
                    ProcessRowView(row: row, valueText: networkValue(row))
                }
            }
        }
    }

    private func networkValue(_ row: ProcessRow) -> String {
        let down = row.downBps ?? 0
        let up = row.upBps ?? 0
        return
            "↓\(NetFormat.networkRateCompact(down, inBits: speedInBits)) ↑\(NetFormat.networkRateCompact(up, inBits: speedInBits))"
    }

    // MARK: - Session totals

    private var totalsRow: some View {
        HStack(spacing: 6) {
            Text("This session")
                .font(.system(size: 10))
                .foregroundStyle(.panelTertiary)
            Spacer()
            if hasSample {
                Text("↓\(NetFormat.bytes(system.netSessionDown))  ↑\(NetFormat.bytes(system.netSessionUp))")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.panelSecondary)
            }
        }
    }

    // MARK: - Local address

    /// Read from the local interface list only; nothing leaves the machine.
    private var addressRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("Local IPv4")
                .font(.system(size: 10))
                .foregroundStyle(.panelTertiary)
            Spacer()
            // Nothing connected: the value is left out, like the totals row.
            // One line per interface, right-aligned (Vorssaint). A single
            // joined Text would wrap a long USB LAN name and truncate it,
            // hiding the Wi-Fi line.
            if !localAddresses.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(localAddresses, id: \.self) { address in
                        Text(address)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.panelSecondary)
                .textSelection(.enabled)
                .layoutPriority(1)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { refreshAddresses() }
        .onReceive(system.$downloadBps) { _ in refreshAddresses() }
        .onDisappear { localAddresses = [] }
    }

    private func refreshAddresses() {
        let fresh = LocalAddressReader.read()
        if fresh != localAddresses { localAddresses = fresh }
    }

    // MARK: - Speed test

    private var speedTestRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if speedTest.phase == .testing {
                    ProgressView().controlSize(.small)
                    Text("Testing…")
                        .font(.system(size: 11))
                        .foregroundStyle(.panelSecondary)
                } else {
                    Button {
                        speedTest.run()
                    } label: {
                        Label(
                            speedTest.downMbps == nil ? "Speed test" : "Test again",
                            systemImage: "gauge.with.dots.needle.67percent"
                        )
                        .font(.system(size: 11))
                    }
                    .buttonStyle(PanelButtonStyle())
                    .controlSize(.small)
                }
                Spacer()
                if let down = speedTest.downMbps, let up = speedTest.upMbps {
                    Text("↓\(NetFormat.mbps(down)) ↑\(NetFormat.mbps(up)) Mbps")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            if speedTest.phase == .failed {
                Text("Test failed")
                    .font(.system(size: 10))
                    .foregroundStyle(PanelMetricColor.orange)
            } else if let latency = speedTest.latencyMs {
                Text("Latency: \(Int(latency.rounded())) ms")
                    .font(.system(size: 10))
                    .foregroundStyle(.panelTertiary)
            }
        }
    }
}

// MARK: - Formatting (Vorssaint MetricFormat port)

private enum NetFormat {
    static var locale: Locale { .current }

    /// Splits a byte count into a value + unit, base 1024. A value that only
    /// reaches 1024 once rounded is promoted, so 1 MB never reads "1024 KB".
    static func scale(_ bytes: Double) -> (value: Double, unit: String) {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = bytes.isFinite ? max(0, bytes) : 0
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        while index < units.count - 1, value.rounded() >= 1024, index == 0 || value >= 10 {
            value /= 1024
            index += 1
        }
        return (value, units[index])
    }

    /// One decimal under 10, none at or above; whole bytes.
    private static func number(_ value: Double, unit: String) -> String {
        if unit == "B" { return String(format: "%.0f", locale: locale, value) }
        return value < 10
            ? String(format: "%.1f", locale: locale, value)
            : String(format: "%.0f", locale: locale, value)
    }

    /// A whole quantity of bytes, e.g. "1.2 GB". Used for session totals.
    static func bytes(_ bytes: UInt64) -> String {
        let (value, unit) = scale(Double(bytes))
        return "\(number(value, unit: unit)) \(unit)"
    }

    /// "1.2 MB/s".
    static func bytesPerSec(_ bytesPerSecond: Double) -> String {
        let (value, unit) = scale(bytesPerSecond)
        return "\(number(value, unit: unit)) \(unit)/s"
    }

    /// "1.2M", "320K", "0B".
    static func bytesPerSecCompact(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G", "T", "P"]
        var value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        while index < units.count - 1 {
            if index == 0 {
                guard value.rounded() >= 1024 else { break }
            } else if value >= 10 {
                guard value.rounded() >= 1024 else { break }
            } else {
                break
            }
            value /= 1024
            index += 1
        }
        if index == 0 { return "\(Int(value.rounded()))B" }
        if value < 10 {
            let rounded = (value * 10).rounded() / 10
            if rounded >= 10 { return "\(Int(rounded.rounded()))\(units[index])" }
            return String(format: "%.1f%@", locale: locale, rounded, units[index])
        }
        return "\(Int(value.rounded()))\(units[index])"
    }

    /// Takes bytes per second, shows bits with 1000 steps: "12 Mbps".
    static func bitsPerSec(_ bytesPerSecond: Double) -> String {
        let units = ["bps", "Kbps", "Mbps", "Gbps", "Tbps", "Pbps"]
        var value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) * 8 : 0
        var index = 0
        while index < units.count - 1, value.rounded() >= 1000 {
            value /= 1000
            index += 1
        }
        if index == 0 { return String(format: "%.0f %@", locale: locale, value, units[index]) }
        return value < 10
            ? String(format: "%.1f %@", locale: locale, value, units[index])
            : String(format: "%.0f %@", locale: locale, value, units[index])
    }

    /// "9.6Mb", "320Kb", "0b". Never wider than "999Kb".
    static func bitsPerSecCompact(_ bytesPerSecond: Double) -> String {
        let units = ["b", "Kb", "Mb", "Gb", "Tb", "Pb"]
        var value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) * 8 : 0
        var index = 0
        while index < units.count - 1 {
            let shown = value < 10 && index > 0 ? (value * 10).rounded() / 10 : value.rounded()
            guard shown >= 1000 else { break }
            value /= 1000
            index += 1
        }
        if index == 0 { return "\(Int(value.rounded()))b" }
        if value < 10 {
            let rounded = (value * 10).rounded() / 10
            if rounded >= 10 { return "\(Int(rounded.rounded()))\(units[index])" }
            return String(format: "%.1f%@", locale: locale, rounded, units[index])
        }
        return "\(Int(value.rounded()))\(units[index])"
    }

    static func networkRate(_ bytesPerSecond: Double, inBits: Bool) -> String {
        inBits ? bitsPerSec(bytesPerSecond) : bytesPerSec(bytesPerSecond)
    }

    static func networkRateCompact(_ bytesPerSecond: Double, inBits: Bool) -> String {
        inBits ? bitsPerSecCompact(bytesPerSecond) : bytesPerSecCompact(bytesPerSecond)
    }

    /// A ceiling in bytes/s that lands on a round number in the chosen unit.
    static func networkGraphCeiling(_ peakBytesPerSecond: Double, inBits: Bool) -> Double {
        guard inBits else { return PanelFormat.graphCeiling(peakBytesPerSecond, unitStep: 1024) }
        return PanelFormat.graphCeiling(peakBytesPerSecond * 8, unitStep: 1000) / 8
    }

    /// Speed-test result: "%.0f" from 100, "%.1f" below.
    static func mbps(_ value: Double) -> String {
        value >= 100
            ? String(format: "%.0f", locale: locale, value)
            : String(format: "%.1f", locale: locale, value)
    }
}

// MARK: - Local addresses (Vorssaint NetworkAddressService port)

private enum LocalAddressReader {
    private static let excludedPrefixes = [
        "lo", "gif", "stf", "awdl", "llw", "nan", "utun", "bridge",
        "ap", "anpi", "p2p", "XHC", "vmenet", "tap", "tun",
    ]

    /// Every up and running IPv4 interface as "192.168.1.4 (Wi-Fi)", sorted.
    static func read() -> [String] {
        let names = connectionNames()
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var addresses = Set<String>()
        var current = first
        while let entry = current?.pointee {
            defer { current = entry.ifa_next }
            guard let address = entry.ifa_addr else { continue }
            let name = String(cString: entry.ifa_name)
            let upRunning = UInt32(IFF_UP | IFF_RUNNING)
            guard Int32(address.pointee.sa_family) == AF_INET,
                entry.ifa_flags & upRunning == upRunning,
                !name.isEmpty,
                !excludedPrefixes.contains(where: { name.hasPrefix($0) })
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard
                getnameinfo(
                    address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                    nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let ip = String(cString: host)
            // The system knows en0 as "Wi-Fi"; the BSD name means nothing on screen.
            addresses.insert(names[name].map { "\(ip) (\($0))" } ?? ip)
        }
        return addresses.sorted()
    }

    /// The system's own name per interface ("Wi-Fi", "Ethernet"), keyed by BSD name.
    private static func connectionNames() -> [String: String] {
        var names: [String: String] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            else { continue }
            names[bsd] = display
        }
        return names
    }
}
