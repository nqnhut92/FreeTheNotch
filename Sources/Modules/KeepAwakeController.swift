import Combine
import CoreGraphics
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// Keep-awake via a power assertion (IOPMAssertion) — the same mechanism as
/// `caffeinate` — plus an optional Vorssaint-style mouse jiggle that nudges
/// the cursor one pixel every few minutes so apps like Microsoft Teams keep
/// reporting "Available" (a power assertion alone does not do that; Teams
/// uses its own presence heuristics).
///
/// Note: jiggling needs Accessibility permission (System Settings → Privacy &
/// Security → Accessibility). Without it the synthetic mouse events are
/// silently dropped.
@MainActor
final class KeepAwakeController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds: Int = 0
    /// End of a timed session; nil while idle or for an open-ended session.
    @Published private(set) var endDate: Date?
    /// Minutes of the running duration-chip session (0 = until stopped).
    /// nil while idle or for an "Until…" (end-time) session.
    @Published private(set) var sessionMinutes: Int?

    /// Battery protection blocks (and ends) sessions at or below this charge
    /// while running on battery.
    static let batteryProtectionThreshold = 20

    /// The last duration picked, reused by the panel's master switch.
    private(set) var lastMinutes: Int = 0

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?
    private var jiggleTimer: Timer?
    private var pendingMouseReturn: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var lockObservers: [NSObjectProtocol] = []
    private var ticks = 0
    private weak var settings: SettingsStore?

    /// Wire to the settings store so the jiggle toggle/interval take effect.
    func configure(with settings: SettingsStore) {
        self.settings = settings
        settings.$awakeMouseJiggle
            .combineLatest(settings.$awakeMouseJiggleIntervalMinutes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncJiggleTimer() }
            .store(in: &cancellables)
        settings.$awakePauseWhileLocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.syncAssertionWithLockState() }
            }
            .store(in: &cancellables)
        settings.$awakeBatteryProtection
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.enforceBatteryProtection() }
            }
            .store(in: &cancellables)

        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            lockObservers.append(
                center.addObserver(
                    forName: Notification.Name(name),
                    object: nil, queue: .main
                ) { [weak self] _ in
                    // The session dictionary updates a moment after the notification.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.syncAssertionWithLockState()
                        self?.syncJiggleTimer()
                    }
                })
        }
    }

    deinit {
        for observer in lockObservers { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    /// - Parameter minutes: 0 means "until stopped manually".
    func start(minutes: Int) {
        lastMinutes = minutes
        begin(
            endDate: minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : nil,
            sessionMinutes: minutes)
    }

    /// Keep awake until a wall-clock time (the panel's "Until…" chip).
    func start(until date: Date) {
        guard date > Date() else { return }
        begin(endDate: date, sessionMinutes: nil)
    }

    /// Restart the last picked duration (the panel's master switch).
    func startLastPick() {
        start(minutes: lastMinutes)
    }

    /// Push the end of a running timed session back.
    func extend(minutes: Int) {
        guard isActive, let end = endDate else { return }
        endDate = end.addingTimeInterval(TimeInterval(minutes * 60))
        updateRemaining()
    }

    func stop() {
        releaseAssertion()
        timer?.invalidate()
        timer = nil
        stopJiggleTimer()
        remainingSeconds = 0
        endDate = nil
        sessionMinutes = nil
        isActive = false
    }

    // MARK: - Session

    private func begin(endDate: Date?, sessionMinutes: Int?) {
        stop()
        // Battery protection would end the session at once; don't start.
        guard batteryProtectionPercent() == nil else { return }
        if !(settings?.awakePauseWhileLocked == true && Self.isScreenLocked) {
            guard acquireAssertion() else { return }
        }
        self.endDate = endDate
        self.sessionMinutes = sessionMinutes
        isActive = true
        updateRemaining()
        syncJiggleTimer()

        ticks = 0
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        ticks += 1
        if endDate != nil {
            updateRemaining()
            if remainingSeconds <= 0 {
                stop()
                return
            }
        }
        if ticks % 30 == 0 { enforceBatteryProtection() }
    }

    private func updateRemaining() {
        remainingSeconds = endDate.map { max(0, Int($0.timeIntervalSinceNow.rounded(.up))) } ?? 0
    }

    @discardableResult
    private func acquireAssertion() -> Bool {
        guard assertionID == 0 else { return true }
        var id: IOPMAssertionID = 0
        let reason = "FreeTheNotch keep-awake" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason, &id)
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        return true
    }

    private func releaseAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    /// "Pause while locked": drop the power assertion while the screen is
    /// locked (the session clock keeps running) and take it back on unlock.
    private func syncAssertionWithLockState() {
        guard isActive else { return }
        if settings?.awakePauseWhileLocked == true && Self.isScreenLocked {
            releaseAssertion()
        } else {
            acquireAssertion()
        }
    }

    // MARK: - Battery protection

    /// The battery charge when battery protection would block or end a
    /// session (protection on, running on battery, at or below the
    /// threshold); nil otherwise.
    func batteryProtectionPercent() -> Int? {
        guard settings?.awakeBatteryProtection == true,
            let battery = Self.batteryState(),
            !battery.onAC,
            battery.percent <= Self.batteryProtectionThreshold
        else { return nil }
        return battery.percent
    }

    private func enforceBatteryProtection() {
        if isActive, batteryProtectionPercent() != nil { stop() }
    }

    private static func batteryState() -> (percent: Int, onAC: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onAC = source == kIOPMACPowerKey
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                let current = desc[kIOPSCurrentCapacityKey] as? Int,
                let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return (current * 100 / max, onAC)
        }
        return nil
    }

    // MARK: - Mouse jiggle (Vorssaint-style)

    private func syncJiggleTimer() {
        guard isActive,
            !Self.isScreenLocked,
            settings?.awakeMouseJiggle == true
        else {
            stopJiggleTimer()
            return
        }

        let minutes = settings?.awakeMouseJiggleIntervalMinutes ?? 5
        let sanitized = SettingsStore.allowedJiggleIntervals.contains(minutes) ? minutes : 5
        let interval = TimeInterval(sanitized * 60)
        if jiggleTimer?.timeInterval == interval { return }

        stopJiggleTimer()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.jiggleMousePointer() }
        }
        timer.tolerance = min(10, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        jiggleTimer = timer
    }

    private func stopJiggleTimer() {
        jiggleTimer?.invalidate()
        jiggleTimer = nil
        pendingMouseReturn?.cancel()
        pendingMouseReturn = nil
    }

    /// Move the cursor 1pt, then move it back after 80ms — but only if the
    /// user hasn't moved it themselves in the meantime.
    private func jiggleMousePointer() {
        guard isActive,
            !Self.isScreenLocked,
            settings?.awakeMouseJiggle == true,
            let original = Self.currentMouseLocation(),
            let target = Self.jiggleTarget(from: original)
        else {
            syncJiggleTimer()
            return
        }

        guard Self.postMouseMove(to: target) else { return }

        pendingMouseReturn?.cancel()
        let returnMove = DispatchWorkItem { [weak self] in
            self?.pendingMouseReturn = nil
            guard let current = Self.currentMouseLocation() else { return }
            guard abs(current.x - target.x) <= 2,
                abs(current.y - target.y) <= 2
            else { return }
            _ = Self.postMouseMove(to: original)
        }
        pendingMouseReturn = returnMove
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: returnMove)
    }

    private static func currentMouseLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private static func jiggleTarget(from original: CGPoint) -> CGPoint? {
        guard let bounds = displayBounds(containing: original) else { return nil }
        let safeFrame = bounds.insetBy(dx: 2, dy: 2)
        let x = min(max(original.x, safeFrame.minX), safeFrame.maxX)
        let y = min(max(original.y, safeFrame.minY), safeFrame.maxY)

        if x + 1 <= safeFrame.maxX { return CGPoint(x: x + 1, y: y) }
        if x - 1 >= safeFrame.minX { return CGPoint(x: x - 1, y: y) }
        if y + 1 <= safeFrame.maxY { return CGPoint(x: x, y: y + 1) }
        if y - 1 >= safeFrame.minY { return CGPoint(x: x, y: y - 1) }
        return nil
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        for display in displays.prefix(Int(count)) {
            let bounds = CGDisplayBounds(display)
            if point.x >= bounds.minX, point.x <= bounds.maxX,
                point.y >= bounds.minY, point.y <= bounds.maxY
            {
                return bounds
            }
        }
        return nil
    }

    private static func postMouseMove(to point: CGPoint) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let event = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left)
        else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }

    private static var isScreenLocked: Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
