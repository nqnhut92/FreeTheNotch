import SwiftUI

// MARK: - Settings sections

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, skins, liveActivities, clipboard, aiUsage, hud, sideNotch, utilities, lockScreen, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .skins: return "Skins"
        case .liveActivities: return "Live Activities"
        case .clipboard: return "Clipboard"
        case .aiUsage: return "AI Usage"
        case .hud: return "HUD"
        case .sideNotch: return "Side Notch"
        case .utilities: return "Utilities"
        case .lockScreen: return "Lock Screen"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "paintbrush.fill"
        case .skins: return "sparkles"
        case .liveActivities: return "bolt.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .aiUsage: return "chart.bar.xaxis"
        case .hud: return "rectangle.on.rectangle.fill"
        case .sideNotch: return "rectangle.righthalf.inset.filled"
        case .utilities: return "wrench.fill"
        case .lockScreen: return "lock.fill"
        case .about: return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .blue
        case .skins: return .pink
        case .liveActivities: return .orange
        case .clipboard: return .purple
        case .aiUsage: return .orange
        case .hud: return .teal
        case .sideNotch: return .green
        case .utilities: return .brown
        case .lockScreen: return .indigo
        case .about: return .cyan
        }
    }
}

// MARK: - Sidebar

/// A sidebar entry: the section's coloured icon and title, highlighted
/// when selected.
struct SettingsSidebarButton: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(section.iconColor.gradient)
                        .frame(width: 26, height: 26)
                    if section == .sideNotch {
                        // Drawn, not a stock symbol.
                        SideNotchSidebarIcon()
                    } else {
                        Image(systemName: section.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                Text(section.title)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings window

/// iOS-style grouped settings: a sidebar of sections, each a page of cards.
/// The pages are in the SettingsView+*.swift extensions.
struct SettingsView: View {
    /// The window's content size (AppDelegate.showSettings).
    static let size = CGSize(width: 700, height: 660)
    private static let sidebarWidth: CGFloat = 200

    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var aiUsage: AIUsageMonitor
    @EnvironmentObject var aiActivities: AIActivityMonitor
    @ObservedObject var dockSide = DockSide.shared
    @State var selection: SettingsSection = .general
    /// The row being dragged in Appearance → Notch Tabs and Side Notch → Cells.
    @State var draggingPage: NotchPage?
    @State var draggingCell: SideNotchCell?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(SettingsSection.allCases.filter { $0 != .about }) { section in
                sidebarButton(section)
            }
            Spacer()
            Divider()
                .padding(.vertical, 6)
            // About pinned to the bottom.
            sidebarButton(.about)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(width: Self.sidebarWidth)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private func sidebarButton(_ section: SettingsSection) -> some View {
        SettingsSidebarButton(section: section, isSelected: selection == section) {
            withAnimation(.easeInOut(duration: 0.15)) {
                selection = section
            }
        }
    }

    /// iOS-style grouped cards on grey.
    private var content: some View {
        VStack(spacing: 0) {
            if selection == .lockScreen {
                // Pinned above the scrolling switches:
                // flip one and watch the preview without scrolling back.
                VStack(alignment: .leading, spacing: 0) {
                    pageTitle("Lock Screen")
                    LockScreenPreview()
                        .padding(.horizontal, 2)
                }
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)
                // Full width at its own height; otherwise the card shrinks
                // to the leftover height and leaves a gap on the right.
                .fixedSize(horizontal: false, vertical: true)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionContent
                }
                .padding(selection == .lockScreen ? [.horizontal, .bottom] : .all, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlColor).opacity(0.35))
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selection {
        case .general: generalSection
        case .appearance: appearanceSection
        case .skins: skinsSection
        case .liveActivities: liveActivitiesSection
        case .clipboard: clipboardSection
        case .aiUsage: aiUsageSection
        case .hud: hudSection
        case .sideNotch: sideNotchSection
        case .utilities: utilitiesSection
        case .lockScreen: lockScreenSection
        case .about: aboutSection
        }
    }

    func pageTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .padding(.leading, 4)
            .padding(.bottom, 8)
    }
}
