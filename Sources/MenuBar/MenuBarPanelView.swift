import SwiftUI

/// Where the panel opens. Its height is capped by that screen, which
/// SideNotchWindowController sets before each show.
final class PanelPlacement: ObservableObject {
    @Published var screen: NSScreen?
}

/// What the panel keeps between opens. Its view is dropped on close, so
/// nothing in it keeps observing the monitors; this outlives it.
final class PanelMemory: ObservableObject {
    /// The full panel's selected tab.
    @Published var tab: MenuBarPanelTab = MenuBarPanelTab.allCases[0]
    /// Last measured content height per tab, so a rebuilt panel opens at its
    /// final size. Not published: it is read once per open.
    var contentHeights: [MenuBarPanelTab: CGFloat] = [:]
}

// Menu-bar monitor panel. Tab bar + card design follows Vorssaint's panel
// (vorssaint/vorssaint-utils, GPL-3.0-or-later); the System/Network/Disks/
// Power tabs are faithful ports of their sections.
struct MenuBarPanelView: View {
    var fixedTab: PanelTab? = nil
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var disks: DiskMonitor
    @EnvironmentObject var processes: ProcessMonitor
    @EnvironmentObject var speedTest: SpeedTest
    @EnvironmentObject var keepAwake: KeepAwakeController

    @EnvironmentObject var cleaning: CleaningModeController
    @EnvironmentObject var placement: PanelPlacement
    @EnvironmentObject var memory: PanelMemory

    /// On the popover's dark system glass (macOS 26+, Reduce Transparency
    /// off), like the Side Notch's other popovers: white text levels.
    private var usesGlassPanel: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    @Environment(\.colorScheme) private var colorScheme
    typealias PanelTab = MenuBarPanelTab

    private var selectedTab: PanelTab { fixedTab ?? memory.tab }
    /// Natural height of the scrolled content, reported by OverlayScrollView.
    @State private var contentHeight: CGFloat = 0
    @State private var measuredTab: PanelTab?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if fixedTab == nil { header }
            if fixedTab == nil { tabBar }
            OverlayScrollView(measuredHeight: $contentHeight) {
                VStack(alignment: .leading, spacing: 12) {
                    PanelSection(title: selectedTab.title) {
                        tabContent
                    }
                }
                .frame(width: 308)
                // The scroll content lives in its own NSHostingView, which does
                // not inherit the environment: apply the glass text levels
                // again.
                .glassPanelText(usesGlassPanel)
            }
            .frame(width: 308, height: scrollHeight)
            if fixedTab == nil { footer }
        }
        .padding(12)
        .frame(width: 332, height: panelHeight)
        // White text levels on the dark glass.
        .glassPanelText(usesGlassPanel)
        .background(PanelGlassSurface())
        .onChange(of: selectedTab) { _, _ in measuredTab = nil }
        .onChange(of: contentHeight) { _, height in
            measuredTab = selectedTab
            memory.contentHeights[selectedTab] = height
        }
    }

    // MARK: - Height (Vorssaint's navigable panel sizing)

    /// Header, tab bar, footer, paddings and spacings around the scroll area.
    private var chromeHeight: CGFloat { fixedTab == nil ? 180 : 42 }

    /// Never taller than the usable screen: the popover window is the panel
    /// plus 26pt for the arrow, and a too-tall window makes AppKit open the
    /// popover beside the icon instead of under it.
    private var maxHeight: CGFloat {
        let screen = placement.screen ?? NSScreen.screens.first
        return max(360, (screen?.visibleFrame.height ?? 760) - 28)
    }

    /// Before the first measurement of a tab, a per-tab estimate.
    private var estimatedContentHeight: CGFloat {
        switch selectedTab {
        case .keepAwake: return 250
        case .system: return 460
        case .network: return 190
        case .disk: return 360
        case .power: return 170
        case .tools: return 120
        }
    }

    private var scrollHeight: CGFloat {
        let measured =
            (measuredTab == selectedTab && contentHeight > 0)
            ? contentHeight : memory.contentHeights[selectedTab] ?? estimatedContentHeight
        return min(measured, max(80, maxHeight - chromeHeight))
    }

    private var panelHeight: CGFloat {
        min(maxHeight, max(220, scrollHeight + chromeHeight))
    }

    // MARK: - Header

    /// Vorssaint's MenuPanelHeader: just the brand mark, centered. Ours is
    /// the app's coffee cup in the app icon's orange gradient.
    private var header: some View {
        Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.78, blue: 0.52),
                        Color(red: 1.0, green: 0.60, blue: 0.30),
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .frame(height: 28)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                let isActive = selectedTab == tab
                Button {
                    memory.tab = tab
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.panelSecondary))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isActive
                                ? Color.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.13)
                                : Color.clear)
                )
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PanelSurface.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .keepAwake:
            PanelKeepAwakeCard()
        case .system:
            PanelSystemSection()
        case .network:
            PanelNetworkSection()
        case .disk:
            PanelDiskSection()
        case .power:
            PanelPowerSection()
        case .tools:
            PanelUtilitiesCard(onDismiss: onDismiss)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton("Settings", systemImage: "gearshape") {
                onDismiss()
                onOpenSettings()
            }
            footerButton("Quit", systemImage: "power", destructive: true) {
                NSApp.terminate(nil)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .padding(.top, 4)
    }

    private func footerButton(
        _ title: String, systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        // Red text washes out on Liquid Glass, so there the button gets a red fill instead.
        let glassDestructive = destructive && usesGlassPanel
        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.78)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(glassDestructive ? Color.red.opacity(0.78) : PanelSurface.cardFill(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            glassDestructive ? Color.red.opacity(0.9) : PanelSurface.border(for: colorScheme),
                            lineWidth: 0.8)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            glassDestructive
                ? AnyShapeStyle(Color.white)
                : destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.panelSecondary))
    }
}

// MARK: - Surface

/// Vorssaint's PanelGlassSurface. On macOS 26+ the popover hosts full-size
/// content, so a plain rectangle bleeds into the arrow and the popover clips
/// and outlines it. Before that, the panel is a rounded card inside the balloon.
/// With Reduce Transparency off, this surface stays clear so the popover's own
/// dark system glass shows (the Side Notch window is darkAqua), the same as
/// the Side Notch's Wi-Fi and Bluetooth popovers.
private struct PanelGlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(macOS 26.0, *) {
            Group {
                if !reduceTransparency {
                    Color.clear
                } else {
                    Rectangle()
                        .fill(.regularMaterial)
                        .overlay(Rectangle().fill(PanelSurface.baseFill(for: colorScheme)))
                }
            }
            .ignoresSafeArea()
        } else {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            shape
                .fill(.regularMaterial)
                .overlay(shape.fill(PanelSurface.baseFill(for: colorScheme)))
                .overlay(shape.strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8))
        }
    }
}
