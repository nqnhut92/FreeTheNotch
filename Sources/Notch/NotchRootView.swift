import SwiftUI

/// Root view of one display's notch panel.
///
/// One black shape morphs in width and height together. Splitting the camera
/// band from the body made the island lurch sideways and only then drop.
struct NotchRootView: View {
    let screen: NSScreen
    @ObservedObject var panelState: NotchPanelState
    /// The gear in the open island's right ear.
    let openSettings: () -> Void

    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var hud: HUDController
    @EnvironmentObject var media: MediaRemoteAdapter
    @EnvironmentObject var bluetooth: BluetoothMonitor
    @EnvironmentObject var capsLock: CapsLockManager
    @EnvironmentObject var timerStore: TimerStore
    @EnvironmentObject var batteryHUD: BatteryHUDController
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var aiActivities: AIActivityMonitor
    @EnvironmentObject var aiUsage: AIUsageMonitor

    /// Atoll shows the battery HUD over the closed island only.
    private var batteryKind: BatteryHUDKind? {
        panelState.isExpanded ? nil : batteryHUD.activeKind
    }

    private var quotaAlert: AIQuotaAlertPolicy.Alert? {
        panelState.isExpanded || batteryKind != nil || hud.isHUDVisible ? nil : aiUsage.quotaAlert
    }

    private var notchWidth: CGFloat {
        DisplayGeometry.collapsedSize(for: screen).width
    }

    /// Fill for the notch shape: solid black normally, or fading slightly
    /// from 70% height downwards when Liquid Glass is on and expanded.
    private var notchFill: LinearGradient {
        if settings.liquidGlass && panelState.isExpanded {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.7),
                    .init(color: .black.opacity(0.55), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var notchHeight: CGFloat {
        DisplayGeometry.collapsedSize(for: screen).height
    }

    private var showingLiveActivity: Bool {
        guard !hud.isHUDVisible, !panelState.isExpanded else { return false }
        return Self.widensForLiveActivity(
            settings: settings, media: media, capsLock: capsLock,
            timerStore: timerStore, aiActivities: aiActivities)
    }

    /// Whether the closed island widens to live-activity width. The one
    /// source for the shape here and the hit area in
    /// `NotchWindowController.applyHitSize`, so the two cannot drift. A
    /// Bluetooth connection does not widen it: it drops a popup below.
    static func widensForLiveActivity(
        settings: SettingsStore, media: MediaRemoteAdapter,
        capsLock: CapsLockManager, timerStore: TimerStore, aiActivities: AIActivityMonitor
    ) -> Bool {
        if settings.mediaEnabled && media.isPlaying { return true }
        if settings.capsLockEnabled && capsLock.isCapsLockActive { return true }
        return timerStore.isActive || !aiActivities.activities.isEmpty
    }

    /// Notch skin (decorations + pet) around the island. Hidden while the
    /// island is open when "Hide while the notch is open" is on.
    private var showsSkin: Bool {
        settings.notchSkin != .none && !(panelState.isExpanded && settings.skinHideWhenExpanded)
    }

    private var bodyHeight: CGFloat {
        NotchPage.bodyHeight(for: panelState.page, media: media, settings: settings, calendar: calendar)
    }

    private var shapeWidth: CGFloat {
        if panelState.isExpanded { return DisplayGeometry.expandedWidth }
        if let batteryKind {
            return batteryKind.size(notchWidth: notchWidth, notchHeight: notchHeight).width
        }
        if quotaAlert != nil {
            return DisplayGeometry.aiQuotaHUDSize(notchWidth: notchWidth, notchHeight: notchHeight).width
        }
        if hud.isHUDVisible || showingLiveActivity {
            return DisplayGeometry.liveActivityWidth(notchWidth: notchWidth)
        }
        return notchWidth
    }

    private var shapeHeight: CGFloat {
        if panelState.isExpanded { return notchHeight + bodyHeight }
        if let batteryKind {
            return batteryKind.size(notchWidth: notchWidth, notchHeight: notchHeight).height
        }
        if quotaAlert != nil {
            return DisplayGeometry.aiQuotaHUDSize(notchWidth: notchWidth, notchHeight: notchHeight).height
        }
        return notchHeight
    }

    /// Hovered or open: a skin on battery keeps moving.
    private var isSkinEngaged: Bool { panelState.isHovered || panelState.isExpanded }

    /// Width on each side of the physical camera once the island is open.
    private var earWidth: CGFloat {
        max(0, (shapeWidth - notchWidth) / 2)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if showsSkin {
                // Behind the island: the pet's tucked part hides under it.
                NotchSkinLayer(
                    part: .behindIsland, shapeSize: CGSize(width: shapeWidth, height: shapeHeight),
                    isEngaged: isSkinEngaged, isOnScreen: panelState.isOnScreen)
            }
            NotchShape(
                topRadius: 0,
                bottomRadius: panelState.isExpanded
                    ? 22 : (batteryKind?.bottomRadius ?? (quotaAlert == nil ? 16 : NotchStyle.aiQuotaHUDCornerRadius))
            )
            .fill(notchFill)
            .frame(width: shapeWidth, height: shapeHeight)

            VStack(spacing: 0) {
                if let batteryKind {
                    BatteryHUDView(
                        kind: batteryKind,
                        batteryLevel: batteryHUD.displayedLevel,
                        isLowPowerMode: batteryHUD.displayedLowPowerMode
                    )
                    .id(batteryHUD.token)
                    .frame(width: shapeWidth, height: shapeHeight)
                    .transition(.opacity)
                } else if let quotaAlert {
                    AIUsageHUDView(alert: quotaAlert, notchHeight: notchHeight)
                        .frame(width: shapeWidth, height: shapeHeight)
                        .transition(.opacity)
                } else {
                    topBand
                        .frame(width: shapeWidth, height: notchHeight)
                }
                if panelState.isExpanded {
                    ExpandedPanelView(panelState: panelState)
                        .frame(width: DisplayGeometry.expandedWidth, height: bodyHeight)
                }
            }
            .frame(width: shapeWidth, height: shapeHeight, alignment: .top)
            .clipped()

            if showsSkin {
                NotchSkinLayer(
                    part: .aboveIsland, shapeSize: CGSize(width: shapeWidth, height: shapeHeight),
                    isEngaged: isSkinEngaged, isOnScreen: panelState.isOnScreen)
            }

            // Bluetooth connection notification: drops below the notch shape.
            // Separate layer (not clipped with the panel content).
            if settings.bluetoothPopupEnabled, let device = bluetooth.liveDevice,
                !panelState.isExpanded, batteryKind == nil, quotaAlert == nil
            {
                BluetoothPopupView(device: device)
                    .offset(y: notchHeight + 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(NotchStyle.morph, value: panelState.isExpanded)
        .animation(NotchStyle.morph, value: panelState.page)
        .animation(NotchStyle.morph, value: media.upNext)
        .animation(NotchStyle.morph, value: bodyHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: bluetooth.liveDevice?.id)
        .animation(NotchStyle.morph, value: hud.isHUDVisible)
        .animation(NotchStyle.morph, value: media.isPlaying)
        .animation(.easeInOut(duration: 0.25), value: showsSkin)
        .animation(.easeInOut(duration: 0.25), value: settings.notchSkin)
        .animation(NotchStyle.morph, value: timerStore.isActive)
        .animation(NotchStyle.morph, value: aiActivities.activities.isEmpty)
        .animation(NotchStyle.morph, value: aiUsage.quotaAlert)
        .animation(NotchStyle.morph, value: batteryHUD.activeKind)
        .animation(NotchStyle.morph, value: batteryHUD.token)
    }

    /// The menu-bar band. Icons sit in the ears, level with the menu bar.
    /// The center is left empty so it stays over the camera.
    @ViewBuilder
    private var topBand: some View {
        if panelState.isExpanded {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach(settings.visibleNotchTabs) { item in
                        Button {
                            panelState.page = item
                        } label: {
                            NotchPageIcon(
                                page: item, size: 14,
                                weight: panelState.page == item ? .semibold : .regular
                            )
                            .foregroundStyle(panelState.page == item ? Color.white : Color.white.opacity(0.4))
                            .frame(width: 28, height: notchHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(item.title)
                    }
                }
                .padding(.leading, 14)
                .frame(width: earWidth, alignment: .leading)

                Color.clear.frame(width: notchWidth, height: notchHeight)

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: notchHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                .padding(.trailing, 14)
                .frame(width: earWidth, alignment: .trailing)
            }
        } else {
            CollapsedNotchView(screen: screen)
        }
    }
}
