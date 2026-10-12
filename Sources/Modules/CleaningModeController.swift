import AppKit
import ApplicationServices
import SwiftUI
import os

// Event-tap lock ported from Vorssaint's CleaningModeManager
// (vorssaint/vorssaint-utils, GPL-3.0-or-later).

/// Cleaning mode: covers every display with an overlay and locks input with a
/// HID-level event tap, so wiping the keyboard (and optionally the trackpad)
/// types and clicks nothing in any app.
///
/// Exit: press Esc five times, or click the button on the overlay (only
/// possible when the trackpad is not locked). No timeout.
final class CleaningModeController: ObservableObject {
    @Published private(set) var isActive = false
    /// Consecutive Esc presses so far (0...unlockThreshold).
    @Published private(set) var unlockProgress = 0
    @Published private(set) var trackpadLocked = false

    let unlockThreshold = 5

    private static let escapeKeyCode: Int64 = 53
    /// Vorssaint's 6s window: slow deliberate presses still count, five
    /// isolated Esc hits spread across a long wipe do not.
    private static let pressWindow: TimeInterval = 6.0
    private static let gestureRaw = UInt32(NSEvent.EventType.gesture.rawValue)

    private var windows: [NSWindow] = []
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastEscTime: TimeInterval = 0

    func start(lockTrackpad: Bool) {
        guard !isActive else { return }
        // Without the tap there would be no way to stop keys, and no Esc
        // gesture to unlock — so never start without Accessibility.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            Logger.modules.notice("[FreeTheNotch] Cleaning mode needs Accessibility")
            return
        }
        trackpadLocked = lockTrackpad
        guard installTap(lockPointer: lockTrackpad) else {
            Logger.modules.error("[FreeTheNotch] Cleaning mode: failed to create event tap")
            return
        }
        unlockProgress = 0
        isActive = true

        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            panel.isFloatingPanel = true
            panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isMovable = false

            let root = CleaningOverlayView(controller: self)
            let host = FirstClickHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: screen.frame.size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            panel.orderFrontRegardless()
            windows.append(panel)
        }

        if lockTrackpad {
            NSCursor.hide()
            // Freeze the cursor even if a movement slips past the tap.
            CGAssociateMouseAndMouseCursorPosition(0)
        }
    }

    @objc func stop() {
        guard isActive else { return }
        // Leave the tap callback / button action before tearing the tap down
        // (Vorssaint schedules teardown on the next main-loop turn).
        DispatchQueue.main.async { [weak self] in
            self?.finishStop()
        }
    }

    private func finishStop() {
        guard isActive else { return }
        isActive = false
        unlockProgress = 0
        removeTap()
        if trackpadLocked {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
        }
        trackpadLocked = false
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }

    // MARK: Event tap

    private func installTap(lockPointer: Bool) -> Bool {
        var types: [UInt32] = [
            CGEventType.keyDown.rawValue,
            CGEventType.keyUp.rawValue,
            CGEventType.flagsChanged.rawValue,
            CGEventType.scrollWheel.rawValue,
            SystemDefinedEvent.type.rawValue,
            Self.gestureRaw,
        ]
        if lockPointer {
            // Beyond Vorssaint (which always lets the pointer through):
            // also swallow movement and clicks so wiping the trackpad does
            // nothing at all.
            types += [
                CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            ].map(\.rawValue)
        }
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let controller = Unmanaged<CleaningModeController>.fromOpaque(userInfo).takeUnretainedValue()
                    return controller.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
    }

    /// Runs on the main thread (the source is on the main run loop).
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that stalls; re-arm so the lock holds.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        if type == .keyDown {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            registerKeyDown(code: code, isRepeat: isRepeat)
        } else if type == .flagsChanged {
            // Modifiers sit next to Esc; a cloth on them resets the count.
            registerKeyDown(code: event.getIntegerValueField(.keyboardEventKeycode), isRepeat: false)
        }
        return nil
    }

    private func registerKeyDown(code: Int64, isRepeat: Bool) {
        guard !isRepeat else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if code == Self.escapeKeyCode {
            if unlockProgress > 0, now - lastEscTime > Self.pressWindow {
                unlockProgress = 0
            }
            lastEscTime = now
            unlockProgress += 1
            if unlockProgress >= unlockThreshold { stop() }
        } else {
            unlockProgress = 0
        }
    }
}

/// The overlay panel never becomes key; accept the first click so the exit
/// button fires immediately.
private final class FirstClickHostingView: NSHostingView<CleaningOverlayView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct CleaningOverlayView: View {
    @ObservedObject var controller: CleaningModeController

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Cleaning mode")
                    .font(.title2)
                    .foregroundStyle(.white)
                Text(
                    controller.trackpadLocked
                        ? "Keyboard and trackpad are locked. Press Esc 5 times to exit."
                        : "Keyboard is locked. Press Esc 5 times or click below to exit."
                )
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 8) {
                    ForEach(0..<controller.unlockThreshold, id: \.self) { i in
                        Circle()
                            .fill(i < controller.unlockProgress ? Color.white : Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                if !controller.trackpadLocked {
                    Button("Exit cleaning mode") { controller.stop() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
