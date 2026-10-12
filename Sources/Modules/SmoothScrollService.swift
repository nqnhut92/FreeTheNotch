// Adapted from Vorssaint: Services/SmoothScrollService.swift and
// Services/MouseExceptions/MouseAppExceptions.swift.
// Copyright (C) 2026 Vorssaint. SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import Combine
import QuartzCore
import os

/// Replays mouse-wheel distance as eased pixel events. Touch gestures pass through.
@MainActor
final class SmoothScrollService: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var hasAccessibility = false

    private static let ownProcessID = Int64(getpid())
    private static let permissionRefreshInterval: Duration = .seconds(1)
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var displayLink: CADisplayLink?
    private var frameTask: Task<Void, Never>?
    private var schedulerScreenNumber: NSNumber?
    private var permissionTask: Task<Void, Never>?
    private var targetTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var engine = SmoothScrollSupport.Engine()
    private var lastFrameTimestamp: TimeInterval?
    private var lastGesturePhaseTimestamp: UInt64?
    private var carryVertical: Double = 0
    private var carryHorizontal: Double = 0
    private var currentFlags: CGEventFlags = []
    private var glideFromContinuous = false
    private var enabled = false
    private var isCleaning = false
    private var sessionIsActive = true
    private var isLocked = false
    private var isSleeping = false
    private var step = SmoothScrollSupport.defaultStep
    private var response = SmoothScrollSupport.defaultResponse
    private var coast = SmoothScrollSupport.defaultCoast
    private var exclusions = Set<String>()
    private var excludedProcessIDs = Set<Int64>()
    private var cachedTarget: MouseScrollTarget?

    func configure(with settings: SettingsStore, cleaning: CleaningModeController) {
        guard cancellables.isEmpty else { return }
        settings.$smoothScrollStep.sink { [weak self] in
            self?.step = SmoothScrollSupport.sanitizedStep($0)
        }.store(in: &cancellables)
        settings.$smoothScrollResponse.sink { [weak self] in
            self?.response = SmoothScrollSupport.sanitizedResponse($0)
        }.store(in: &cancellables)
        settings.$smoothScrollCoast.sink { [weak self] in
            self?.coast = SmoothScrollSupport.sanitizedCoast($0)
        }.store(in: &cancellables)
        settings.$smoothScrollExcludedApps.sink { [weak self] values in
            guard let self else { return }
            self.exclusions = Set(SmoothScrollSupport.sanitizedExclusions(values))
            self.cachedTarget = nil
            self.stopGlide()
            self.refreshExcludedProcesses()
        }.store(in: &cancellables)
        cleaning.$isActive.sink { [weak self] active in
            self?.isCleaning = active
            self?.syncTap()
        }.store(in: &cancellables)
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            sessionIsActive = session[kCGSessionOnConsoleKey as String] as? Bool ?? true
            isLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        }
        installObservers()
        settings.$smoothScrollEnabled.sink { [weak self] enabled in
            guard let self else { return }
            self.enabled = enabled
            self.permissionTask?.cancel()
            self.permissionTask = nil
            self.refreshPermission()
            guard enabled else { return }
            self.permissionTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: Self.permissionRefreshInterval) } catch { return }
                    self?.refreshPermission()
                }
            }
        }.store(in: &cancellables)
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
        syncTap()
        if !hasAccessibility { SystemSettings.open(.accessibility) }
    }

    func shutdown() {
        enabled = false
        permissionTask?.cancel()
        permissionTask = nil
        targetTask?.cancel()
        targetTask = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        cancellables.removeAll()
        stopTap()
    }

    private func refreshPermission() {
        hasAccessibility = AXIsProcessTrusted()
        refreshExcludedProcesses()
        syncTap()
    }

    private func refreshExcludedProcesses() {
        guard !exclusions.isEmpty else {
            excludedProcessIDs.removeAll()
            return
        }
        excludedProcessIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap { app in
                guard let identifier = app.bundleIdentifier, exclusions.contains(identifier) else { return nil }
                return Int64(app.processIdentifier)
            })
    }

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionIsActive = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionIsActive = true }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.isSleeping = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.isSleeping = false }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.isLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.isLocked = false }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.stopGlide() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) {
            $0.cachedTarget = nil
            $0.stopGlide()
        }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        update: @escaping @MainActor (SmoothScrollService) -> Void
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.syncTap()
            }
        }
        observers.append((center, observer))
    }

    private func syncTap() {
        guard enabled, hasAccessibility, sessionIsActive, !isLocked, !isSleeping, !isCleaning else {
            stopTap()
            return
        }
        guard tap == nil else { return }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    return MainActor.assumeIsolated {
                        Unmanaged<SmoothScrollService>.fromOpaque(context).takeUnretainedValue()
                            .process(type: type, event: event)
                    }
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            Logger.modules.error("[FreeTheNotch] Smooth scrolling: failed to create event tap")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func stopTap() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        stopGlide()
        cachedTarget = nil
        lastGesturePhaseTimestamp = nil
        isRunning = false
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stopGlide()
            // Trust and lifecycle state are refreshed outside the latency-critical callback.
            if enabled, hasAccessibility, sessionIsActive, !isLocked, !isSleeping, !isCleaning, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard event.getIntegerValueField(.eventSourceUserData) != SmoothScrollSupport.syntheticTag,
            sourceProcessID != Self.ownProcessID
        else { return Unmanaged.passUnretained(event) }
        let traits = SmoothScrollSupport.WheelTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount))
        let timestamp = event.timestamp
        let elapsed = lastGesturePhaseTimestamp.flatMap { previous in
            timestamp >= previous ? Double(timestamp - previous) / 1_000_000_000 : nil
        }
        if traits.momentumPhase != 0 || traits.scrollPhase != 0 { lastGesturePhaseTimestamp = timestamp }
        guard SmoothScrollSupport.isMouseWheel(traits, secondsSinceLastGesturePhase: elapsed),
            !event.flags.contains(.maskControl),
            !isExcluded(at: event.location, sourceProcessID: sourceProcessID)
        else {
            stopGlide()
            return Unmanaged.passUnretained(event)
        }
        let vertical: Double
        let horizontal: Double
        if traits.isContinuous {
            vertical = SmoothScrollSupport.continuousDistance(
                fixedPointDelta: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                pointDelta: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)), step: Double(step))
            horizontal = SmoothScrollSupport.continuousDistance(
                fixedPointDelta: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                pointDelta: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)), step: Double(step))
        } else {
            let axes = SmoothScrollSupport.axes(
                vertical: SmoothScrollSupport.ticks(
                    line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                    fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)),
                horizontal: SmoothScrollSupport.ticks(
                    line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                    fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)),
                shiftPressed: event.flags.contains(.maskShift))
            vertical = axes.vertical * Double(step)
            horizontal = axes.horizontal * Double(step)
        }
        guard vertical != 0 || horizontal != 0 else { return Unmanaged.passUnretained(event) }
        if currentFlags != event.flags || glideFromContinuous != traits.isContinuous { stopGlide() }
        carryVertical = SmoothScrollSupport.carry(carryVertical, continuing: vertical)
        carryHorizontal = SmoothScrollSupport.carry(carryHorizontal, continuing: horizontal)
        engine.add(vertical: vertical, horizontal: horizontal)
        currentFlags = event.flags
        glideFromContinuous = traits.isContinuous
        startGlideIfNeeded(at: event.location)
        return nil
    }

    /// Until a fresh pointer target is known, preserve the raw event rather than guessing its app.
    private func isExcluded(at point: CGPoint, sourceProcessID: Int64) -> Bool {
        guard !exclusions.isEmpty else { return false }
        if excludedProcessIDs.contains(sourceProcessID) { return true }
        let now = ProcessInfo.processInfo.systemUptime
        if let cachedTarget, cachedTarget.contains(point, now: now) {
            return cachedTarget.bundleIdentifier.map(exclusions.contains) ?? true
        }
        let staleIdentity = cachedTarget.flatMap { target in
            target.namesWindow(at: point) ? target.bundleIdentifier : nil
        }
        if targetTask == nil {
            targetTask = Task { [weak self] in
                let window = await Task.detached(priority: .userInitiated) {
                    Self.pointerWindow(at: point)
                }.value
                guard let self else { return }
                self.targetTask = nil
                guard !Task.isCancelled, self.isRunning else { return }
                let app =
                    window.flatMap { NSRunningApplication(processIdentifier: $0.processID) }
                    ?? NSWorkspace.shared.frontmostApplication
                self.cachedTarget = MouseScrollTarget(
                    bundleIdentifier: app?.bundleIdentifier,
                    region: window?.frame, point: point, resolvedAt: ProcessInfo.processInfo.systemUptime)
                if app?.bundleIdentifier.map(self.exclusions.contains) ?? true { self.stopGlide() }
            }
        }
        return staleIdentity.map(exclusions.contains) ?? true
    }

    private struct PointerWindow: Sendable {
        let processID: Int32
        let frame: CGRect
    }

    nonisolated private static func pointerWindow(at point: CGPoint) -> PointerWindow? {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for window in windows {
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.contains(point),
                let processID = window[kCGWindowOwnerPID as String] as? Int32,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { continue }
            return PointerWindow(processID: processID, frame: frame)
        }
        return nil
    }

    private func startGlideIfNeeded(at point: CGPoint) {
        // CGEvent coordinates start at the main display's upper left; NSScreen uses bottom-left coordinates.
        let appKitPoint = NSPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) })
        let screenNumber = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if displayLink != nil, schedulerScreenNumber == screenNumber { return }
        if frameTask != nil, screen == nil { return }
        stopFrameScheduler()
        schedulerScreenNumber = screenNumber
        if let screen {
            let link = screen.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
            displayLink = link
            link.add(to: .main, forMode: .common)
        } else {
            frameTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.emitFrame(
                        at: ProcessInfo.processInfo.systemUptime,
                        firstElapsed: SmoothScrollSupport.frameInterval)
                    do { try await Task.sleep(for: .seconds(SmoothScrollSupport.frameInterval)) } catch { return }
                }
            }
        }
    }

    @objc private func displayLinkDidFire(_ sender: CADisplayLink) {
        guard sender === displayLink else { return }
        emitFrame(
            at: sender.timestamp,
            firstElapsed: sender.duration > 0 ? sender.duration : SmoothScrollSupport.frameInterval)
    }

    private func emitFrame(at timestamp: TimeInterval, firstElapsed: TimeInterval) {
        if !exclusions.isEmpty, let point = CGEvent(source: nil)?.location,
            isExcluded(at: point, sourceProcessID: 0)
        {
            stopGlide()
            return
        }
        let elapsed = lastFrameTimestamp.map { timestamp - $0 } ?? firstElapsed
        lastFrameTimestamp = timestamp
        let frame = engine.advance(elapsed: elapsed, response: response, coast: coast)
        let vertical =
            frame.finished
            ? (pixels: SmoothScrollSupport.finalPixels(frame.vertical, carry: carryVertical), carry: 0)
            : SmoothScrollSupport.wholePixels(frame.vertical, carry: carryVertical)
        let horizontal =
            frame.finished
            ? (pixels: SmoothScrollSupport.finalPixels(frame.horizontal, carry: carryHorizontal), carry: 0)
            : SmoothScrollSupport.wholePixels(frame.horizontal, carry: carryHorizontal)
        carryVertical = vertical.carry
        carryHorizontal = horizontal.carry
        if vertical.pixels != 0 || horizontal.pixels != 0,
            let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: Self.pixelField(vertical.pixels), wheel2: Self.pixelField(horizontal.pixels),
                wheel3: 0)
        {
            event.setIntegerValueField(.eventSourceUserData, value: SmoothScrollSupport.syntheticTag)
            event.flags = currentFlags
            event.post(tap: .cghidEventTap)
        }
        if frame.finished { stopGlide() }
    }

    private func stopGlide() {
        stopFrameScheduler()
        engine.reset()
        carryVertical = 0
        carryHorizontal = 0
    }

    private func stopFrameScheduler() {
        displayLink?.invalidate()
        displayLink = nil
        frameTask?.cancel()
        frameTask = nil
        schedulerScreenNumber = nil
        lastFrameTimestamp = nil
    }

    private static func pixelField(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        return Int32(clamping: Int(min(max(value, -1_000_000), 1_000_000)))
    }
}
