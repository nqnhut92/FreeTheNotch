// Patterns from DuoBar (github.com/Mikeli7666/DuoBar), MIT:
// Services/NetworkService.swift (NWPathMonitor + low-frequency CoreWLAN
// refresh, SSID gated by Location), Services/WiFiPowerController.swift
// (power toggle) and Models/SystemStatus.swift (RSSI → signal bars).

import AppKit
import CoreLocation
import CoreWLAN
import Network
import SystemConfiguration
import os

/// One row in the Duo popover's network list.
struct WiFiNetworkItem: Identifiable, Equatable {
    let ssid: String
    let rssi: Int
    let isSecure: Bool

    var id: String { ssid }
    var bars: Int { WiFiMonitor.bars(forRSSI: rssi) }
}

/// Wi-Fi state for DuoGlyph: power, SSID, signal bars and a
/// cached scan for the popover. CoreWLAN withholds SSIDs without Location
/// authorization; then only power and bars are known and there is no list.
final class WiFiMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var hasInterface = false
    @Published private(set) var isPoweredOn = false
    @Published private(set) var isConnected = false
    @Published private(set) var ssid: String?
    /// 0–3; 0 when off or not associated.
    @Published private(set) var bars = 0
    /// SSIDs saved in macOS (`CWConfiguration.networkProfiles`), for the
    /// popover's "Known Networks" section. Empty without Location.
    @Published private(set) var knownSSIDs: Set<String> = []
    /// "Ethernet: USB 10/100/1G/2.5G LAN (en16)" while a wired link is up,
    /// like the first line of the macOS Wi-Fi menu.
    @Published private(set) var ethernetLabel: String?
    /// Last scan, strongest first, without the current network. Kept between
    /// popover opens so the list shows instantly.
    @Published private(set) var networks: [WiFiNetworkItem] = []
    @Published private(set) var isScanning = false
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var joiningSSID: String?
    @Published private(set) var joinError: String?
    /// A known secured network that would not join without a password; the
    /// popover opens its password field.
    @Published var passwordNeededSSID: String?

    var isLocationAuthorized: Bool {
        authorization == .authorized || authorization == .authorizedAlways
    }

    private let client = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()
    /// CoreWLAN calls are XPC round trips to airportd; scan and associate
    /// block for seconds. None of it runs on the main thread.
    private let queue = DispatchQueue(label: "FreeTheNotch.wifi", qos: .userInitiated)
    private var pathMonitor: NWPathMonitor?
    /// Latest path; written and read on `queue`.
    private var latestPath: NWPath?
    private var timer: Timer?
    /// Scan results by SSID, for `associate(to:password:)`. Main thread only.
    private var scanned: [String: CWNetwork] = [:]

    override init() {
        super.init()
        locationManager.delegate = self
        authorization = locationManager.authorizationStatus
    }

    // MARK: Lifecycle (only while the indicator is shown)

    func start() {
        guard timer == nil else { return }
        // NWPath reports association changes at once; the timer is only for
        // RSSI drift (DuoBar refreshes every 15 s too).
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.latestPath = path  // already on `queue`
            DispatchQueue.main.async { self?.refresh() }
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    /// Popover opened: ask for Location once (the app is active now, so the
    /// prompt can appear), re-read state and rescan in the background.
    func popoverOpened() {
        joinError = nil
        if authorization == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        refresh()
        scan()
    }

    func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: Reading

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let interface = self.client.interface()
            let power = interface?.powerOn() ?? false
            let raw = interface?.rssiValue() ?? 0
            let rssi = raw == 0 ? nil : raw
            let name = interface?.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines)
            let ssid = name?.isEmpty == false ? name : nil
            // Without Location the SSID is nil, so RSSI also counts as
            // "associated" (DuoBar's WiFiService does the same).
            let connected = power && (ssid != nil || rssi != nil)
            let bars = connected ? Self.bars(forRSSI: rssi ?? -60) : 0
            let known = Set(
                (interface?.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? [])
                    .compactMap(\.ssid))
            let ethernet = Self.ethernetLabel(for: self.latestPath)
            DispatchQueue.main.async {
                if self.knownSSIDs != known { self.knownSSIDs = known }
                if self.ethernetLabel != ethernet { self.ethernetLabel = ethernet }
                if self.hasInterface != (interface != nil) { self.hasInterface = interface != nil }
                if self.isPoweredOn != power { self.isPoweredOn = power }
                if self.isConnected != connected { self.isConnected = connected }
                if self.ssid != ssid { self.ssid = ssid }
                if self.bars != bars { self.bars = bars }
            }
        }
    }

    func scan() {
        guard timer != nil, !isScanning, isPoweredOn, isLocationAuthorized else { return }
        isScanning = true
        queue.async { [weak self] in
            guard let self else { return }
            let found = (try? self.client.interface()?.scanForNetworks(withSSID: nil)) ?? []
            var best: [String: CWNetwork] = [:]
            for network in found {
                guard let ssid = network.ssid, !ssid.isEmpty else { continue }
                if let existing = best[ssid], existing.rssiValue >= network.rssiValue { continue }
                best[ssid] = network
            }
            DispatchQueue.main.async {
                self.isScanning = false
                guard !found.isEmpty else { return }  // keep the cache on a failed scan
                self.scanned = best
                self.networks = best.values
                    .map {
                        WiFiNetworkItem(
                            ssid: $0.ssid ?? "", rssi: $0.rssiValue,
                            isSecure: !$0.supportsSecurity(.none))
                    }
                    .sorted { $0.rssi > $1.rssi }
            }
        }
    }

    /// The wired interface carrying traffic, named the way System Settings
    /// names it (SCNetworkInterface display name + BSD name).
    private static func ethernetLabel(for path: NWPath?) -> String? {
        guard let path, path.status == .satisfied,
            let wired = path.availableInterfaces.first(where: { $0.type == .wiredEthernet })
        else { return nil }
        let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let display = all.first { SCNetworkInterfaceGetBSDName($0) as String? == wired.name }
            .flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? }
        return "Ethernet: \(display ?? "Ethernet") (\(wired.name))"
    }

    /// DuoBar's thresholds: ≥ −67 dBm strong, ≥ −75 medium, else weak.
    static func bars(forRSSI rssi: Int) -> Int {
        if rssi >= -67 { return 3 }
        if rssi >= -75 { return 2 }
        return 1
    }

    // MARK: Actions

    func setPower(_ on: Bool) {
        isPoweredOn = on
        queue.async { [weak self] in
            do {
                try self?.client.interface()?.setPower(on)
            } catch {
                Logger.modules.error(
                    "[FreeTheNotch] Wi-Fi setPower(\(on ? 1 : 0, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            DispatchQueue.main.async {
                self?.refresh()
                if on { self?.scan() }
            }
        }
    }

    /// Best effort only. Networks that need more than a password (802.1X,
    /// captive portals) fail here; the popover then points to System Settings.
    func join(_ item: WiFiNetworkItem, password: String?) {
        guard let network = scanned[item.ssid], joiningSSID == nil else { return }
        joiningSSID = item.ssid
        joinError = nil
        queue.async { [weak self] in
            var message: String?
            do {
                try self?.client.interface()?.associate(to: network, password: password)
            } catch {
                message = error.localizedDescription
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.joiningSSID = nil
                if message != nil, password == nil, item.isSecure {
                    // Saved passwords live in the System keychain, which
                    // CoreWLAN does not read for us: ask instead.
                    self.passwordNeededSSID = item.ssid
                } else {
                    self.joinError = message.map { "Couldn't join \u{201C}\(item.ssid)\u{201D}: \($0)" }
                }
                self.refresh()
            }
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.authorization = status
            self.refresh()
            self.scan()
        }
    }
}
