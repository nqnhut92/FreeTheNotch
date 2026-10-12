import AppKit
import Foundation
import IOBluetooth
import IOKit
import os

// MARK: - Monitor

/// Bluetooth connection state via the public IOBluetooth framework.
/// Emits short transient events ("AirPods Pro connected") for the
/// collapsed notch live activity.
final class BluetoothMonitor: ObservableObject {
    @Published private(set) var devices: [BTDevice] = []
    /// Device that just connected. Drives the collapsed-notch ears (icon
    /// left, battery ring right) for a few seconds like an iPhone live
    /// activity — it clears on a timer, not on disconnect, so the ears
    /// don't linger for the whole session.
    @Published private(set) var liveDevice: BTDevice?
    /// Devices system_profiler reports with battery that IOBluetooth does not
    /// call connected, e.g. AirPods resting in their case near the Mac (the
    /// macOS Batteries widget shows those too). Batteries page only.
    @Published private(set) var nearbyDevices: [BTDevice] = []
    /// Controller power (Atoll's `IOBluetoothHostController.default()?.powerState`
    /// check). Drives the side notch's Bluetooth logo and its menu switch.
    @Published private(set) var isPoweredOn = false
    /// Device type macOS stored at pairing (system_profiler's
    /// `device_minorType`: Keyboard, Mouse, Headphones…), by lowercased name.
    /// IOBluetooth's class of device is often empty (BLE devices, devices not
    /// seen for a while), so this fills in `kind`. iPhone, iPad, Watch,
    /// HomePod and Apple TV, paired through iCloud, have no type, and the
    /// macOS Bluetooth menu hides them; so does the side notch's. Nil until
    /// the first system_profiler run.
    @Published private(set) var accessoryTypes: [String: String]?
    var accessoryNames: Set<String>? { accessoryTypes.map { Set($0.keys) } }

    private var connectNote: IOBluetoothUserNotification?
    private var pollTimer: Timer?
    private var liveTimer: Timer?
    private var lastConnectedIDs: Set<String> = []

    /// How long the Bluetooth ears stay visible after a connection.
    private static let liveDuration: TimeInterval = 2

    func startMonitoring() {
        refresh()
        lastConnectedIDs = Set(devices.filter(\.isConnected).map(\.id))
        connectNote = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:)))
        // IOBluetooth offers no class-level disconnect registration,
        // so disconnects are detected by polling connection state.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollConnectionStates()
        }
    }

    func refresh() {
        let powered = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
        if isPoweredOn != powered { isPoweredOn = powered }
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        var registryMisses: Set<String> = []
        devices = paired.map { device in
            let name = device.name ?? "Unknown device"
            // A stable key for the rare device without an address, so its
            // row keeps its identity across refreshes.
            let address = device.addressString ?? "name." + name.lowercased()
            let connected = device.isConnected()
            let registry = connected ? Self.batteryPercentFromIORegistry(address: address, name: name) : nil
            if connected && registry == nil { registryMisses.insert(name) }
            var kind = Self.kind(of: device)
            if kind == .generic, let type = accessoryTypes?[name.lowercased()] {
                kind = BTKind(name: name, minorType: type)
            }
            return BTDevice(
                id: address,
                name: name,
                kind: kind,
                isConnected: connected,
                batteryPercent: connected
                    ? (registry ?? subprocessPercentages[name.lowercased()])
                    : nil,
                parts: connected ? subprocessParts[name.lowercased()] : nil)
        }
        .sorted { $0.isConnected && !$1.isConnected }
        subprocessNames = registryMisses
        if let live = liveDevice {
            liveDevice = devices.first { $0.id == live.id && $0.isConnected }
        }
        refreshSubprocessBatteries()
    }

    /// Bluetooth class-of-device first, then the name. AirPods advertise as
    /// generic headphones, so the name has to win for those.
    private static func kind(of device: IOBluetoothDevice) -> BTKind {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpod") || name.contains("beats") { return .airpods }
        if name.contains("trackpad") { return .trackpad }
        if name.contains("pencil") { return .pencil }
        if name.contains("watch") { return .watch }
        if name.contains("mouse") || name.contains("master") || name.contains("mx ") { return .mouse }
        if name.contains("keyboard") { return .keyboard }
        if name.contains("speaker") || name.contains("homepod") { return .speaker }

        let major = device.deviceClassMajor
        let minor = device.deviceClassMinor
        if major == UInt32(kBluetoothDeviceClassMajorAudio) {
            if minor == UInt32(kBluetoothDeviceClassMinorAudioLoudspeaker)
                || minor == UInt32(kBluetoothDeviceClassMinorAudioHiFi)
                || minor == UInt32(kBluetoothDeviceClassMinorAudioCar)
            {
                return .speaker
            }
            return .headphones
        }
        if major == UInt32(kBluetoothDeviceClassMajorPeripheral) {
            let keyboard = UInt32(kBluetoothDeviceClassMinorPeripheral1Keyboard)
            let pointing = UInt32(kBluetoothDeviceClassMinorPeripheral1Pointing)
            if minor & keyboard != 0 { return .keyboard }
            if minor & pointing != 0 { return .mouse }
            let sub = minor & 0x0F
            if sub == UInt32(kBluetoothDeviceClassMinorPeripheral2Gamepad) { return .gamepad }
            if sub == UInt32(kBluetoothDeviceClassMinorPeripheral2DigitalPen) { return .pencil }
            return .generic
        }
        if major == UInt32(kBluetoothDeviceClassMajorPhone) { return .phone }
        if major == UInt32(kBluetoothDeviceClassMajorWearable) { return .watch }
        return .generic
    }

    /// Best-effort Bluetooth battery level via IORegistry. Returns nil when
    /// the device doesn't expose it (common for classic Bluetooth).
    /// Atoll-style: checks AppleDeviceManagementHIDEventService (where AirPods
    /// expose battery) in addition to IOBluetoothDevice, matches by address
    /// or device name.
    private static func batteryPercentFromIORegistry(address: String?, name: String?) -> Int? {
        let targetAddr = address?.lowercased()
        let targetName = name?.lowercased()
        for serviceName in ["AppleDeviceManagementHIDEventService", "IOBluetoothDevice"] {
            if let pct = batteryFromService(serviceName, targetAddr: targetAddr, targetName: targetName, precise: true)
            {
                return pct
            }
        }
        // For keyboards: try HID service without name matching (Keychron may
        // have different HID name than Bluetooth name).
        if let targetName, targetName.lowercased().contains("keychron") {
            if let pct = batteryFromHIDServiceAny() {
                return pct
            }
        }
        // Atoll-style fallback: Bluetooth preferences DeviceCache.
        if let pct = batteryFromBluetoothPrefs(address: address, name: name) {
            return pct
        }
        // system_profiler / pmset run off the main thread instead
        // (refreshSubprocessBatteries), like Atoll's batteryFetchQueue.
        return nil
    }

    // MARK: Subprocess battery fallback (Atoll's batteryFetchQueue pattern)

    /// Where the subprocess half of a battery refresh runs. Never the main
    /// thread: Keychron never reports battery, so every poll falls through to
    /// the tools, and right after wake, while Bluetooth restarts, they can
    /// take seconds.
    private let batteryFetchQueue = DispatchQueue(label: "FreeTheNotch.bluetooth.battery", qos: .utility)
    private var isSubprocessRefreshInFlight = false
    private var lastSubprocessRefresh: Date?
    private static let subprocessRefreshInterval: TimeInterval = 20
    /// Last levels the subprocesses reported, by lowercased device name, so the
    /// cheap in-process pass keeps publishing them.
    private var subprocessPercentages: [String: Int] = [:]
    /// Per-part AirPods levels from system_profiler, by lowercased name.
    private var subprocessParts: [String: BTBatteryParts] = [:]
    /// Connected devices the in-process lookup could not read. They are
    /// re-read by the subprocesses on every pass, even once a cached value
    /// fills `batteryPercent`, so the level never freezes.
    private var subprocessNames: Set<String> = []

    private func refreshSubprocessBatteries(force: Bool = false) {
        // refresh() also runs from IOBluetooth callbacks; keep this state on main.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refreshSubprocessBatteries(force: force) }
            return
        }
        // AirPods always go through system_profiler: it is the only source
        // of separate left / right / case levels.
        let names = devices.filter { $0.isConnected && (subprocessNames.contains($0.name) || $0.kind == .airpods) }
            .map(\.name)
        // Runs even with no names: system_profiler also finds nearby devices.
        guard !isSubprocessRefreshInFlight else { return }
        if !force, let last = lastSubprocessRefresh,
            Date().timeIntervalSince(last) < Self.subprocessRefreshInterval
        {
            return
        }
        isSubprocessRefreshInFlight = true
        lastSubprocessRefresh = Date()
        batteryFetchQueue.async { [weak self] in
            let profiler = Self.runTool("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])
            let pmset = names.isEmpty ? nil : Self.runTool("/usr/bin/pmset", ["-g", "accps"])
            let nearby = profiler.map { BluetoothToolParser.nearbyDevices(systemProfiler: $0) } ?? []
            let accessories = profiler.map { BluetoothToolParser.accessoryTypes(systemProfiler: $0) }
            var found: [String: Int] = [:]
            var foundParts: [String: BTBatteryParts] = [:]
            for name in names {
                if let pct = profiler.flatMap({ BluetoothToolParser.batteryPercent(name: name, systemProfiler: $0) })
                    ?? pmset.flatMap({ BluetoothToolParser.batteryPercent(name: name, pmset: $0) })
                {
                    found[name.lowercased()] = pct
                }
                if let parts = profiler.flatMap({ BluetoothToolParser.batteryParts(name: name, systemProfiler: $0) }) {
                    foundParts[name.lowercased()] = parts
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubprocessRefreshInFlight = false
                if let accessories, !accessories.isEmpty, accessories != self.accessoryTypes {
                    self.accessoryTypes = accessories
                    self.devices = self.devices.map { device in
                        guard device.kind == .generic,
                            let type = accessories[device.name.lowercased()]
                        else { return device }
                        var d = device
                        d.kind = BTKind(name: d.name, minorType: type)
                        return d
                    }
                }
                // Loose match: IOBluetooth and system_profiler can spell the
                // same AirPods differently.
                let connectedNames = self.devices.filter(\.isConnected).map(\.name)
                let nearbyNow = nearby.filter { entry in
                    !connectedNames.contains { BluetoothToolParser.namesMatch($0, entry.name) }
                }
                if nearbyNow.map(\.id) != self.nearbyDevices.map(\.id)
                    || nearbyNow.map(\.batteryPercent) != self.nearbyDevices.map(\.batteryPercent)
                    || nearbyNow.map(\.parts) != self.nearbyDevices.map(\.parts)
                {
                    self.nearbyDevices = nearbyNow
                }
                guard !found.isEmpty || !foundParts.isEmpty else { return }
                self.subprocessPercentages.merge(found) { _, new in new }
                self.subprocessParts.merge(foundParts) { _, new in new }
                self.devices = self.devices.map { device in
                    var d = device
                    if d.isConnected, self.subprocessNames.contains(d.name),
                        let pct = self.subprocessPercentages[d.name.lowercased()]
                    {
                        d.batteryPercent = pct
                    }
                    if d.isConnected, let parts = self.subprocessParts[d.name.lowercased()] {
                        d.parts = parts
                    }
                    return d
                }
            }
        }
    }

    /// A tool's stdout, or nil when it fails or prints nothing. Killed after
    /// 5 s so a wedged tool cannot pile up.
    private static func runTool(_ path: String, _ args: [String]) -> Data? {
        guard let output = Subprocess.run(path, arguments: args, timeout: 5), output.succeeded,
            !output.data.isEmpty
        else { return nil }
        return output.data
    }

    /// Finds any HID device with battery (for Keychron which may have
    /// different HID vs Bluetooth names).
    private static func batteryFromHIDServiceAny() -> Int? {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("AppleDeviceManagementHIDEventService"),
                &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        let batteryKeys = ["BatteryPercent", "Battery Level", "AppleBatteryPercent", "kHIDBatteryLevel"] as [CFString]
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            for key in batteryKeys {
                if let value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
                {
                    if let n = value as? Int, (0...100).contains(n) {
                        return n
                    }
                }
            }
        }
        return nil
    }

    /// Atoll-style: reads battery from /Library/Preferences/com.apple.Bluetooth DeviceCache.
    private static func batteryFromBluetoothPrefs(address: String?, name: String?) -> Int? {
        guard let prefs = UserDefaults(suiteName: "/Library/Preferences/com.apple.Bluetooth"),
            let deviceCache = prefs.object(forKey: "DeviceCache") as? [String: Any]
        else { return nil }
        let targetAddr = address?.lowercased().replacingOccurrences(of: "-", with: "")
        let targetName = name?.lowercased()
        for (key, value) in deviceCache {
            guard let payload = value as? [String: Any] else { continue }
            var matched = false
            // Match by address (key is often the address).
            if let targetAddr {
                let normKey = key.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(
                    of: ":", with: "")
                if normKey.contains(targetAddr) || targetAddr.contains(normKey) { matched = true }
            }
            // Match by name in payload.
            if !matched, let targetName {
                for nameKey in ["Name", "DeviceName", "ProductName"] {
                    if let devName = payload[nameKey] as? String {
                        let ld = devName.lowercased()
                        if ld.contains(targetName) || targetName.contains(ld) {
                            matched = true
                            break
                        }
                    }
                }
            }
            guard matched else { continue }
            for batKey in ["BatteryPercent", "BatteryLevel", "batteryLevel", "Battery"] {
                if let n = payload[batKey] as? Int, (0...100).contains(n) {
                    return n
                }
                if let n = payload[batKey] as? Double, (0...100).contains(Int(n)) {
                    return Int(n)
                }
            }
        }
        return nil
    }

    private static func batteryFromService(
        _ serviceName: String, targetAddr: String?, targetName: String?, precise: Bool = true
    ) -> Int? {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching(serviceName),
                &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        let nameKeys = ["Product", "ProductName", "DeviceName", "Name", "Bluetooth Product Name"] as [CFString]
        let batteryKeys = ["BatteryPercent", "Battery Level", "AppleBatteryPercent", "kHIDBatteryLevel"] as [CFString]
        var result: Int?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var matched = false
            var foundAddr: String?
            var foundName: String?
            // DeviceAddress can be Data or String.
            if let addrData = IORegistryEntryCreateCFProperty(
                service, "DeviceAddress" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                addrData.count >= 6
            {
                foundAddr = addrData.prefix(6).reversed().map { String(format: "%02x", $0) }.joined(separator: "-")
            } else if let addrStr = IORegistryEntryCreateCFProperty(
                service, "DeviceAddress" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            {
                foundAddr = addrStr.lowercased()
            }
            if let targetAddr, let foundAddr, foundAddr == targetAddr.lowercased() { matched = true }
            for nameKey in nameKeys {
                if let devName = IORegistryEntryCreateCFProperty(
                    service, nameKey,
                    kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                {
                    if foundName == nil { foundName = devName }
                    if let targetName, !targetName.isEmpty {
                        let ld = devName.lowercased()
                        let lt = targetName.lowercased()
                        if ld.contains(lt) || lt.contains(ld) {
                            matched = true
                            break
                        }
                    }
                }
            }
            // Also try the IORegistry entry name itself.
            if !matched, let targetName {
                var entryName = [CChar](repeating: 0, count: 128)
                if IORegistryEntryGetName(service, &entryName) == KERN_SUCCESS {
                    let nameStr = String(cString: entryName)
                    if foundName == nil { foundName = nameStr }
                    let ld = nameStr.lowercased()
                    let lt = targetName.lowercased()
                    if ld.contains(lt) || lt.contains(ld) { matched = true }
                }
            }
            if targetAddr == nil && targetName == nil { matched = true }
            guard matched else { continue }
            for key in batteryKeys {
                if let value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
                {
                    if let n = value as? Int, (0...100).contains(n) {
                        result = n
                        break
                    }
                    if let n = value as? Double, (0...100).contains(Int(n)) {
                        result = Int(n)
                        break
                    }
                }
            }
            if result != nil { break }
        }
        return result
    }

    func toggle(_ device: BTDevice) {
        guard
            let target = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?
                .first(where: { ($0.addressString ?? "") == device.id })
        else { return }
        if target.isConnected() {
            target.closeConnection()
        } else {
            target.openConnection()
        }
        // Refresh shortly after; connection is async.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: Power

    /// `IOBluetoothPreferenceSetControllerPowerState(Int32)`: private
    /// IOBluetooth function, the one `blueutil` calls. macOS has no public
    /// API to switch Bluetooth on or off. Looked up by this one name only;
    /// nil when a future macOS drops it.
    private typealias SetPowerFunction = @convention(c) (Int32) -> Void
    private static let setPowerFunction: SetPowerFunction? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW),
            let symbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState")
        else { return nil }
        return unsafeBitCast(symbol, to: SetPowerFunction.self)
    }()
    private let powerQueue = DispatchQueue(label: "FreeTheNotch.bluetooth.power", qos: .userInitiated)

    /// Switches Bluetooth on or off. Falls back to Bluetooth settings when
    /// the private call is missing or does not take effect.
    func setPower(_ on: Bool) {
        guard let setPower = Self.setPowerFunction else {
            Logger.bluetooth.notice("[FreeTheNotch] Bluetooth power: private setter missing, opening Settings")
            SystemSettings.open(.bluetooth)
            return
        }
        isPoweredOn = on  // the switch follows the click; re-read below
        powerQueue.async { [weak self] in
            setPower(on ? 1 : 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                self.refresh()
                if self.isPoweredOn != on {
                    Logger.bluetooth.notice(
                        "[FreeTheNotch] Bluetooth power: set \(on ? 1 : 0, privacy: .public) had no effect, opening Settings"
                    )
                    SystemSettings.open(.bluetooth)
                }
            }
        }
    }

    // MARK: Notifications

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        // `devices` and the other published state belong to the main thread.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.deviceConnected(notification, device: device) }
            return
        }
        refresh()
        let id = device.addressString ?? ""
        if let connected = devices.first(where: { $0.id == id && $0.isConnected }) {
            showLiveDevice(connected)
        }
        lastConnectedIDs = Set(devices.filter(\.isConnected).map(\.id))
    }

    private func pollConnectionStates() {
        let before = lastConnectedIDs
        refresh()
        let now = Set(devices.filter(\.isConnected).map(\.id))
        if let id = now.subtracting(before).first,
            let connected = devices.first(where: { $0.id == id })
        {
            showLiveDevice(connected)
        }
        lastConnectedIDs = now
    }

    /// Shows the device popup, then clears it after `liveDuration` even if
    /// it is still connected. A fresh connection restarts the timer.
    private func showLiveDevice(_ device: BTDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.liveDevice = device
            self.liveTimer?.invalidate()
            let id = device.id
            // Timer must be scheduled on the main runloop; IOBluetooth
            // callbacks arrive on a background thread where it never fires.
            self.liveTimer = Timer.scheduledTimer(withTimeInterval: Self.liveDuration, repeats: false) {
                [weak self] _ in
                guard let self, self.liveDevice?.id == id else { return }
                self.liveDevice = nil
            }
        }
    }

}
