import AppKit
import Foundation
import IOKit

// Disk volumes with SMART health, live read/write speeds and eject support.
// SMART fields follow Vorssaint's approach (vorssaint/vorssaint-utils,
// GPL-3.0-or-later): `diskutil info -plist` -> SMARTDeviceSpecificKeysMayVaryNotGuaranteed.
struct DiskSMART: Equatable {
    var status: String?
    var totalWrittenBytes: UInt64?
    var totalReadBytes: UInt64?
    var temperatureC: Double?
    var healthPercent: Int?
    var powerCycles: Int?
    var powerOnHours: Int?
}

enum DiskEjectState: Equatable {
    case idle, ejecting, ready, failed
}

struct DiskVolume: Identifiable {
    let id: String  // mount path
    var name: String
    var bsdName: String
    var wholeDiskBSD: String
    /// Whole disk carrying the IOBlockStorageDriver counters. For APFS that is
    /// the physical store (disk0), not the synthesized container (disk3).
    var ioDiskBSD: String
    var mountPath: String
    var totalBytes: UInt64
    var freeBytes: UInt64
    var purgeableBytes: UInt64
    /// Vorssaint: physically used = total - raw free. Purgeable space still
    /// counts as used (shown separately), so "used" + "available" can exceed
    /// the total, exactly as in Vorssaint.
    var usedBytes: UInt64
    var fileSystem: String
    var isInternal: Bool
    var isEjectable: Bool
    var smart: DiskSMART?
    var readBps: Double = 0
    var writeBps: Double = 0
    var sessionReadBytes: UInt64 = 0
    var sessionWriteBytes: UInt64 = 0

    var usedFraction: Double {
        totalBytes > 0 ? min(1, Double(usedBytes) / Double(totalBytes)) : 0
    }
}

final class DiskMonitor: ObservableObject {
    @Published private(set) var volumes: [DiskVolume] = []
    @Published var selectedID: String?
    @Published private(set) var readHistory: [Double] = []
    @Published private(set) var writeHistory: [Double] = []
    @Published private(set) var ejectStates: [String: DiskEjectState] = [:]

    static let historyLength = 60

    private var speedTimer: Timer?
    private var smartTimer: Timer?
    private var lastStats: [String: (read: UInt64, written: UInt64, time: Date)] = [:]

    var selected: DiskVolume? {
        volumes.first { $0.id == selectedID } ?? volumes.first
    }

    init() {
        refreshVolumes()
        speedTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshSpeeds()
        }
        smartTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshVolumes()
        }
    }

    // MARK: - Volumes & SMART

    func refreshVolumes() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let urls =
                FileManager.default.mountedVolumeURLs(
                    includingResourceValuesForKeys: [
                        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                        .volumeIsReadOnlyKey,
                    ],
                    options: [.skipHiddenVolumes]) ?? []
            var fresh: [DiskVolume] = []
            for url in urls {
                let path = url.path
                guard let info = Self.diskutilInfo(for: path) else { continue }
                let values = try? url.resourceValues(forKeys: [
                    .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                    .volumeIsReadOnlyKey,
                ])
                let name =
                    (values?.volumeName as? String)
                    ?? (info["VolumeName"] as? String) ?? path
                let bsd = (info["DeviceIdentifier"] as? String) ?? ""
                let whole = (info["ParentWholeDisk"] as? String) ?? bsd
                let physicalStore =
                    (info["APFSPhysicalStores"] as? [[String: Any]])?
                    .first?["APFSPhysicalStore"] as? String
                let isInternal = (info["Internal"] as? Bool) ?? true
                let ioDisk = Self.ioCounterDisk(
                    bsd: bsd, parentWhole: whole,
                    physicalStore: physicalStore, isInternal: isInternal)
                // Vorssaint's DiskSampler: the volume's own capacity values
                // (what Finder shows) win. The sealed system snapshot reports
                // diskutil FreeSpace = 0.
                let diskutilTotal = Self.uint(info["APFSContainerSize"]) ?? Self.uint(info["TotalSize"]) ?? 0
                let diskutilFree = Self.uint(info["APFSContainerFree"]) ?? Self.uint(info["FreeSpace"]) ?? 0
                let total = Self.positive(values?.volumeTotalCapacity) ?? diskutilTotal
                let rawFree = Self.positive(values?.volumeAvailableCapacity)
                let importantFree = values?.volumeIsReadOnly == true ? nil : Self.importantFree(url)
                let free = min(importantFree ?? rawFree ?? diskutilFree, total)
                let purgeable = rawFree.map { free > $0 ? free - $0 : 0 } ?? 0
                let used = min(
                    total,
                    rawFree.map { total >= $0 ? total - $0 : 0 }
                        ?? (total >= free ? total - free : 0))
                let volume = DiskVolume(
                    id: path,
                    name: name,
                    bsdName: bsd,
                    wholeDiskBSD: whole,
                    ioDiskBSD: ioDisk,
                    mountPath: path,
                    totalBytes: total,
                    freeBytes: free,
                    purgeableBytes: purgeable,
                    usedBytes: used,
                    fileSystem: Self.fileSystemLabel(
                        type: info["FilesystemType"] as? String,
                        name: info["FilesystemName"] as? String),
                    isInternal: isInternal,
                    isEjectable: (info["Ejectable"] as? Bool) ?? false,
                    smart: Self.parseSMART(info))
                fresh.append(volume)
            }
            // Boot volume first, then the rest by name.
            fresh.sort {
                if $0.mountPath == "/" { return true }
                if $1.mountPath == "/" { return false }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            let scanned = fresh
            DispatchQueue.main.async {
                // Live counters carry over; `volumes` is only touched on main.
                var merged = scanned
                for index in merged.indices {
                    guard let old = self.volumes.first(where: { $0.id == merged[index].id }) else { continue }
                    merged[index].readBps = old.readBps
                    merged[index].writeBps = old.writeBps
                    merged[index].sessionReadBytes = old.sessionReadBytes
                    merged[index].sessionWriteBytes = old.sessionWriteBytes
                }
                self.volumes = merged
                if self.selectedID == nil || !merged.contains(where: { $0.id == self.selectedID }) {
                    self.selectedID = merged.first?.id
                }
            }
        }
    }

    /// Free space counting what macOS would purge to make room. Only a
    /// writable volume can answer it.
    private static func importantFree(_ url: URL) -> UInt64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let v = values.volumeAvailableCapacityForImportantUsage, v > 0
        else { return nil }
        return UInt64(v)
    }

    /// Vorssaint's DiskSupport.fileSystemLabel: "apfs" -> "APFS".
    private static func fileSystemLabel(type: String?, name: String?) -> String {
        guard let type = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            !type.isEmpty
        else { return "" }
        switch type {
        case "apfs": return "APFS"
        case "hfs": return "HFS+"
        case "exfat": return "exFAT"
        case "ntfs": return "NTFS"
        case "msdos":
            if let name {
                if name.contains("32") { return "FAT32" }
                if name.contains("16") { return "FAT16" }
                if name.contains("12") { return "FAT12" }
            }
            return "FAT"
        case "cd9660": return "ISO 9660"
        default: return name ?? type.uppercased()
        }
    }

    private static func positive(_ value: Int?) -> UInt64? {
        guard let value, value > 0 else { return nil }
        return UInt64(value)
    }

    private static func uint(_ value: Any?) -> UInt64? {
        if let v = value as? UInt64 { return v }
        if let v = value as? Int, v >= 0 { return UInt64(v) }
        if let v = value as? NSNumber { return v.uint64Value }
        return nil
    }

    /// Vorssaint's ioCounterIDs: an internal APFS volume's counters live on
    /// its physical store's whole disk; an external one's on its own disk.
    private static func ioCounterDisk(
        bsd: String, parentWhole: String,
        physicalStore: String?, isInternal: Bool
    ) -> String {
        let candidates =
            isInternal
            ? [physicalWholeDisk(physicalStore), physicalWholeDisk(parentWhole), physicalWholeDisk(bsd)]
            : [physicalWholeDisk(bsd), physicalWholeDisk(parentWhole), physicalWholeDisk(physicalStore)]
        return candidates.compactMap { $0 }.first ?? parentWhole
    }

    /// "disk0s2" -> "disk0".
    static func physicalWholeDisk(_ identifier: String?) -> String? {
        guard let identifier, identifier.hasPrefix("disk") else { return nil }
        let digits = identifier.dropFirst(4).prefix { $0.isNumber }
        return digits.isEmpty ? nil : "disk" + digits
    }

    private static func diskutilInfo(for mountPath: String) -> [String: Any]? {
        guard let output = Subprocess.run("/usr/sbin/diskutil", arguments: ["info", "-plist", mountPath], timeout: 15),
            output.succeeded
        else { return nil }
        return (try? PropertyListSerialization.propertyList(from: output.data, format: nil)) as? [String: Any]
    }

    private static func parseSMART(_ info: [String: Any]) -> DiskSMART? {
        guard let dict = info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any] else {
            // Still surface the verified/not-verified status when present.
            if let status = info["SMARTStatus"] as? String {
                return DiskSMART(status: status)
            }
            return nil
        }
        func u64(_ key: String) -> UInt64? {
            if let v = dict[key] as? UInt64 { return v }
            if let v = dict[key] as? Int { return UInt64(max(0, v)) }
            if let v = dict[key] as? Double { return UInt64(max(0, v)) }
            return nil
        }
        func nvmeBytes(low: String, high: String) -> UInt64? {
            guard let lo = u64(low), let hi = u64(high) else { return nil }
            // NVMe data unit = 512,000 bytes.
            return (lo + (hi << 32)) * 512_000
        }
        var smart = DiskSMART()
        smart.status = info["SMARTStatus"] as? String
        smart.totalWrittenBytes = nvmeBytes(low: "DATA_UNITS_WRITTEN_0", high: "DATA_UNITS_WRITTEN_1")
        smart.totalReadBytes = nvmeBytes(low: "DATA_UNITS_READ_0", high: "DATA_UNITS_READ_1")
        if let rawTemp = (dict["TEMPERATURE"] as? Double) ?? (dict["TEMPERATURE"] as? Int).map(Double.init) {
            // Values above 150 are Kelvin.
            let celsius = rawTemp > 150 ? rawTemp - 273.15 : rawTemp
            if (1...125).contains(celsius) { smart.temperatureC = celsius }
        }
        if let used = (dict["PERCENTAGE_USED"] as? Int) ?? (dict["PERCENTAGE_USED"] as? Double).map(Int.init) {
            smart.healthPercent = max(0, 100 - used)
        }
        smart.powerCycles = (dict["POWER_CYCLES_0"] as? Int) ?? (dict["POWER_CYCLES_0"] as? Double).map(Int.init)
        smart.powerOnHours = (dict["POWER_ON_HOURS_0"] as? Int) ?? (dict["POWER_ON_HOURS_0"] as? Double).map(Int.init)
        return smart
    }

    // MARK: - Live speeds

    private func refreshSpeeds() {
        let stats = Self.blockStatistics()
        let now = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for i in self.volumes.indices {
                let whole = self.volumes[i].ioDiskBSD
                guard let current = stats[whole] else { continue }
                if let last = self.lastStats[whole] {
                    let dt = now.timeIntervalSince(last.time)
                    if dt > 0, dt < 15 {
                        let read = current.read >= last.read ? Double(current.read - last.read) / dt : 0
                        let written = current.written >= last.written ? Double(current.written - last.written) / dt : 0
                        self.volumes[i].readBps = read
                        self.volumes[i].writeBps = written
                        self.volumes[i].sessionReadBytes += current.read >= last.read ? current.read - last.read : 0
                        self.volumes[i].sessionWriteBytes +=
                            current.written >= last.written ? current.written - last.written : 0
                        if self.volumes[i].id == self.selectedID {
                            self.pushHistory(read, to: &self.readHistory)
                            self.pushHistory(written, to: &self.writeHistory)
                        }
                    }
                }
                self.lastStats[whole] = (current.read, current.written, now)
            }
        }
    }

    private func pushHistory(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
    }

    /// Whole-disk BSD name -> cumulative (read, written) bytes, from
    /// IOBlockStorageDriver "Statistics".
    private static func blockStatistics() -> [String: (read: UInt64, written: UInt64)] {
        var result: [String: (UInt64, UInt64)] = [:]
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("IOBlockStorageDriver"),
                &iterator) == KERN_SUCCESS
        else { return result }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard
                let stats = IORegistryEntryCreateCFProperty(
                    service, "Statistics" as CFString,
                    kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                let read = stats["Bytes (Read)"] as? UInt64,
                let written = stats["Bytes (Write)"] as? UInt64,
                let whole = wholeDiskBSDName(for: service)
            else { continue }
            result[whole] = (read, written)
        }
        return result
    }

    /// Vorssaint's wholeDiskBSDName(descendingFrom:): the whole-disk IOMedia
    /// ("disk0") is a child of the IOBlockStorageDriver, not a parent.
    private static func wholeDiskBSDName(for entry: io_registry_entry_t) -> String? {
        if (IORegistryEntryCreateCFProperty(
            entry, "Whole" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool) == true,
            let name = IORegistryEntryCreateCFProperty(
                entry, "BSD Name" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        {
            return name
        }
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(children) }
        var child = IOIteratorNext(children)
        while child != 0 {
            defer {
                IOObjectRelease(child)
                child = IOIteratorNext(children)
            }
            if let name = wholeDiskBSDName(for: child) { return name }
        }
        return nil
    }

    // MARK: - Eject

    func eject(_ volume: DiskVolume) {
        guard volume.isEjectable else { return }
        ejectStates[volume.id] = .ejecting
        let url = URL(fileURLWithPath: volume.mountPath)
        let id = volume.id
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                DispatchQueue.main.async {
                    self?.ejectStates[id] = .ready
                    self?.refreshVolumes()
                }
            } catch {
                self?.ejectViaDiskutil(volume)
            }
        }
    }

    private func ejectViaDiskutil(_ volume: DiskVolume) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // A busy disk can take a while to flush before it lets go.
            let ok =
                Subprocess.run("/usr/sbin/diskutil", arguments: ["eject", volume.wholeDiskBSD], timeout: 60)?
                .succeeded ?? false
            DispatchQueue.main.async {
                self?.ejectStates[volume.id] = ok ? .ready : .failed
                if ok { self?.refreshVolumes() }
            }
        }
    }

    func ejectAll() {
        for volume in volumes where volume.isEjectable {
            if ejectStates[volume.id] != .ejecting { eject(volume) }
        }
    }

    var canEjectAny: Bool {
        volumes.contains { $0.isEjectable && ejectStates[$0.id] != .ejecting }
    }

    func openInFinder(_ volume: DiskVolume) {
        NSWorkspace.shared.open(URL(fileURLWithPath: volume.mountPath))
    }
}
