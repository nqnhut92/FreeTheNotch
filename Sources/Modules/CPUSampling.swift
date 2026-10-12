import Foundation
import IOKit

// MARK: - CPU load ticks

/// Cumulative CPU ticks as Mach reports them (`host_cpu_load_info`,
/// `PROCESSOR_CPU_LOAD_INFO`). The counters are 32-bit and wrap after a few
/// weeks of uptime, so deltas use wrapping arithmetic.
struct CPUTicks: Equatable {
    var user: UInt32 = 0
    var system: UInt32 = 0
    var idle: UInt32 = 0
    var nice: UInt32 = 0

    /// Busy share (user + system + nice) of the ticks elapsed since
    /// `previous`, 0…1; nil when no tick elapsed.
    func busyFraction(since previous: CPUTicks) -> Double? {
        let busy =
            UInt64(user &- previous.user) + UInt64(system &- previous.system) + UInt64(nice &- previous.nice)
        let total = busy + UInt64(idle &- previous.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }
}

// MARK: - CPU core topology

// Ported from Vorssaint's CPUCoreSampler.swift (CPUCoreGroup / CPUCoreTopology;
// vorssaint/vorssaint-utils, GPL-3.0-or-later). `cpuCoreUsages` is in Mach
// processor order, where Apple Silicon numbers E cores first (logical CPU 0…3
// on M4 Pro) while perflevel0 is the Performance class, so each sampler slot
// is mapped to its class via the device tree's logical-cpu-id/cluster-type.

/// A core class (sysctl perflevel name, such as "Performance") and the
/// sampler indices of its cores.
struct CPUCoreGroup: Equatable {
    let name: String
    let indices: [Int]
    /// Faster cores get wider bars.
    var weight: Double {
        switch name.lowercased() {
        case "super": return 1.5
        case "performance": return 1.25
        default: return 1
        }
    }
}

enum CPUCoreTopology {
    /// Read once. Anything that does not add up falls back to one "CPU" group
    /// rather than guessing which core belongs to which class.
    static let groups: [CPUCoreGroup] = read()

    static func groups(for count: Int) -> [CPUCoreGroup] {
        guard groups.reduce(0, { $0 + $1.indices.count }) == count else {
            return count == 0 ? [] : [CPUCoreGroup(name: "CPU", indices: Array(0..<count))]
        }
        return groups
    }

    /// `levels` come from sysctl in perflevel order, `cores` from the device
    /// tree (logical CPU ID and cluster type), and `slots` map each sampler
    /// index to its logical CPU ID.
    static func groups(
        levels: [(name: String, count: Int)],
        cores: [(id: Int, type: String)],
        slots: [Int]
    ) -> [CPUCoreGroup] {
        let fallback = slots.isEmpty ? [] : [CPUCoreGroup(name: "CPU", indices: Array(slots.indices))]
        guard Set(levels.map(\.name)).count == levels.count, Set(slots).count == slots.count,
            cores.count == slots.count, Set(cores.map(\.id)) == Set(slots)
        else { return fallback }
        // XNU orders perflevels by cluster performance, not by logical CPU ID.
        let order = ["S", "P", "E"]
        let types = Set(cores.map(\.type))
        guard types.isSubset(of: Set(order)), types.count == levels.count else { return fallback }
        let byID = Dictionary(uniqueKeysWithValues: cores.map { ($0.id, $0.type) })
        var groups: [CPUCoreGroup] = []
        for (level, type) in zip(levels, order.filter(types.contains)) {
            let indices = slots.indices.filter { byID[slots[$0]] == type }
            guard indices.count == level.count else { return fallback }
            groups.append(CPUCoreGroup(name: level.name, indices: indices))
        }
        return groups
    }

    private static func read() -> [CPUCoreGroup] {
        #if arch(arm64)
            guard let levelCount = integer("hw.nperflevels"), (1...8).contains(levelCount) else { return [] }
            guard let slots = processorSlots() else { return [] }
            var levels: [(name: String, count: Int)] = []
            for level in 0..<levelCount {
                guard let name = string("hw.perflevel\(level).name"),
                    let cpuCount = integer("hw.perflevel\(level).logicalcpu_max")
                else { return [] }
                levels.append((name, cpuCount))
            }
            let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
            guard root != 0 else { return [] }
            defer { IOObjectRelease(root) }
            var iterator: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else {
                return []
            }
            defer { IOObjectRelease(iterator) }
            var cores: [(id: Int, type: String)] = []
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                guard
                    let id = IORegistryEntryCreateCFProperty(
                        entry, "logical-cpu-id" as CFString,
                        kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber,
                    let data = IORegistryEntryCreateCFProperty(
                        entry, "cluster-type" as CFString,
                        kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                    let type = String(data: data.prefix(while: { $0 != 0 }), encoding: .utf8)
                else { continue }
                cores.append((id.intValue, type))
            }
            return groups(levels: levels, cores: cores, slots: slots)
        #else
            return []
        #endif
    }

    /// Logical CPU ID (slot_num) of each processor, in Mach processor order —
    /// the same order PROCESSOR_CPU_LOAD_INFO uses for `cpuCoreUsages`.
    private static func processorSlots() -> [Int]? {
        let stride = MemoryLayout<processor_basic_info>.stride / MemoryLayout<integer_t>.stride
        var processors: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        guard host_processor_info(host, PROCESSOR_BASIC_INFO, &processors, &info, &count) == KERN_SUCCESS,
            let info
        else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        guard processors > 0, Int(processors) <= Int(count) / stride else { return nil }
        let records = UnsafeRawPointer(info).assumingMemoryBound(to: processor_basic_info.self)
        return (0..<Int(processors)).map { Int(records[$0].slot_num) }
    }

    private static func integer(_ key: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(key, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    private static func string(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0, size < 256 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(bytes: bytes.prefix(while: { $0 != 0 }), encoding: .utf8)
    }
}

// MARK: - CPU temperature sensor selection

// Ported from Vorssaint's TemperatureSensorSelector
// (vorssaint/vorssaint-utils, GPL-3.0-or-later): per-generation core sensor
// sets for Apple M1–M5, Tf keys only on M3.
enum CPUTemperaturePlatform {
    case appleM1Family, appleM2Family, appleM3Family, appleM4Family, appleM5Family
    case unmappedAppleSilicon, generic
}

enum CPUTemperatureSelector {
    static let minimumChipTemperature = 10.0

    private static let appleM1CPUCoreKeys: Set<String> = [
        "Tp09", "Tp0T",
        "Tp01", "Tp05", "Tp0D", "Tp0H",
        "Tp0L", "Tp0P", "Tp0X", "Tp0b",
    ]

    private static let appleM2CPUCoreKeys: Set<String> = [
        "Tp1h", "Tp1t", "Tp1p", "Tp1l",
        "Tp01", "Tp05", "Tp09", "Tp0D",
        "Tp0X", "Tp0b", "Tp0f", "Tp0j",
    ]

    private static let appleM3CPUCoreKeys: Set<String> = [
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B",
        "Tf0D", "Tf0E", "Tf44", "Tf49",
        "Tf4A", "Tf4B", "Tf4D", "Tf4E",
    ]

    private static let appleM4CPUCoreKeys: Set<String> = [
        "Te05", "Te0S", "Te09", "Te0H",
        "Tp01", "Tp05", "Tp09", "Tp0D",
        "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
    ]

    private static let appleM5CPUCoreKeys: Set<String> = [
        "Tp00", "Tp04", "Tp08", "Tp0C",
        "Tp0G", "Tp0K",
        "Tp0O", "Tp0R", "Tp0U", "Tp0X",
        "Tp0a", "Tp0d", "Tp0g", "Tp0j",
        "Tp0m", "Tp0p", "Tp0u", "Tp0y",
    ]

    static func currentPlatform() -> CPUTemperaturePlatform {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return .unmappedAppleSilicon
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return .unmappedAppleSilicon
        }
        return platform(brandString: String(cString: buffer))
    }

    static func platform(brandString: String) -> CPUTemperaturePlatform {
        let brand = brandString.trimmingCharacters(in: .whitespacesAndNewlines)
        if brand == "Apple A18 Pro" { return .generic }
        switch appleSiliconGeneration(in: brand) {
        case 1: return .appleM1Family
        case 2: return .appleM2Family
        case 3: return .appleM3Family
        case 4: return .appleM4Family
        case 5: return .appleM5Family
        default: return brand.hasPrefix("Apple ") ? .unmappedAppleSilicon : .generic
        }
    }

    static func isCPUCoreKey(_ key: String, platform: CPUTemperaturePlatform) -> Bool {
        switch platform {
        case .appleM1Family: return appleM1CPUCoreKeys.contains(key)
        case .appleM2Family: return appleM2CPUCoreKeys.contains(key)
        case .appleM3Family: return appleM3CPUCoreKeys.contains(key)
        case .appleM4Family: return appleM4CPUCoreKeys.contains(key)
        case .appleM5Family: return appleM5CPUCoreKeys.contains(key)
        case .unmappedAppleSilicon, .generic: return false
        }
    }

    static func isCPUTemperatureKey(_ key: String, platform: CPUTemperaturePlatform) -> Bool {
        if key.hasPrefix("Tp") || key.hasPrefix("Te") { return true }
        return platform == .appleM3Family && key.hasPrefix("Tf")
    }

    private static func appleSiliconGeneration(in brand: String) -> Int? {
        guard brand.hasPrefix("Apple M") else { return nil }
        let remainder = brand.dropFirst("Apple M".count)
        guard let first = remainder.first, let generation = Int(String(first)) else { return nil }
        guard generation >= 1, generation <= 5 else { return nil }
        let afterGeneration = remainder.dropFirst()
        guard afterGeneration.isEmpty || afterGeneration.first == " " else { return nil }
        return generation
    }
}
