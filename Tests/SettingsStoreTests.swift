import Foundation
import Testing

/// SettingsStore against a throwaway UserDefaults suite. Keys and stored
/// types must never change: they are the user's saved settings.
@MainActor
struct SettingsStoreTests {
    /// A fresh suite, removed again when the test ends.
    private final class Suite {
        let name = "FreeTheNotchTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() {
            defaults = UserDefaults(suiteName: name)!
        }

        deinit { defaults.removePersistentDomain(forName: name) }
    }

    @Test func emptyStoreHasTheDefaultsAndWritesNothing() {
        let suite = Suite()
        let store = SettingsStore(defaults: suite.defaults)
        #expect(store.hoverDelay == 0.3)
        #expect(store.displayScope == .allDisplays)
        #expect(store.sideNotchEdge == .right)
        #expect(store.quoteSource == .online)
        #expect(store.notchSkin == .none)
        #expect(store.clipboardRetention == .keep)
        #expect(store.notchTabOrder == NotchPage.allCases)
        #expect(store.sideNotchOrder == SideNotchCell.allCases)
        #expect(store.awakeMouseJiggleIntervalMinutes == 1)
        #expect(store.lockArtworkWallpaper == false)
        #expect(store.lockMedia)
        #expect(!store.hasPendingSave)
        #expect(suite.defaults.object(forKey: "ftn.hoverDelay") == nil)
    }

    @Test func aiNotificationSwitchesPersistIndependentlyOfProviderVisibility() {
        let suite = Suite()
        let store = SettingsStore(defaults: suite.defaults)
        #expect(store.aiLiveActivitiesEnabled)
        #expect(store.aiQuotaHUDEnabled)
        store.aiLiveActivitiesEnabled = false
        store.aiQuotaHUDEnabled = false
        store.flush()
        let restored = SettingsStore(defaults: suite.defaults)
        #expect(!restored.aiLiveActivitiesEnabled)
        #expect(!restored.aiQuotaHUDEnabled)
        #expect(restored.codexUsageEnabled && restored.claudeUsageEnabled)
    }

    @Test func loadsStoredValues() {
        let suite = Suite()
        suite.defaults.set(0.5, forKey: "ftn.hoverDelay")
        suite.defaults.set("mainOnly", forKey: "ftn.displayScope")
        suite.defaults.set("left", forKey: "ftn.sideNotchEdge")
        suite.defaults.set(false, forKey: "ftn.lockMedia")
        suite.defaults.set(50, forKey: "ftn.clipboardLimit")
        suite.defaults.set("panel,duo", forKey: "ftn.sideNotchOrder")
        let store = SettingsStore(defaults: suite.defaults)
        #expect(store.hoverDelay == 0.5)
        #expect(store.displayScope == .mainOnly)
        #expect(store.sideNotchEdge == .left)
        #expect(!store.lockMedia)
        #expect(store.clipboardLimit == 50)
        #expect(store.sideNotchOrder == [.keepAwake, .system, .network, .disk, .power, .duo, .bluetooth])
        // Loading is not a change.
        #expect(!store.hasPendingSave)
    }

    @Test func storedValuesOfTheWrongTypeKeepTheDefault() {
        let suite = Suite()
        suite.defaults.set("fast", forKey: "ftn.hoverDelay")
        suite.defaults.set("yes", forKey: "ftn.lockMedia")
        suite.defaults.set("sideways", forKey: "ftn.displayScope")
        let store = SettingsStore(defaults: suite.defaults)
        #expect(store.hoverDelay == 0.3)
        #expect(store.lockMedia)
        // An unknown raw value reads as the stored default too.
        #expect(store.displayScope == .allDisplays)
    }

    @Test func duoGlyphKeysMoveToSideNotchOnce() {
        let suite = Suite()
        suite.defaults.set(true, forKey: "ftn.duoGlyphEnabled")
        suite.defaults.set(2.0, forKey: "ftn.duoGlyphZoom")
        suite.defaults.set("topRight", forKey: "ftn.duoGlyphCorner")
        let store = SettingsStore(defaults: suite.defaults)
        #expect(store.sideNotchEnabled)
        #expect(store.sideNotchZoom == 2)
        #expect(suite.defaults.bool(forKey: "ftn.sideNotchEnabled"))
        #expect(suite.defaults.double(forKey: "ftn.sideNotchZoom") == 2)
        for key in ["ftn.duoGlyphEnabled", "ftn.duoGlyphZoom", "ftn.duoGlyphCorner"] {
            #expect(suite.defaults.object(forKey: key) == nil)
        }
    }

    @Test func migrationNeverOverwritesASideNotchValue() {
        let suite = Suite()
        suite.defaults.set(false, forKey: "ftn.sideNotchEnabled")
        suite.defaults.set(true, forKey: "ftn.duoGlyphEnabled")
        let store = SettingsStore(defaults: suite.defaults)
        #expect(!store.sideNotchEnabled)
        #expect(suite.defaults.object(forKey: "ftn.duoGlyphEnabled") == nil)
    }

    @Test func removedDarkTextKeyIsDeleted() {
        let suite = Suite()
        suite.defaults.set(true, forKey: "ftn.lockDarkText")
        _ = SettingsStore(defaults: suite.defaults)
        #expect(suite.defaults.object(forKey: "ftn.lockDarkText") == nil)
    }

    @Test(arguments: [(4, 1), (0, 1), (2, 2), (5, 5)])
    func jiggleIntervalMustBeOffered(stored: Int, expected: Int) {
        let suite = Suite()
        suite.defaults.set(stored, forKey: "ftn.awakeMouseJiggleIntervalMinutes")
        #expect(SettingsStore(defaults: suite.defaults).awakeMouseJiggleIntervalMinutes == expected)
    }

    @Test func aChangeIsSavedOnFlushAndLoadsBack() {
        let suite = Suite()
        let store = SettingsStore(defaults: suite.defaults)
        store.hoverDelay = 0.7
        store.sideNotchEdge = .left
        store.lockArtworkWallpaper = true
        #expect(store.hasPendingSave)
        store.flush()
        #expect(!store.hasPendingSave)
        #expect(suite.defaults.double(forKey: "ftn.hoverDelay") == 0.7)
        let reloaded = SettingsStore(defaults: suite.defaults)
        #expect(reloaded.hoverDelay == 0.7)
        #expect(reloaded.sideNotchEdge == .left)
        #expect(reloaded.lockArtworkWallpaper)
    }

    @Test func smoothScrollingIsOffByDefaultAndAllControlsPersist() {
        let suite = Suite()
        let store = SettingsStore(defaults: suite.defaults)
        #expect(!store.smoothScrollEnabled)
        #expect(store.smoothScrollStep == 40)
        #expect(store.smoothScrollResponse == 65)
        #expect(store.smoothScrollCoast == 0)
        #expect(store.smoothScrollExcludedApps.isEmpty)
        store.smoothScrollEnabled = true
        store.smoothScrollStep = 70
        store.smoothScrollResponse = 80
        store.smoothScrollCoast = 25
        store.smoothScrollExcludedApps = ["com.example.app"]
        store.flush()
        let reloaded = SettingsStore(defaults: suite.defaults)
        #expect(reloaded.smoothScrollEnabled)
        #expect(reloaded.smoothScrollStep == 70)
        #expect(reloaded.smoothScrollResponse == 80)
        #expect(reloaded.smoothScrollCoast == 25)
        #expect(reloaded.smoothScrollExcludedApps == ["com.example.app"])
        #expect(suite.defaults.bool(forKey: "ftn.smoothScrollEnabled"))
        #expect(suite.defaults.stringArray(forKey: "ftn.smoothScrollExcludedApps") == ["com.example.app"])
    }

    @Test func invalidSmoothScrollingPreferencesLoadWithinTheAllowedRanges() {
        let suite = Suite()
        suite.defaults.set(0, forKey: "ftn.smoothScrollStep")
        suite.defaults.set(200, forKey: "ftn.smoothScrollResponse")
        suite.defaults.set(-5, forKey: "ftn.smoothScrollCoast")
        suite.defaults.set([" com.example.app ", "", "com.example.app"], forKey: "ftn.smoothScrollExcludedApps")
        let store = SettingsStore(defaults: suite.defaults)
        #expect(store.smoothScrollStep == 40)
        #expect(store.smoothScrollResponse == 100)
        #expect(store.smoothScrollCoast == 0)
        #expect(store.smoothScrollExcludedApps == ["com.example.app"])
        #expect(!store.hasPendingSave)
    }

    @Test func customPetSizeIsRememberedPerAnimation() {
        let suite = Suite()
        let store = SettingsStore(defaults: suite.defaults)
        store.skinPetScale = 1.2
        store.idleAnimationName = "Pikachu"
        store.setPetScale(2.0, for: .custom)
        store.idleAnimationName = "Moody Dog"
        #expect(store.petScale(for: .custom) == 1)
        #expect(store.petScale(for: .sakura) == 1.2)

        store.flush()
        let reloaded = SettingsStore(defaults: suite.defaults)
        reloaded.idleAnimationName = "Pikachu"
        #expect(reloaded.petScale(for: .custom) == 2.0)
        #expect(reloaded.petScale(for: .jungle) == 1.2)
        #expect(suite.defaults.dictionary(forKey: "ftn.customPetScales") as? [String: Double] == ["Pikachu": 2.0])
    }

    @Test func flushWithoutAChangeWritesNothing() {
        let suite = Suite()
        let store = SettingsStore(defaults: suite.defaults)
        store.flush()
        #expect(suite.defaults.object(forKey: "ftn.hoverDelay") == nil)
    }

    /// The stored representation: `ftn.` keys, raw-value strings, plain numbers.
    @Test func savedValuesKeepTheirKeysAndTypes() {
        let suite = Suite()
        let store = SettingsStore(defaults: suite.defaults)
        store.displayScope = .mainDisplay
        store.quoteSource = .builtIn
        store.flush()
        let defaults = suite.defaults
        #expect(defaults.object(forKey: "ftn.displayScope") as? String == "mainDisplay")
        #expect(defaults.object(forKey: "ftn.quoteSource") as? String == "builtIn")
        #expect(defaults.object(forKey: "ftn.sideNotchEdge") as? String == "right")
        #expect(defaults.object(forKey: "ftn.notchTabOrder") as? String == "")
        #expect(defaults.object(forKey: "ftn.clipboardLimit") as? Int == 25)
        #expect(defaults.object(forKey: "ftn.sideNotchZoom") as? Double == 1)
        #expect(defaults.object(forKey: "ftn.lockArtworkWallpaper") as? Bool == false)
        #expect(defaults.object(forKey: "ftn.idleAnimationName") as? String == "Orange Cat Peeping")
    }

    @Test func typedAccessorsWriteRawValues() {
        let suite = Suite()
        let store = SettingsStore(defaults: suite.defaults)
        store.notchTabOrder = [.timer, .home]
        #expect(store.notchTabOrderRaw == "home,timer")
        #expect(store.notchTabOrder == [.home, .timer, .clipboard, .aiUsage, .calculator, .qr])
        store.clipboardRetention = .oneDay
        #expect(store.clipboardRetentionRaw == ClipboardRetention.oneDay.rawValue)
    }

    @Test(arguments: [
        ("", SideNotchCell.allCases),
        ("keepAwake,system,network,disk,power", [.keepAwake, .system, .network, .disk, .power, .duo, .bluetooth]),
        ("keepAwake,duo,keepAwake,bogus,bluetooth", [.keepAwake, .duo, .bluetooth, .system, .network, .disk, .power]),
        ("bluetooth,,duo", [.bluetooth, .duo, .keepAwake, .system, .network, .disk, .power]),
    ])
    func orderIsNormalised(_ raw: String, expected: [SideNotchCell]) {
        let order: [SideNotchCell] = SettingsStore.normalizedOrder(raw)
        #expect(order == expected)
    }

    @Test func hiddenTabsStayOrderedAndCannotHideTheLastPage() {
        let suite = Suite()
        let store = SettingsStore(defaults: suite.defaults)
        store.setNotchTabVisible(.clipboard, isVisible: false)
        #expect(store.visibleNotchTabs == [.home, .aiUsage, .timer, .calculator, .qr])
        store.setNotchTabVisible(.clipboard, isVisible: true)
        #expect(store.visibleNotchTabs == NotchPage.allCases)
        for page in NotchPage.allCases { store.setNotchTabVisible(page, isVisible: false) }
        #expect(store.visibleNotchTabs == [.home])
        store.flush()
        #expect(SettingsStore(defaults: suite.defaults).visibleNotchTabs == [.home])
    }

    @Test func homeCannotBeHiddenOrMovedAndDisablingBothProvidersHidesAIUsage() {
        let suite = Suite()
        let store = SettingsStore(defaults: suite.defaults)
        store.notchTabOrder = [.timer, .clipboard, .home]
        #expect(store.notchTabOrder.first == .home)
        store.setNotchTabVisible(.home, isVisible: false)
        #expect(store.visibleNotchTabs.first == .home)
        store.codexUsageEnabled = false
        store.claudeUsageEnabled = false
        #expect(!store.isNotchTabVisible(.aiUsage))
        store.claudeUsageEnabled = true
        #expect(store.isNotchTabVisible(.aiUsage))
    }

    @Test func invalidHiddenTabsStillLeaveHomeReachable() {
        let suite = Suite()
        suite.defaults.set("home,clipboard,aiUsage,timer,calculator,qr", forKey: "ftn.hiddenNotchTabs")
        let store = SettingsStore(defaults: suite.defaults)
        #expect(store.visibleNotchTabs == [.home])
    }

    @Test func legacyPanelExpandsAtItsSavedPosition() {
        let suite = Suite()
        suite.defaults.set("bluetooth,panel,duo", forKey: "ftn.sideNotchOrder")
        let store = SettingsStore(defaults: suite.defaults)
        #expect(store.sideNotchOrder == [.bluetooth, .keepAwake, .system, .network, .disk, .power, .duo])
    }

    @Test(arguments: [(1.0, 1.0), (1.25, 1.0), (1.75, 2.0), (3.0, 2.0)])
    func sideNotchZoomLoadsAsOneOrTwo(_ stored: Double, expected: Double) {
        let suite = Suite()
        suite.defaults.set(stored, forKey: "ftn.sideNotchZoom")
        let store = SettingsStore(defaults: suite.defaults)
        #expect(store.sideNotchZoom == expected)
    }

    @Test func orderIsStoredCommaSeparated() {
        #expect(SettingsStore.storedOrder([SideNotchCell.keepAwake, .duo]) == "keepAwake,duo")
        #expect(SettingsStore.storedOrder([SideNotchCell]()) == "")
    }
}
