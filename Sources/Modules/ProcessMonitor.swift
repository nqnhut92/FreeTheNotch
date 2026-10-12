import AppKit
import Foundation
import IOKit

// Top processes per resource for the panel's expandable breakdown rows.
// CPU/memory via libproc (proc_pid_rusage deltas), GPU via the IOAccelerator
// user clients' accumulatedGPUTime (public IOKit), network via nettop.
// Approach follows Vorssaint's ProcessUsageService (GPL-3.0-or-later).
struct ProcessRow: Identifiable {
    let pid: pid_t
    var name: String
    var icon: NSImage?
    /// CPU/GPU/energy: percent 0…100. Memory: bytes. Network: bytes/sec.
    var value: Double
    var downBps: Double?
    var upBps: Double?
    var id: pid_t { pid }
}

final class ProcessMonitor: ObservableObject {
    @Published private(set) var topCPU: [ProcessRow] = []
    @Published private(set) var topMemory: [ProcessRow] = []
    @Published private(set) var topGPU: [ProcessRow] = []
    @Published private(set) var topEnergy: [ProcessRow] = []
    @Published private(set) var topNetwork: [ProcessRow] = []
    /// True once at least one full sampling interval has elapsed.
    @Published private(set) var hasSamples = false

    private var timer: Timer?
    private var netTimer: Timer?
    private var lastCPU: [pid_t: UInt64] = [:]
    private var lastCPUDate = Date.distantPast
    private var lastGPU: [pid_t: Double] = [:]
    private var lastGPUDate = Date.distantPast
    private var timebaseNumer: UInt64 = 1
    private var timebaseDenom: UInt64 = 1
    private var iconCache: [pid_t: NSImage] = [:]
    private let workQueue = DispatchQueue(label: "FreeTheNotch.ProcessMonitor", qos: .utility)

    static let breakdownLimit = 15
    static let networkLimit = 6

    init() {
        var tb = mach_timebase_info_data_t()
        if mach_timebase_info(&tb) == KERN_SUCCESS, tb.denom != 0 {
            timebaseNumer = UInt64(tb.numer)
            timebaseDenom = UInt64(tb.denom)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        workQueue.async { [weak self] in self?.refresh() }
    }

    // MARK: - Network sampling (on demand; nettop is expensive)

    func startNetworkSampling() {
        guard netTimer == nil else { return }
        workQueue.async { [weak self] in self?.sampleNetwork() }
        netTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.workQueue.async { self.sampleNetwork() }
        }
    }

    func stopNetworkSampling() {
        netTimer?.invalidate()
        netTimer = nil
    }

    // MARK: - Main refresh (CPU / memory / GPU)

    private func refresh() {
        workQueue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            let usage = Self.resourceUsagePerPid(timebaseNumer: self.timebaseNumer, timebaseDenom: self.timebaseDenom)
            let cpuTimes = usage.cpuNanoseconds
            let footprints = usage.footprints
            let gpuTimes = Self.gpuTimePerPid()
            // Icons are cached per owner pid; drop the ones whose process is
            // gone so the cache neither grows nor hands a reused pid the
            // wrong icon.
            self.iconCache = self.iconCache.filter { usage.livePids.contains($0.key) }

            var cpuRows: [ProcessRow] = []
            var memRows: [ProcessRow] = []
            var gpuRows: [ProcessRow] = []

            let cpuElapsed = now.timeIntervalSince(self.lastCPUDate)
            if cpuElapsed >= 2, !self.lastCPU.isEmpty {
                let elapsedNs = cpuElapsed * 1_000_000_000
                for (pid, ns) in cpuTimes {
                    guard let before = self.lastCPU[pid], ns > before else { continue }
                    let pct = Double(ns - before) / elapsedNs * 100
                    guard pct >= 0.1 else { continue }
                    let (owner, name, icon) = self.ownerNameAndIcon(for: pid)
                    cpuRows.append(
                        ProcessRow(
                            pid: owner, name: name, icon: icon,
                            value: min(pct, 100 * Double(self.ncpu))))
                }
            }
            for (pid, bytes) in footprints where bytes > 0 {
                let (owner, name, icon) = self.ownerNameAndIcon(for: pid)
                memRows.append(ProcessRow(pid: owner, name: name, icon: icon, value: Double(bytes)))
            }
            let gpuElapsed = now.timeIntervalSince(self.lastGPUDate)
            if gpuElapsed >= 2, !self.lastGPU.isEmpty {
                let elapsedNs = gpuElapsed * 1_000_000_000
                for (pid, total) in gpuTimes {
                    guard let before = self.lastGPU[pid], total > before else { continue }
                    let pct = (total - before) / elapsedNs * 100
                    guard pct >= 0.05 else { continue }
                    let (owner, name, icon) = self.ownerNameAndIcon(for: pid)
                    gpuRows.append(ProcessRow(pid: owner, name: name, icon: icon, value: min(pct, 100)))
                }
            }
            self.lastCPU = cpuTimes
            self.lastCPUDate = now
            self.lastGPU = gpuTimes
            self.lastGPUDate = now

            // Roll every helper into its app first, then take the top rows.
            let groupedCPU = Self.grouped(cpuRows)
            let groupedMem = Self.grouped(memRows)
            let groupedGPU = Self.grouped(gpuRows)
            // Energy: combined CPU + GPU share per app.
            // Rows carry the owner pid, so CPU + GPU merge per app.
            let energy = Self.grouped(groupedCPU + groupedGPU)

            DispatchQueue.main.async {
                self.topCPU = Array(groupedCPU.prefix(Self.breakdownLimit))
                self.topMemory = Array(groupedMem.prefix(Self.breakdownLimit))
                self.topGPU = Array(groupedGPU.prefix(Self.breakdownLimit))
                self.topEnergy = Array(energy.prefix(Self.breakdownLimit))
                self.hasSamples = true
            }
        }
    }

    /// Sums rows per responsible app (rows already carry the owner pid),
    /// largest first.
    static func grouped(_ rows: [ProcessRow]) -> [ProcessRow] {
        var byOwner: [pid_t: ProcessRow] = [:]
        for row in rows {
            if var existing = byOwner[row.pid] {
                existing.value += row.value
                if let d = row.downBps { existing.downBps = (existing.downBps ?? 0) + d }
                if let u = row.upBps { existing.upBps = (existing.upBps ?? 0) + u }
                byOwner[row.pid] = existing
            } else {
                byOwner[row.pid] = row
            }
        }
        return byOwner.values.sorted { $0.value > $1.value }
    }

    /// Vorssaint's ResponsibleProcess: bill a helper to the app responsible
    /// for it, named and iconed like that app. Daemons keep their own name
    /// and the generic executable icon.
    private func ownerNameAndIcon(for pid: pid_t) -> (pid_t, String, NSImage) {
        let owner = ResponsibleProcess.owner(of: pid)
        let name = ResponsibleProcess.displayName(pid: owner, fallback: "pid \(owner)")
        if let cached = iconCache[owner] { return (owner, name, cached) }
        let icon =
            NSRunningApplication(processIdentifier: owner)?.icon
            ?? NSWorkspace.shared.icon(for: .unixExecutable)
        iconCache[owner] = icon
        return (owner, name, icon)
    }

    private var ncpu: Int { max(1, ProcessInfo.processInfo.processorCount) }

    // MARK: - libproc sampling

    /// CPU time (ns) and memory footprint of every process, from one
    /// `proc_pid_rusage` pass, plus every pid that exists right now.
    private static func resourceUsagePerPid(
        timebaseNumer: UInt64, timebaseDenom: UInt64
    ) -> (cpuNanoseconds: [pid_t: UInt64], footprints: [pid_t: UInt64], livePids: Set<pid_t>) {
        var cpu: [pid_t: UInt64] = [:]
        var footprints: [pid_t: UInt64] = [:]
        let pids = allPids()
        for pid in pids {
            var info = rusage_info_current()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
                }
            }
            guard status == 0 else { continue }
            let total = info.ri_user_time.addingReportingOverflow(info.ri_system_time)
            if !total.overflow {
                cpu[pid] = total.partialValue * timebaseNumer / timebaseDenom
            }
            if info.ri_phys_footprint > 0 {
                footprints[pid] = info.ri_phys_footprint
            }
        }
        return (cpu, footprints, Set(pids))
    }

    private static func allPids() -> [pid_t] {
        let estimate = max(1, Int(proc_listallpids(nil, 0)))
        var pids = [pid_t](repeating: 0, count: estimate + 32)
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return [] }
        return pids.prefix(min(Int(count), pids.count)).filter { $0 > 0 }
    }

    // MARK: - GPU time via IOAccelerator

    /// Walks the accelerator's user clients and sums `accumulatedGPUTime`
    /// (nanoseconds of GPU work since the context was created) per process.
    private static func gpuTimePerPid() -> [pid_t: Double] {
        var perPid: [pid_t: Double] = [:]
        var accelIterator = io_iterator_t()
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("IOAccelerator"),
                &accelIterator) == kIOReturnSuccess
        else { return perPid }
        defer { IOObjectRelease(accelIterator) }
        var accelerator = IOIteratorNext(accelIterator)
        while accelerator != 0 {
            defer {
                IOObjectRelease(accelerator)
                accelerator = IOIteratorNext(accelIterator)
            }
            var clients = io_iterator_t()
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients) == kIOReturnSuccess else {
                continue
            }
            defer { IOObjectRelease(clients) }
            var client = IOIteratorNext(clients)
            while client != 0 {
                defer {
                    IOObjectRelease(client)
                    client = IOIteratorNext(clients)
                }
                guard
                    let creatorRef = IORegistryEntryCreateCFProperty(
                        client, "IOUserClientCreator" as CFString,
                        kCFAllocatorDefault, 0),
                    let creator = creatorRef.takeRetainedValue() as? String,
                    let pid = pidFromCreator(creator)
                else { continue }
                guard
                    let usageRef = IORegistryEntryCreateCFProperty(
                        client, "AppUsage" as CFString,
                        kCFAllocatorDefault, 0),
                    let usage = usageRef.takeRetainedValue() as? [[String: Any]]
                else { continue }
                for entry in usage {
                    if let time = entry["accumulatedGPUTime"] as? Double {
                        perPid[pid, default: 0] += time
                    } else if let time = entry["accumulatedGPUTime"] as? Int64 {
                        perPid[pid, default: 0] += Double(time)
                    }
                }
            }
        }
        return perPid
    }

    /// "pid 437, WindowServer" -> 437
    static func pidFromCreator(_ creator: String) -> pid_t? {
        guard creator.hasPrefix("pid ") else { return nil }
        let digits = creator.dropFirst(4).prefix { $0.isNumber }
        return pid_t(digits)
    }

    // MARK: - Network via nettop

    private func sampleNetwork() {
        // -d -L 2: the first sample is lifetime totals, the second is the
        // per-second delta we want.
        let arguments = ["-P", "-d", "-t", "external", "-J", "bytes_in,bytes_out", "-L", "2", "-s", "1"]
        guard let output = Subprocess.run("/usr/bin/nettop", arguments: arguments, timeout: 10), output.succeeded
        else { return }
        let rows = Self.parseNettop(output.text).map { sample in
            let (owner, name, icon) = ownerNameAndIcon(for: sample.pid)
            return ProcessRow(
                pid: owner, name: name, icon: icon,
                value: sample.bytesIn + sample.bytesOut,
                downBps: sample.bytesIn, upBps: sample.bytesOut)
        }
        let grouped = Self.grouped(rows)
        DispatchQueue.main.async {
            self.topNetwork = Array(grouped.prefix(Self.networkLimit))
        }
    }

    struct NettopSample: Equatable {
        let pid: pid_t
        let bytesIn: Double
        let bytesOut: Double
    }

    /// Lines look like "15:02:09.224695,MSTeams.730,10404,36328," under a
    /// "time,,bytes_in,bytes_out," header: the pid is the suffix after the
    /// last "." of the (15-character truncated) name. Only the second block,
    /// the per-second delta, counts; idle processes are skipped.
    static func parseNettop(_ output: String) -> [NettopSample] {
        var samples: [NettopSample] = []
        var block = 0
        for line in output.split(separator: "\n") {
            if line.hasPrefix("time,") {
                block += 1
                continue
            }
            guard block == 2 else { continue }
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 4,
                let dot = cols[1].lastIndex(of: "."),
                let pid = pid_t(cols[1][cols[1].index(after: dot)...]), pid > 0,
                let bytesIn = Double(cols[2]), let bytesOut = Double(cols[3]),
                bytesIn + bytesOut > 0
            else { continue }
            samples.append(NettopSample(pid: pid, bytesIn: bytesIn, bytesOut: bytesOut))
        }
        return samples
    }
}

// MARK: - Responsible process (Vorssaint's ResponsibleProcess, GPL-3.0-or-later)

enum ResponsibleProcess {
    /// `responsibility_get_pid_responsible_for_pid`, exported by libsystem and
    /// used by the system for the same grouping; resolved at runtime so a
    /// missing symbol degrades to per-process rows instead of breaking.
    private static let resolve: (@convention(c) (pid_t) -> pid_t)? = {
        // RTLD_DEFAULT: search every image loaded in the process.
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(defaultHandle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    static func owner(of pid: pid_t) -> pid_t {
        guard let resolve else { return pid }
        let owner = resolve(pid)
        return owner > 0 ? owner : pid
    }

    /// The app's localized name; system processes fall back to their kernel
    /// name, then their executable name (macOS 27 refuses proc_name for
    /// another user's process).
    static func displayName(pid: pid_t, fallback: String) -> String {
        if let app = NSRunningApplication(processIdentifier: pid),
            let name = app.localizedName, !name.isEmpty
        {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            let name = String(cString: buffer)
            if !name.isEmpty { return name }
        }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            let name = (String(cString: path) as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        return fallback
    }
}
