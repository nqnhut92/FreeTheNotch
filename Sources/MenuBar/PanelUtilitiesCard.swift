import SwiftUI

// MARK: - Utilities card

// Port of Vorssaint's PanelRowGroup / UtilityActionButton / PanelRowHighlight
// (vorssaint/vorssaint-utils, GPL-3.0-or-later): one unpadded card of rows
// split by hairlines that start under the titles.
struct PanelUtilitiesCard: View {
    let onDismiss: () -> Void

    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var cleaning: CleaningModeController

    private struct Tool: Hashable {
        let title: String
        let caption: String
        let systemImage: String
    }

    private static let cleaningTool = Tool(
        title: "Cleaning Mode",
        caption: "Locks the keyboard so you can clean safely.",
        systemImage: "keyboard")

    var body: some View {
        let tools = [Self.cleaningTool]
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                if index > 0 {
                    Divider()
                        .padding(.leading, PanelUtilityRow.separatorInset)
                        .padding(.trailing, PanelUtilityRow.horizontalInset)
                        .accessibilityHidden(true)
                }
                PanelUtilityRow(title: tool.title, caption: tool.caption, systemImage: tool.systemImage) {
                    run(tool)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(padded: false)
    }

    private func run(_ tool: Tool) {
        // Close the panel first so the tool's window isn't covered by it.
        onDismiss()
        let lockTrackpad = settings.cleaningLockTrackpad
        let cleaning = cleaning
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if tool == Self.cleaningTool {
                cleaning.start(lockTrackpad: lockTrackpad)
            }
        }
    }
}

struct PanelUtilityRow: View {
    static let iconWidth: CGFloat = 22
    static let iconSpacing: CGFloat = 9
    static let horizontalInset: CGFloat = 10
    static let verticalInset: CGFloat = 8
    static var separatorInset: CGFloat { horizontalInset + iconWidth + iconSpacing }

    let title: String
    let caption: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.iconSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: Self.iconWidth)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.panelTertiary)
            }
            .padding(.horizontal, Self.horizontalInset)
            .padding(.vertical, Self.verticalInset)
            .background(
                // Inset from the card's edges so it never crosses its corners.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
                    .padding(3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(caption)
    }
}
