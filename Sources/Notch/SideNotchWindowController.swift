// Panel placement adapted from CodeNotch (github.com/vinzdg/codenotch), MIT:
// Sources/Notch/NotchPanel.swift (borderless non-activating panel at
// `.statusBar`) and Sources/Notch/NotchWindowController.swift (`relocate`:
// flush to the edge, centred along it). Glyph hosting adapted from DuoBar
// (github.com/Mikeli7666/DuoBar), MIT: MenuBar/MenuBarController.swift
// (SwiftUI glyph in a click-through hosting view).

// Panel presentation mirrors Vorssaint (GPL-3.0-or-later):
// Sources/Vorssaint/App/AppDelegate.swift (`showPopover`).

import AppKit
import Combine
import SwiftUI

/// Side Notch: a black pill welded to the left or right edge of each target
/// screen, vertically centred, always open. Cells, in the order set in
/// Settings → Side Notch → Cells: DuoGlyph (click → one popover with Wi-Fi |
/// Battery | Sound tabs), Bluetooth and five direct system sections. Right clicks do nothing. Exists only
/// while Settings → Side Notch → Show Side Notch is on.
@MainActor
final class SideNotchWindowController: NSObject, NSPopoverDelegate {
    private typealias PopoverKind = SideNotchPopoverKind

    private weak var services: AppDelegate?
    private var panels: [NSPanel] = []
    /// Popovers that are open or closing. A closed popover is dropped with
    /// its content, so nothing hidden keeps observing the monitors.
    private var popovers: [PopoverKind: NSPopover] = [:]
    private var shownKind: PopoverKind?
    private weak var popoverAnchor: NSView?
    private var lastClosed: (kind: PopoverKind, at: Date)?
    private var isEnabled = false
    private var isHiddenWhileLocked = false
    /// Edge the panels are on now (the setting, or the Dock rule's override).
    private var currentEdge: SideNotchEdge = .right
    private let wifi = WiFiMonitor()
    private let volume = OutputVolumeMonitor()
    private let energy = EnergyModeController()
    private let duoState = DuoGlyphPopoverState()
    private let panelPlacement = PanelPlacement()
    private let panelMemory = PanelMemory()
    /// `.transient` alone does not close a popover of an agent app that
    /// was never activated, nor on clicks in our own other windows.
    private let outsideClicks = OutsideClickMonitor()
    private var cancellables = Set<AnyCancellable>()

    init(services: AppDelegate) {
        self.services = services
        super.init()
        let settings = services.settings
        settings.$sideNotchEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in self?.setEnabled(enabled) }
            .store(in: &cancellables)
        Publishers.CombineLatest4(
            settings.$displayScopeRaw.removeDuplicates(),
            settings.$sideNotchZoom.removeDuplicates(),
            settings.$sideNotchEdgeRaw.removeDuplicates(),
            DockSide.shared.$side.removeDuplicates()
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.rebuildPanels() }
        .store(in: &cancellables)
        settings.$sideNotchOrderRaw
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildPanels() }
            .store(in: &cancellables)
        // The full panel's tab decides what it samples.
        panelMemory.$tab
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSampling() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in self?.closePopovers() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DockSide.shared.reload()
                self?.rebuildPanels()
            }
            .store(in: &cancellables)
    }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            wifi.start()
            volume.start()
            DockSide.shared.start()
        } else {
            wifi.stop()
            volume.stop()
            DockSide.shared.stop()
        }
        rebuildPanels()
    }

    /// Hidden while the screen is locked, like the notch.
    func setHidden(_ hidden: Bool) {
        isHiddenWhileLocked = hidden
        if hidden { closePopovers() }
        for panel in panels {
            if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        }
    }

    // MARK: Panels

    private var targetScreens: [NSScreen] {
        // Same screens as the notch (Settings → General → Displays).
        DisplayGeometry.targetScreens(for: services?.settings.displayScope ?? .mainOnly)
    }

    private func rebuildPanels() {
        closePopovers()
        for panel in panels { panel.orderOut(nil) }
        panels = []
        guard isEnabled, let services else { return }
        currentEdge = DockSide.shared.effectiveEdge(
            for: SideNotchEdge(rawValue: services.settings.sideNotchEdgeRaw) ?? .right)
        for screen in targetScreens {
            let requestedZoom = CGFloat(services.settings.sideNotchZoom) * SideNotchLayout.baseScale
            let zoom = min(requestedZoom, screen.visibleFrame.height / SideNotchLayout.size.height)
            let panel = makePanel(on: screen, zoom: zoom, edge: currentEdge, services: services)
            if !isHiddenWhileLocked { panel.orderFrontRegardless() }
            panels.append(panel)
        }
    }

    private func makePanel(
        on screen: NSScreen, zoom: CGFloat, edge: SideNotchEdge,
        services: AppDelegate
    ) -> NSPanel {
        // Sized to the shape's bounding box, flares included. The transparent
        // flare corners stay inside the window: a small dead zone, accepted
        // instead of CodeNotch's per-mouse-move ignoresMouseEvents toggling.
        let size = SideNotchLayout.windowSize(zoom: zoom)
        let frame = NSRect(
            x: edge == .right ? screen.frame.maxX - size.width : screen.frame.minX,
            y: (screen.frame.midY - size.height / 2).rounded(),
            width: size.width, height: size.height)

        let panel = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        // isFloatingPanel resets the level, so it goes first.
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)

        let click = SideNotchClickView(frame: NSRect(origin: .zero, size: size))
        // One anchor per cell, so each popover points at its own cell.
        // AppKit's y runs up: cell 0 is at the top.
        let cell = SideNotchLayout.ringDiameter * zoom
        for index in 0..<SideNotchLayout.cellCount {
            let centerY = size.height - SideNotchLayout.cellCenterY(index) * zoom
            let anchor = NSView(
                frame: NSRect(
                    x: (size.width - cell) / 2, y: centerY - cell / 2,
                    width: cell, height: cell))
            anchor.toolTip = services.settings.sideNotchOrder[index].title
            click.addSubview(anchor)
            click.cellAnchors.append(anchor)
        }
        // One click per cell; right clicks do nothing.
        let cells = services.settings.sideNotchOrder
        click.onClick = { [weak self] index, anchor in
            guard let kind = PopoverKind(rawValue: cells[index].rawValue) else { return }
            self?.togglePopover(kind, from: anchor)
        }

        let host = PassthroughHostingView(
            rootView: SideNotchView(
                battery: services.batteryHUD, wifi: wifi, volume: volume, bluetooth: services.bluetooth,
                edge: edge, zoom: zoom, canvasSize: size, cells: cells))
        host.frame = click.bounds
        host.autoresizingMask = [.width, .height]
        click.addSubview(host)

        panel.contentView = click
        return panel
    }

    // MARK: Popovers

    /// Full panel fallback when the Side Notch is disabled.
    func toggleMenuBarPanel(from anchor: NSView) {
        guard !isEnabled, !isHiddenWhileLocked else { return }
        togglePopover(.panel, from: anchor)
    }

    private func togglePopover(_ kind: PopoverKind, from anchor: NSView) {
        if let shownKind, let shown = popovers[shownKind], shown.isShown {
            let same = shownKind == kind && popoverAnchor === anchor
            shown.close()
            if same { return }
        } else if let lastClosed, lastClosed.kind == kind, popoverAnchor === anchor,
            Date().timeIntervalSince(lastClosed.at) < 0.25
        {
            // This click already closed the transient popover on mouse-down;
            // don't reopen it.
            return
        }
        // Always a new popover: a reused popover's window reaches the screen
        // only after the open animation, so key would stay on the notch's
        // `KeyablePanel` and the cup panel would show the inactive look
        // (grey switches, pale glass); a new popover's window does not.
        guard let popover = makePopover(kind) else { return }
        popovers[kind] = popover
        shownKind = kind
        popoverAnchor = anchor
        if kind.tab != nil || kind == .panel {
            // Its height is capped by the screen it opens on.
            panelPlacement.screen = anchor.window?.screen
        }
        // Vorssaint's order (AppDelegate.showPopover): show, make key, then
        // activate. Away from the bezel.
        popover.show(
            relativeTo: anchor.bounds, of: anchor,
            preferredEdge: kind == .panel ? .minY : (currentEdge == .right ? .minX : .maxX))
        let popoverWindow = popover.contentViewController?.view.window
        popoverWindow?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        outsideClicks.start(
            isInside: { [weak anchor] _, window in
                guard let window else { return false }
                // The anchor panel's own click toggles; child windows
                // (field editors, menus) belong to the popover. A click in
                // Settings closes it too, at the owner's request; Vorssaint
                // keeps its panel open beside Settings unless the two overlap.
                return window === popoverWindow || window.parent === popoverWindow
                    || window === anchor?.window
            },
            onOutside: { [weak self] in self?.closePopovers() })
        switch kind {
        case .duo: refresh(duoState.tab)
        case .bluetooth: services?.bluetooth.refresh()
        default: break
        }
        updateSampling()
    }

    /// Samples what the open popovers show, and nothing for closed ones
    /// (Vorssaint's `releasePanelResources()` in `popoverDidClose`).
    private func updateSampling() {
        guard let services else { return }
        let needs = PopoverKind.samplingNeeds(
            shown: popovers.filter { $0.value.isShown }.keys, panelTab: panelMemory.tab)
        services.processes.setSampling(processes: needs.contains(.processes), network: needs.contains(.network))
        services.system.setTemperaturesNeeded(needs.contains(.temperatures), by: .panel)
        services.disks.setVolumeSampling(needs.contains(.disks))
    }

    /// Fresh data for the DuoGlyph tab about to show.
    private func refresh(_ tab: DuoGlyphTab) {
        switch tab {
        case .wifi: wifi.popoverOpened()
        case .battery: energy.refresh()
        case .sound: AudioRouteManager.shared.refreshDevices()
        }
    }

    private func closePopovers() {
        outsideClicks.stop()
        for popover in popovers.values where popover.isShown { popover.close() }
    }

    private func makePopover(_ kind: PopoverKind) -> NSPopover? {
        guard let services else { return nil }
        let popover = NSPopover()
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let close: () -> Void = { [weak self] in self?.popovers[kind]?.performClose(nil) }
        let content: AnyView
        switch kind {
        case .duo:
            content = AnyView(
                DuoGlyphCombinedPopover(
                    state: duoState, wifi: wifi, battery: services.batteryHUD, system: services.system,
                    processes: services.processes, energy: energy, volume: volume, onClose: close,
                    onTabChange: { [weak self] tab in self?.refresh(tab) }))
        case .bluetooth:
            content = AnyView(DuoBluetoothPopover(bluetooth: services.bluetooth, onClose: close))
        default:
            content = AnyView(
                MenuBarPanelView(
                    fixedTab: kind.tab,
                    onDismiss: close,
                    onOpenSettings: { [weak services] in services?.showSettings() }
                )
                .environmentObject(services.settings)
                .environmentObject(services.system)
                .environmentObject(services.disks)
                .environmentObject(services.processes)
                .environmentObject(services.speedTest)
                .environmentObject(services.keepAwake)
                .environmentObject(services.cleaning)
                .environmentObject(panelPlacement)
                .environmentObject(panelMemory))
            // Closed by us (outside clicks, including the Settings window).
            // The panel's surface reaches the arrow.
            popover.behavior = .applicationDefined
            if #available(macOS 26.0, *) { popover.hasFullSizeContent = true }
        }
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        return popover
    }

    /// Safety net: key the popover once it is up if `makeKey()` in
    /// `togglePopover` did not take.
    func popoverDidShow(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
            let window = popover.contentViewController?.view.window, !window.isKeyWindow
        else { return }
        window.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }
        // Tear the SwiftUI tree down: kept, it would re-render on every
        // monitor update while hidden, and its onDisappear would never run.
        popover.contentViewController = nil
        if let kind = popovers.first(where: { $0.value === popover })?.key {
            popovers[kind] = nil
            lastClosed = (kind, Date())
            if kind == .panel, services?.settings.rememberLastTab == false {
                panelMemory.tab = MenuBarPanelTab.allCases[0]
            }
        }
        if popovers.values.allSatisfy({ !$0.isShown }) { outsideClicks.stop() }
        updateSampling()
    }
}

/// Takes the click for the whole panel, including the first click while the
/// app is inactive, and routes it to the cell under the pointer. Clicks
/// between cells or on the flares do nothing.
private final class SideNotchClickView: NSView {
    var cellAnchors: [NSView] = []
    var onClick: ((Int, NSView) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func cell(at event: NSEvent) -> (Int, NSView)? {
        let point = convert(event.locationInWindow, from: nil)
        // Generous hit area: the cell's full depth and half the gap either side.
        for (index, anchor) in cellAnchors.enumerated() {
            let gap = anchor.frame.height * SideNotchLayout.cellSpacing / SideNotchLayout.ringDiameter / 2
            let area = NSRect(
                x: 0, y: anchor.frame.minY - gap, width: bounds.width,
                height: anchor.frame.height + 2 * gap)
            if area.contains(point) { return (index, anchor) }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        // Control-click is a right click in macOS: nothing, like right click.
        guard !event.modifierFlags.contains(.control), let (index, anchor) = cell(at: event) else { return }
        onClick?(index, anchor)
    }

    /// Swallowed so it does not reach the window underneath.
    override func rightMouseDown(with event: NSEvent) {}
}

/// Draws the SwiftUI content but lets every click reach the view underneath.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
