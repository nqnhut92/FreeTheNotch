import Foundation
import IOKit
import IOKit.ps

/// System stats: battery (IOKit power sources), CPU load and memory pressure
/// (host_statistics), network throughput (getifaddrs deltas), temperatures
/// and wattage (SMC, AppleSmartBattery).
///
/// The menu-bar panel UI follows Vorssaint's design (vorssaint/vorssaint-utils,
/// GPL-3.0-or-later); SMCClient.swift is ported from that project.
final class SystemMonitor: ObservableObject {
    // MARK: Battery
    @Published private(set) var batteryPercent: Int = 100
    /// The battery is actually taking charge (kIOPSIsChargingKey).
    @Published private(set) var isCharging: Bool = false
    /// On adapter power. Plugged in and not charging = "Charging On Hold"
    /// (charge limit, Optimized Charging) or full.
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var minutesToFull: Int?
    @Published private(set) var batteryCycleCount: Int = 0
    @Published private(set) var batteryHealthPercent: Int = 100

    // MARK: CPU / GPU / memory (0…1)
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var gpuUsage: Double = 0
    @Published private(set) var memoryPressure: Double = 0

    // MARK: Network (bytes/sec, sampled)
    @Published private(set) var downloadBps: Double = 0
    @Published private(set) var uploadBps: Double = 0
    /// Cumulative bytes since the app started (gaps > 10s are ignored).
    @Published private(set) var netSessionDown: UInt64 = 0
    @Published private(set) var netSessionUp: UInt64 = 0

    // MARK: Temperatures (SMC, Celsius; nil when the sensor is missing)
    @Published private(set) var cpuTemperature: Double?
    @Published private(set) var gpuTemperature: Double?
    @Published private(set) var batteryTemperature: Double?

    // MARK: Power (watts)
    /// Total system power draw (SMC PSTR). Falls back to |battery| on discharge.
    @Published private(set) var systemWatts: Double?
    /// Adapter input power (SMC PDTR).
    @Published private(set) var adapterWatts: Double?
    /// Charger rating (AppleSmartBattery AdapterDetails).
    @Published private(set) var adapterMaxWatts: Double?
    /// Signed battery power: positive = charging, negative = discharging.
    @Published private(set) var batteryWatts: Double?
    @Published private(set) var isOnACPower = false
    @Published private(set) var batteryTimeRemainingMinutes: Int?

    // MARK: Memory detail (bytes)
    @Published private(set) var memoryUsedBytes: UInt64 = 0
    @Published private(set) var memoryTotalBytes: UInt64 = 0
    @Published private(set) var memoryCompressedBytes: UInt64 = 0
    @Published private(set) var memoryCachedBytes: UInt64 = 0
    @Published private(set) var memorySwapBytes: UInt64 = 0
    /// 1 = normal, 2 = warning, 4 = critical (kern.memorystatus_vm_pressure_level).
    @Published private(set) var memoryPressureLevel: Int = 1

    // MARK: Per-core CPU (0…1 each, for the expanded core matrix)
    @Published private(set) var cpuCoreUsages: [Double] = []

    /// Core classes (Performance, Efficiency, …) with their indices into
    /// `cpuCoreUsages`, in perflevel order. One "CPU" group when the
    /// topology cannot be read or does not match the sampled core count.
    var cpuCoreGroups: [CPUCoreGroup] { CPUCoreTopology.groups(for: cpuCoreUsages.count) }

    // MARK: Uptime
    /// Wall-clock time since boot, including sleep (kern.boottime), like
    /// Vorssaint's SystemInfo.wallClockUptimeSeconds. Falls back to
    /// ProcessInfo.systemUptime (which excludes sleep).
    @Published private(set) var uptimeSeconds: TimeInterval = SystemMonitor.wallClockUptime()

    // MARK: History for live graphs (last 60 samples)
    static let historyLength = 60
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var uploadHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var batteryHistory: [Double] = []
    @Published private(set) var systemPowerHistory: [Double] = []

    static func wallClockUptime(now: Date = Date()) -> TimeInterval {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0, bootTime.tv_sec > 0
        else { return ProcessInfo.processInfo.systemUptime }
        let boot = Double(bootTime.tv_sec) + Double(bootTime.tv_usec) / 1_000_000
        let elapsed = now.timeIntervalSince1970 - boot
        guard elapsed.isFinite, elapsed >= 0 else { return ProcessInfo.processInfo.systemUptime }
        return elapsed.rounded(.down)
    }

    private func pushHistory(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
    }

    private var timer: Timer?
    private static let sampleInterval: TimeInterval = 2
    /// Lets the system coalesce the wake-up with others.
    private static let sampleTolerance: TimeInterval = 0.5
    /// Temperatures are read only while something shows them.
    private var temperatureDemand = SamplingDemand<TemperatureClient>()
    private var lastSample = NetworkSample()
    /// `mach_host_self()` adds a send right on every call; one is kept for
    /// the monitor's lifetime instead of leaking one per sample.
    private let hostPort = mach_host_self()
    private var lastCPUTicks = CPUTicks()
    private var lastCoreTicks: [CPUTicks] = []
    /// Nil until the background key discovery finishes.
    private var smcSensors: SMCSensors?

    /// The SMC connection and the keys found for each sensor.
    private struct SMCSensors {
        let client: SMCClient
        let cpuCoreKeys: [SMCClient.Key]
        let cpuFallbackKeys: [SMCClient.Key]
        let gpuKeys: [SMCClient.Key]
        let batteryKeys: [SMCClient.Key]
        let systemPowerKey: SMCClient.Key?
        let adapterPowerKey: SMCClient.Key?
    }

    /// Owned by the lock-screen manager; kept here so previews share it.
    let weather = WeatherService()

    /// What shows temperatures, so they are read only while one of these is
    /// on screen.
    enum TemperatureClient: Hashable {
        /// The System or Power tab of a Side Notch or menu bar popover.
        case panel
        /// The battery strip on the notch's Home page.
        case batteryStrip
    }

    init() {
        refreshBatteryPower()
        refreshBattery()
        refreshBatteryDetails()
        weather.refresh()
        discoverSMCKeys()
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Power first: refreshBattery reads isOnACPower.
            self.refreshBatteryPower()
            self.refreshBattery()
            self.refreshExactHealth()
            self.refreshCPU()
            self.refreshCPUCores()
            self.refreshMemory()
            self.refreshGPU()
            self.refreshNetwork()
            self.refreshSystemPower()
            if self.temperatureDemand.isActive { self.refreshTemperatures() }
            self.uptimeSeconds = SystemMonitor.wallClockUptime()
        }
        timer.tolerance = Self.sampleTolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Adds or removes `client`'s need for temperatures. They are read at
    /// once when the first client arrives. Main thread only.
    func setTemperaturesNeeded(_ isNeeded: Bool, by client: TemperatureClient) {
        guard temperatureDemand.set(isNeeded, by: client), temperatureDemand.isActive else { return }
        refreshTemperatures()
    }

    deinit {
        timer?.invalidate()
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    /// Called right before the lock-screen widgets appear.
    func refreshForLockScreen() {
        refreshBatteryPower()
        refreshBattery()
        weather.refresh()
    }

    // MARK: Battery

    private func refreshBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
            let source = list.first,
            let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else { return }

        let capacity = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 100
        let max = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
        batteryPercent = max > 0 ? Int(Double(capacity) / Double(max) * 100) : 100
        let state = desc[kIOPSPowerSourceStateKey as String] as? String
        isPluggedIn = state == (kIOPSACPowerValue as String)
        // Not "on AC and below 100 %": a charge held at a limit is not charging.
        isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
        minutesToFull = desc[kIOPSTimeToFullChargeKey as String] as? Int
        pushHistory(Double(batteryPercent) / 100.0, to: &batteryHistory)
        // Time to empty is only meaningful while discharging on battery.
        if let mins = desc[kIOPSTimeToEmptyKey as String] as? Int,
            mins > 0, mins < 0x7fff, !isCharging, !isOnACPower
        {
            batteryTimeRemainingMinutes = mins
        } else {
            batteryTimeRemainingMinutes = nil
        }
    }

    /// Cycle count and health (max/design capacity) from AppleSmartBattery.
    private func refreshBatteryDetails() {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("AppleSmartBattery"),
                &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if let cycles = IORegistryEntryCreateCFProperty(
            service, "CycleCount" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        {
            batteryCycleCount = cycles
        }
        // Fallback health: full-charge capacity over design capacity. macOS 27
        // keeps these keys only inside the BatteryData dictionary.
        let design = batteryInt(service, "DesignCapacity") ?? 0
        let fullCharge =
            batteryInt(service, "NominalChargeCapacity")
            ?? batteryInt(service, "FullChargeCapacity")
            ?? batteryInt(service, "AppleRawMaxCapacity")
        if let fullCharge, design > 0 {
            batteryHealthPercent = min(100, Int(Double(fullCharge) / Double(design) * 100))
        }
        refreshExactHealth()
    }

    /// The exact "Maximum Capacity" System Information shows (98% where the
    /// raw ratio says 95%); replaces the fallback once system_profiler answers.
    private func refreshExactHealth() {
        MaxCapacityProbe.shared.refreshIfStale { [weak self] percent in
            DispatchQueue.main.async { self?.batteryHealthPercent = percent }
        }
    }

    private func batteryInt(_ service: io_service_t, _ key: String) -> Int? {
        if let v = IORegistryEntryCreateCFProperty(
            service, key as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        {
            return v
        }
        let data =
            IORegistryEntryCreateCFProperty(
                service, "BatteryData" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
        return (data?[key] as? NSNumber)?.intValue
    }

    // MARK: CPU

    private func refreshCPU() {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let ticks = CPUTicks(
            user: info.cpu_ticks.0, system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { lastCPUTicks = ticks }
        if let usage = ticks.busyFraction(since: lastCPUTicks) {
            cpuUsage = usage
            pushHistory(cpuUsage, to: &cpuHistory)
        }
    }

    // MARK: Memory

    private func refreshMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let total = used + Double(stats.free_count + stats.inactive_count)
        if total > 0 {
            memoryPressure = used / total
            pushHistory(memoryPressure, to: &memoryHistory)
        }
        var pageSize: vm_size_t = 0
        host_page_size(hostPort, &pageSize)
        let ps = UInt64(pageSize)
        memoryUsedBytes = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * ps
        memoryTotalBytes =
            UInt64(
                stats.active_count + stats.wire_count + stats.compressor_page_count
                    + stats.free_count + stats.inactive_count) * ps
        memoryCompressedBytes = UInt64(stats.compressor_page_count) * ps
        memoryCachedBytes = UInt64(stats.inactive_count) * ps
        memorySwapBytes = Self.swapUsedBytes()
        memoryPressureLevel = Self.memoryPressureLevel()
    }

    private static func swapUsedBytes() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    private static func memoryPressureLevel() -> Int {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 1 }
        return Int(level)
    }

    // MARK: GPU

    /// GPU utilization via the public IOAccelerator IORegistry entry.
    /// Reads only "PerformanceStatistics" (not the whole tree) to keep
    /// sampling cheap. Key: "Device Utilization %".
    private func refreshGPU() {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("IOAccelerator"),
                &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        guard
            let stats = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
            let utilization = stats["Device Utilization %"] as? Int
        else { return }
        gpuUsage = Double(utilization) / 100.0
        pushHistory(gpuUsage, to: &gpuHistory)
    }

    // MARK: Network

    private struct NetworkSample {
        var down: UInt64 = 0
        var up: UInt64 = 0
        var time = Date()
    }

    private func refreshNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var down: UInt64 = 0
        var up: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            if isUp && !isLoopback, let data = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                down += UInt64(data.pointee.ifi_ibytes)
                up += UInt64(data.pointee.ifi_obytes)
            }
            cursor = ptr.pointee.ifa_next
        }
        let now = Date()
        let dt = now.timeIntervalSince(lastSample.time)
        if dt > 0 && lastSample.down > 0 {
            // The sum can go down: per-interface counters are 32-bit and wrap
            // every 4 GB, and an interface can vanish (USB LAN unplugged,
            // sleep). Treat a drop as 0 for this tick.
            let downDelta = down >= lastSample.down ? down - lastSample.down : 0
            let upDelta = up >= lastSample.up ? up - lastSample.up : 0
            downloadBps = Double(downDelta) / dt
            uploadBps = Double(upDelta) / dt
            pushHistory(downloadBps, to: &downloadHistory)
            pushHistory(uploadBps, to: &uploadHistory)
            // Session totals; ignore gaps (sleep) longer than 10s.
            if dt < 10 {
                netSessionDown += downDelta
                netSessionUp += upDelta
            }
        }
        lastSample = NetworkSample(down: down, up: up, time: now)
    }
}

// MARK: - SMC sensors, power, per-core CPU

extension SystemMonitor {
    // MARK: SMC

    /// Enumerates temperature/power keys once, on a background queue.
    private func discoverSMCKeys() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let smc = SMCClient() else { return }
            let platform = CPUTemperatureSelector.currentPlatform()
            let cpu = smc.keys { CPUTemperatureSelector.isCPUTemperatureKey($0, platform: platform) }
            let cpuCore = cpu.filter { CPUTemperatureSelector.isCPUCoreKey($0.name, platform: platform) }
            let cpuCoreNames = Set(cpuCore.map(\.name))
            let sensors = SMCSensors(
                client: smc,
                cpuCoreKeys: cpuCore,
                cpuFallbackKeys: cpu.filter { !cpuCoreNames.contains($0.name) },
                gpuKeys: smc.keys { $0.hasPrefix("Tg") },
                batteryKeys: smc.keys { $0.range(of: "^TB[0-9]T$", options: .regularExpression) != nil },
                systemPowerKey: smc.key(named: "PSTR"),
                adapterPowerKey: smc.key(named: "PDTR"))
            DispatchQueue.main.async { self?.smcSensors = sensors }
        }
    }

    /// CPU, GPU and battery temperatures: dozens of SMC keys per read.
    private func refreshTemperatures() {
        guard let sensors = smcSensors else { return }
        let smc = sensors.client
        // Vorssaint: the hottest verified core sensor of this chip; the other
        // Tp/Te keys only when no core sensor answers. The max of every
        // Tp/Te/Tf key reads 10–20 °C hotter (Te06, Tp1x on M4 Pro).
        cpuTemperature =
            Self.maxChip(sensors.cpuCoreKeys.map { smc.readValue($0) })
            ?? Self.maxChip(sensors.cpuFallbackKeys.map { smc.readValue($0) })
        gpuTemperature = Self.maxChip(sensors.gpuKeys.map { smc.readValue($0) })
        batteryTemperature = Self.maxValid(sensors.batteryKeys.map { smc.readValue($0) })
    }

    /// System and adapter power: two SMC keys, sampled always so the power
    /// graph has its history when the Power tab opens.
    private func refreshSystemPower() {
        guard let sensors = smcSensors else { return }
        let smc = sensors.client
        if let key = sensors.systemPowerKey,
            let w = smc.readValue(key), (0...1000).contains(w)
        {
            systemWatts = w
            pushHistory(w, to: &systemPowerHistory)
        } else if let bw = batteryWatts, bw < 0 {
            // No PSTR sensor: fall back to battery discharge power.
            systemWatts = abs(bw)
            pushHistory(abs(bw), to: &systemPowerHistory)
        }
        if let key = sensors.adapterPowerKey,
            let w = smc.readValue(key), (0...1000).contains(w)
        {
            adapterWatts = w
        }
    }

    /// Chip sensors below 10 °C are not plausible readings.
    private static func maxChip(_ values: [Double?]) -> Double? {
        values.compactMap { $0 }.filter { $0 >= CPUTemperatureSelector.minimumChipTemperature && $0 < 125 }.max()
    }

    private static func maxValid(_ values: [Double?]) -> Double? {
        values.compactMap { $0 }.filter { (1...125).contains($0) }.max()
    }

    // MARK: Battery power (AppleSmartBattery)

    private func refreshBatteryPower() {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("AppleSmartBattery"),
                &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        func prop(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(
                service, key as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        if let connected = prop("ExternalConnected") as? Bool {
            isOnACPower = connected
        }
        if let adapter = prop("AdapterDetails") as? [String: Any],
            let watts = adapter["Watts"] as? Int
        {
            adapterMaxWatts = Double(watts)
        }
        if let voltage = prop("Voltage") as? Int {
            let amperage = (prop("Amperage") as? Int) ?? (prop("InstantAmperage") as? Int) ?? 0
            // mV * mA / 1e6 = W. Negative while discharging.
            batteryWatts = Double(voltage) * Double(amperage) / 1_000_000
        }
    }

    // MARK: Per-core CPU

    private func refreshCPUCores() {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        guard
            host_processor_info(
                hostPort, PROCESSOR_CPU_LOAD_INFO,
                &cpuCount, &cpuInfo, &cpuInfoCount) == KERN_SUCCESS,
            let info = cpuInfo
        else { return }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        let cores = (0..<Int(cpuCount)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            // integer_t slots hold unsigned tick counters.
            func ticks(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[base + Int(state)]) }
            return CPUTicks(
                user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE))
        }
        cpuCoreUsages = cores.indices.map { core in
            guard core < lastCoreTicks.count else { return 0 }
            return min(1, cores[core].busyFraction(since: lastCoreTicks[core]) ?? 0)
        }
        lastCoreTicks = cores
    }
}
