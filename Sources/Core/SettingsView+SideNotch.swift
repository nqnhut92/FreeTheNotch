import SwiftUI

extension SettingsView {
    var sideNotchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageTitle("Side Notch")
            SettingsGroupHeader("Side Notch")
            SettingsCard {
                SettingsToggleRow(
                    "Show Side Notch",
                    description:
                        "A black notch on the screen edge with battery, Wi-Fi, volume and Bluetooth. Click the ring for Wi-Fi, Battery and Sound, Bluetooth for its menu, and each system icon for its controls. With Side Notch off, click the menu bar cup for the full panel.",
                    isOn: $settings.sideNotchEnabled, showDivider: false)
            }
            Group {
                SettingsGroupHeader("Edge")
                SideNotchEdgeCards(selection: $settings.sideNotchEdge, blocked: dockSide.blockedEdge)
                if let blocked = dockSide.blockedEdge {
                    SettingsFootnote(
                        "The Dock is on the \(blocked.title.lowercased()), so Side Notch uses the \(blocked.opposite.title.lowercased()) edge."
                    )
                }
                sideNotchCellsGroup
                SettingsGroupHeader("Placement")
                SettingsCard {
                    SettingsRow("Show on", description: "Same displays as the notch") {
                        Button(settings.displayScope.title) {
                            selection = .general
                        }
                        .help("Change in General \u{2192} Displays")
                    }
                    SettingsRow("Zoom", showDivider: false) {
                        Picker("Zoom", selection: $settings.sideNotchZoom) {
                            Text("1×").tag(1.0)
                            Text("2×").tag(2.0)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
            }
            .disabled(!settings.sideNotchEnabled)
            .opacity(settings.sideNotchEnabled ? 1 : 0.5)
        }
        .onAppear { dockSide.reload() }
    }

    /// Reorder the Side Notch cells: drag a row by its ≡ handle; the drawing
    /// beside the rows follows live. No reference equivalent: CodeNotch's
    /// cells are fixed.
    private var sideNotchCellsGroup: some View {
        let order = settings.sideNotchOrder
        return VStack(alignment: .leading, spacing: 0) {
            SettingsGroupHeader("Cells")
            SettingsCard {
                HStack(alignment: .center, spacing: 0) {
                    SideNotchOrderPreview(cells: order, edge: dockSide.effectiveEdge(for: settings.sideNotchEdge))
                        .frame(width: 92)
                        .padding(.vertical, 12)
                    Divider()
                    VStack(spacing: 0) {
                        ForEach(Array(order.enumerated()), id: \.element) { index, cell in
                            sideNotchCellRow(cell, position: index)
                                .onDrop(
                                    of: [.text],
                                    delegate: ReorderDropDelegate(
                                        target: cell, dragging: $draggingCell, order: $settings.sideNotchOrder))
                            Divider().padding(.leading, 16)
                        }
                        SettingsRow("Reset order", showDivider: false) {
                            Button("Reset") { settings.sideNotchOrderRaw = "" }
                                .disabled(settings.sideNotchOrder == SideNotchCell.allCases)
                        }
                    }
                }
            }
        }
    }

    private func sideNotchCellRow(_ cell: SideNotchCell, position: Int) -> some View {
        ReorderRow(payload: cell.rawValue) {
            sideNotchCellLabel(cell)
        } trailing: {
            Text((position + 1).formatted())
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } dragPreview: {
            sideNotchCellLabel(cell)
        } onDragStart: {
            draggingCell = cell
        }
    }

    private func sideNotchCellLabel(_ cell: SideNotchCell) -> some View {
        HStack(spacing: 12) {
            SideNotchCellIcon(cell: cell, size: 18)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
            VStack(alignment: .leading, spacing: 1) {
                Text(cell.title)
                    .font(.system(size: 14))
                Text(cell.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
