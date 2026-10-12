import Combine
import Foundation

// MARK: - Option types

/// Where the notch and Side Notch appear (one setting for both).
enum DisplayScope: String, CaseIterable {
    /// Built-in display only. The raw value is the old name ("Main display
    /// only"), kept so stored settings still load.
    case mainOnly
    /// The display that holds the menu bar (System Settings → Displays →
    /// "Use as main display").
    case mainDisplay
    case allDisplays

    var title: String {
        switch self {
        case .mainOnly: return "Built-in"
        case .mainDisplay: return "Main display"
        case .allDisplays: return "All displays"
        }
    }

    var subtitle: String {
        switch self {
        case .mainOnly: return "Hidden while the lid is closed"
        case .mainDisplay: return "The one with the menu bar"
        case .allDisplays: return "Every connected screen"
        }
    }
}

// MARK: - Settings store

/// All user settings, persisted to UserDefaults under `ftn.<name>` keys.
/// Local-only: nothing here ever leaves the machine.
///
/// Adding a setting: a `@Published` property with its default, plus one
/// line in `persisted` naming its key. Any change is saved 0.3 s later
/// (`flush()` saves at once); loading never triggers a save.
@MainActor
final class SettingsStore: ObservableObject {
    /// Jiggle intervals (minutes).
    static let allowedJiggleIntervals = [1, 2, 3, 5]
    /// Clipboard history sizes offered in Settings.
    static let clipboardLimits = [5, 10, 25, 50]
    static let keyPrefix = "ftn."
    /// Changes are written this long after the last one.
    static let saveDelay: TimeInterval = 0.3

    private let defaults: UserDefaults
    private var saveWorkItem: DispatchWorkItem?
    private var saveOnChange: AnyCancellable?

    // MARK: General
    @Published var hoverDelay = 0.3
    /// `DisplayScope` raw value.
    @Published var displayScopeRaw = DisplayScope.allDisplays.rawValue
    @Published var liquidGlass = true
    /// Atoll's "Remember last tab" (`openLastTabByDefault`, default off):
    /// off = the notch and the menu-bar panel reopen on their first tab.
    @Published var rememberLastTab = false
    /// Atoll's `hideDynamicIslandFromScreenCapture`; on by default here.
    @Published var hideFromScreenCapture = true

    // MARK: Side Notch
    /// Black pill on a side edge holding DuoGlyph and Bluetooth (SideNotchWindowController).
    @Published var sideNotchEnabled = false
    /// Side Notch zoom, 1× or 2×. 1× is 75 % of CodeNotch's size (`SideNotchLayout.baseScale`).
    @Published var sideNotchZoom = 1.0
    /// `SideNotchEdge` raw value. A Dock on the left or right overrides it (DockSide).
    @Published var sideNotchEdgeRaw = SideNotchEdge.right.rawValue
    /// Side Notch cells top to bottom, comma-separated `SideNotchCell` raw values.
    @Published var sideNotchOrderRaw = ""

    // MARK: Calendar
    /// Vietnamese lunar date under the calendar's day title ("1/9 năm Bính Ngọ").
    @Published var showLunarDate = true

    // MARK: Notch pages
    /// Battery strip at the bottom of the Home page.
    @Published var homeBatteryStrip = true
    /// One-line "Quote of the Day" at the top of the Home page. Off by default.
    @Published var homeQuote = false
    /// `QuoteSource` raw value: ZenQuotes online (default) or the built-in list.
    @Published var quoteSourceRaw = QuoteSource.online.rawValue
    /// Hours between quotes, one of `QuoteStore.intervals` (1, 2, 4, 8, 24).
    @Published var quoteIntervalHours = 24
    /// Page order in the open notch, comma-separated `NotchPage` raw values.
    @Published var notchTabOrderRaw = ""
    /// Hidden page raw values; at least one page remains visible.
    @Published var hiddenNotchTabsRaw = ""
    @Published var codexUsageEnabled = true {
        didSet { synchronizeAIUsageVisibility(wasEnabled: oldValue || claudeUsageEnabled) }
    }
    @Published var claudeUsageEnabled = true {
        didSet { synchronizeAIUsageVisibility(wasEnabled: oldValue || codexUsageEnabled) }
    }

    @Published var aiLiveActivitiesEnabled = true
    @Published var aiQuotaHUDEnabled = true

    // MARK: Notch skin (NotchSkin.swift)
    /// `NotchSkin` raw value.
    @Published var notchSkinRaw = NotchSkin.none.rawValue
    /// Pet size for the built-in skins.
    @Published var skinPetScale = 1.0
    /// Custom skin: pet size per animation name (1 when unset), so an
    /// imported file can be sized to match the bundled pets.
    @Published var customPetScales: [String: Double] = [:]
    @Published var skinHideWhenExpanded = true
    /// Custom skin's pet: file name (without .json), bundled or imported.
    @Published var idleAnimationName = "Orange Cat Peeping"
    @Published var idleAnimationSpeed = 1.0

    // MARK: Modules
    @Published var mediaEnabled = true
    @Published var clipboardEnabled = true
    @Published var capsLockEnabled = true
    @Published var bluetoothPopupEnabled = true

    // MARK: Clipboard
    @Published var clipboardLimit = 25
    /// `ClipboardRetention` raw value.
    @Published var clipboardRetentionRaw = ClipboardRetention.keep.rawValue

    // MARK: Utilities
    @Published var awakePauseWhileLocked = true
    @Published var awakeBatteryProtection = true
    @Published var awakeMouseJiggle = true
    /// One of `allowedJiggleIntervals`.
    @Published var awakeMouseJiggleIntervalMinutes = 1
    @Published var cleaningLockTrackpad = true
    @Published var smoothScrollEnabled = false
    @Published var smoothScrollStep = SmoothScrollSupport.defaultStep
    @Published var smoothScrollResponse = SmoothScrollSupport.defaultResponse
    @Published var smoothScrollCoast = SmoothScrollSupport.defaultCoast
    /// Application bundle identifiers whose wheels retain native behavior.
    @Published var smoothScrollExcludedApps: [String] = []

    // MARK: HUD
    @Published var hudVolume = true
    @Published var hudBacklight = true

    // MARK: Battery HUD (Atoll's power status notifications; same defaults)
    @Published var batteryHUDEnabled = true
    @Published var batteryHUDCharging = true
    @Published var batteryHUDLow = true
    @Published var batteryHUDFull = true
    @Published var lowBatteryThreshold = 20
    @Published var lowBatterySound = true

    // MARK: Lock screen widgets
    @Published var lockMedia = true
    @Published var lockTimer = true
    @Published var lockBattery = true
    @Published var lockAirPods = true
    @Published var lockBluetooth = true
    @Published var lockWeather = true
    @Published var lockAQI = true
    @Published var lockEventRow = true
    /// While locked and playing, the artwork becomes the wallpaper (LockArtworkWallpaper).
    @Published var lockArtworkWallpaper = false

    /// Every stored setting and its key (without the `ftn.` prefix). The
    /// value is stored as the property's own type.
    private static let persisted: [PersistedSetting] = [
        PersistedSetting("hoverDelay", \.hoverDelay),
        PersistedSetting("displayScope", \.displayScopeRaw),
        PersistedSetting("liquidGlass", \.liquidGlass),
        PersistedSetting("rememberLastTab", \.rememberLastTab),
        PersistedSetting("hideFromScreenCapture", \.hideFromScreenCapture),
        PersistedSetting("sideNotchEnabled", \.sideNotchEnabled),
        PersistedSetting("sideNotchZoom", \.sideNotchZoom),
        PersistedSetting("sideNotchEdge", \.sideNotchEdgeRaw),
        PersistedSetting("sideNotchOrder", \.sideNotchOrderRaw),
        PersistedSetting("showLunarDate", \.showLunarDate),
        PersistedSetting("homeBatteryStrip", \.homeBatteryStrip),
        PersistedSetting("homeQuote", \.homeQuote),
        PersistedSetting("quoteSource", \.quoteSourceRaw),
        PersistedSetting("quoteIntervalHours", \.quoteIntervalHours),
        PersistedSetting("notchTabOrder", \.notchTabOrderRaw),
        PersistedSetting("hiddenNotchTabs", \.hiddenNotchTabsRaw),
        PersistedSetting("codexUsageEnabled", \.codexUsageEnabled),
        PersistedSetting("claudeUsageEnabled", \.claudeUsageEnabled),
        PersistedSetting("aiLiveActivitiesEnabled", \.aiLiveActivitiesEnabled),
        PersistedSetting("aiQuotaHUDEnabled", \.aiQuotaHUDEnabled),
        PersistedSetting("notchSkin", \.notchSkinRaw),
        PersistedSetting("skinPetScale", \.skinPetScale),
        PersistedSetting("customPetScales", \.customPetScales),
        PersistedSetting("skinHideWhenExpanded", \.skinHideWhenExpanded),
        PersistedSetting("idleAnimationName", \.idleAnimationName),
        PersistedSetting("idleAnimationSpeed", \.idleAnimationSpeed),
        PersistedSetting("mediaEnabled", \.mediaEnabled),
        PersistedSetting("clipboardEnabled", \.clipboardEnabled),
        PersistedSetting("capsLockEnabled", \.capsLockEnabled),
        PersistedSetting("bluetoothPopupEnabled", \.bluetoothPopupEnabled),
        PersistedSetting("clipboardLimit", \.clipboardLimit),
        PersistedSetting("clipboardRetention", \.clipboardRetentionRaw),
        PersistedSetting("awakePauseWhileLocked", \.awakePauseWhileLocked),
        PersistedSetting("awakeBatteryProtection", \.awakeBatteryProtection),
        PersistedSetting("awakeMouseJiggle", \.awakeMouseJiggle),
        PersistedSetting("awakeMouseJiggleIntervalMinutes", \.awakeMouseJiggleIntervalMinutes),
        PersistedSetting("cleaningLockTrackpad", \.cleaningLockTrackpad),
        PersistedSetting("smoothScrollEnabled", \.smoothScrollEnabled),
        PersistedSetting("smoothScrollStep", \.smoothScrollStep),
        PersistedSetting("smoothScrollResponse", \.smoothScrollResponse),
        PersistedSetting("smoothScrollCoast", \.smoothScrollCoast),
        PersistedSetting("smoothScrollExcludedApps", \.smoothScrollExcludedApps),
        PersistedSetting("hudVolume", \.hudVolume),
        PersistedSetting("hudBacklight", \.hudBacklight),
        PersistedSetting("batteryHUDEnabled", \.batteryHUDEnabled),
        PersistedSetting("batteryHUDCharging", \.batteryHUDCharging),
        PersistedSetting("batteryHUDLow", \.batteryHUDLow),
        PersistedSetting("batteryHUDFull", \.batteryHUDFull),
        PersistedSetting("lowBatteryThreshold", \.lowBatteryThreshold),
        PersistedSetting("lowBatterySound", \.lowBatterySound),
        PersistedSetting("lockMedia", \.lockMedia),
        PersistedSetting("lockTimer", \.lockTimer),
        PersistedSetting("lockBattery", \.lockBattery),
        PersistedSetting("lockAirPods", \.lockAirPods),
        PersistedSetting("lockBluetooth", \.lockBluetooth),
        PersistedSetting("lockWeather", \.lockWeather),
        PersistedSetting("lockAQI", \.lockAQI),
        PersistedSetting("lockEventRow", \.lockEventRow),
        PersistedSetting("lockArtworkWallpaper", \.lockArtworkWallpaper),
    ]

    // MARK: Typed accessors

    var displayScope: DisplayScope {
        get { DisplayScope(rawValue: displayScopeRaw) ?? .allDisplays }
        set { displayScopeRaw = newValue.rawValue }
    }
    var sideNotchEdge: SideNotchEdge {
        get { SideNotchEdge(rawValue: sideNotchEdgeRaw) ?? .right }
        set { sideNotchEdgeRaw = newValue.rawValue }
    }
    var quoteSource: QuoteSource {
        get { QuoteSource(rawValue: quoteSourceRaw) ?? .online }
        set { quoteSourceRaw = newValue.rawValue }
    }
    /// Saved order, with unknown pages dropped and new pages appended.
    var notchTabOrder: [NotchPage] {
        get {
            var order: [NotchPage] = Self.normalizedOrder(notchTabOrderRaw)
            if !notchTabOrderRaw.split(separator: ",").contains("aiUsage"),
                let clipboardIndex = order.firstIndex(of: .clipboard)
            {
                order.removeAll { $0 == .aiUsage }
                order.insert(.aiUsage, at: clipboardIndex + 1)
            }
            return [.home] + order.filter { $0 != .home }
        }
        set { notchTabOrderRaw = Self.storedOrder([.home] + newValue.filter { $0 != .home }) }
    }
    var enabledAIUsageProviders: [AIUsageProvider] {
        AIUsageProvider.allCases.filter { $0 == .codex ? codexUsageEnabled : claudeUsageEnabled }
    }

    private func synchronizeAIUsageVisibility(wasEnabled: Bool) {
        let isEnabled = codexUsageEnabled || claudeUsageEnabled
        if !isEnabled {
            setNotchTabVisible(.aiUsage, isVisible: false)
        } else if !wasEnabled {
            setNotchTabVisible(.aiUsage, isVisible: true)
        }
    }

    var visibleNotchTabs: [NotchPage] {
        let hidden = Set(hiddenNotchTabsRaw.split(separator: ",").compactMap { NotchPage(rawValue: String($0)) })
        return notchTabOrder.filter {
            $0 == .home || (!hidden.contains($0) && ($0 != .aiUsage || !enabledAIUsageProviders.isEmpty))
        }
    }

    func isNotchTabVisible(_ page: NotchPage) -> Bool { visibleNotchTabs.contains(page) }

    func setNotchTabVisible(_ page: NotchPage, isVisible: Bool) {
        guard page != .home, page != .aiUsage || !isVisible || !enabledAIUsageProviders.isEmpty else { return }
        var hidden = Set(hiddenNotchTabsRaw.split(separator: ",").compactMap { NotchPage(rawValue: String($0)) })
        if isVisible { hidden.remove(page) } else { hidden.insert(page) }
        hiddenNotchTabsRaw = Self.storedOrder(NotchPage.allCases.filter { $0 != .home && hidden.contains($0) })
    }

    /// Saved Side Notch order, with unknown cells dropped and new cells appended.
    var sideNotchOrder: [SideNotchCell] {
        get {
            Self.normalizedOrder(
                sideNotchOrderRaw.split(separator: ",").map {
                    $0 == "panel" ? "keepAwake,system,network,disk,power" : String($0)
                }.joined(separator: ","))
        }
        set { sideNotchOrderRaw = Self.storedOrder(newValue) }
    }
    /// Pet size for a skin: the built-in skins share `skinPetScale`, the
    /// Custom skin remembers one per animation.
    func petScale(for skin: NotchSkin) -> Double {
        skin == .custom ? customPetScales[idleAnimationName] ?? 1 : skinPetScale
    }

    func setPetScale(_ scale: Double, for skin: NotchSkin) {
        if skin == .custom {
            customPetScales[idleAnimationName] = scale
        } else {
            skinPetScale = scale
        }
    }

    var notchSkin: NotchSkin {
        get { NotchSkin(rawValue: notchSkinRaw) ?? .none }
        set { notchSkinRaw = newValue.rawValue }
    }
    var clipboardRetention: ClipboardRetention {
        get { ClipboardRetention(rawValue: clipboardRetentionRaw) ?? .keep }
        set { clipboardRetentionRaw = newValue.rawValue }
    }

    /// A comma-separated order as stored: duplicates and unknown values
    /// dropped, then every missing case appended in declaration order.
    nonisolated static func normalizedOrder<Item: CaseIterable & RawRepresentable & Equatable>(
        _ raw: String
    ) -> [Item] where Item.RawValue == String {
        var order: [Item] = []
        for item in raw.split(separator: ",").compactMap({ Item(rawValue: String($0)) }) where !order.contains(item) {
            order.append(item)
        }
        return order + Item.allCases.filter { !order.contains($0) }
    }

    nonisolated static func storedOrder<Item: RawRepresentable>(_ order: [Item]) -> String
    where Item.RawValue == String {
        order.map(\.rawValue).joined(separator: ",")
    }

    // MARK: Persistence

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrate(defaults)
        load()
        // Subscribed after loading, so loading never schedules a save.
        saveOnChange = objectWillChange.sink { [weak self] _ in self?.scheduleSave() }
    }

    /// Whether a change is waiting to be written.
    var hasPendingSave: Bool { saveWorkItem != nil }

    /// Writes a pending change now (on quit, where the delayed save would
    /// never run).
    func flush() {
        guard let saveWorkItem else { return }
        saveWorkItem.cancel()
        self.saveWorkItem = nil
        save()
    }

    /// Keys from earlier versions.
    private static func migrate(_ defaults: UserDefaults) {
        // DuoGlyph became Side Notch: carry its switch and zoom over once.
        for (old, new) in [("duoGlyphEnabled", "sideNotchEnabled"), ("duoGlyphZoom", "sideNotchZoom")] {
            if defaults.object(forKey: keyPrefix + new) == nil, let value = defaults.object(forKey: keyPrefix + old) {
                defaults.set(value, forKey: keyPrefix + new)
            }
            defaults.removeObject(forKey: keyPrefix + old)
        }
        defaults.removeObject(forKey: keyPrefix + "duoGlyphCorner")
        // A "Dark text" switch that only ever recoloured the event line.
        defaults.removeObject(forKey: keyPrefix + "lockDarkText")
    }

    private func load() {
        for setting in Self.persisted {
            if let stored = defaults.object(forKey: setting.key) {
                setting.load(self, stored)
            }
        }
        smoothScrollStep = SmoothScrollSupport.sanitizedStep(smoothScrollStep)
        smoothScrollResponse = SmoothScrollSupport.sanitizedResponse(smoothScrollResponse)
        smoothScrollCoast = SmoothScrollSupport.sanitizedCoast(smoothScrollCoast)
        smoothScrollExcludedApps = SmoothScrollSupport.sanitizedExclusions(smoothScrollExcludedApps)
        sideNotchZoom = sideNotchZoom >= 1.5 ? 2 : 1
        if !Self.allowedJiggleIntervals.contains(awakeMouseJiggleIntervalMinutes) {
            awakeMouseJiggleIntervalMinutes = 1
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.saveWorkItem = nil
                self?.save()
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: item)
    }

    private func save() {
        for setting in Self.persisted {
            defaults.set(setting.value(self), forKey: setting.key)
        }
    }
}

/// One stored setting: its UserDefaults key and how to move its value
/// between the store and a property-list value.
@MainActor
private struct PersistedSetting {
    let key: String
    let load: (SettingsStore, Any) -> Void
    let value: (SettingsStore) -> Any

    init<Value>(_ name: String, _ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) {
        key = SettingsStore.keyPrefix + name
        // A stored value of the wrong type keeps the default.
        load = { store, stored in
            if let value = stored as? Value { store[keyPath: keyPath] = value }
        }
        value = { $0[keyPath: keyPath] }
    }
}
