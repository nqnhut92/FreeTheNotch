import AppKit
import SwiftUI

/// Card picker for Settings → General → Displays: one card per
/// `DisplayScope`, with a small drawing of the screens it covers.
struct DisplayScopeCards: View {
    @Binding var selection: DisplayScope

    var body: some View {
        HStack(spacing: 10) {
            ForEach(DisplayScope.allCases, id: \.self) { scope in
                let isSelected = selection == scope
                SelectableCard(isSelected: isSelected, minHeight: 116) {
                    selection = scope
                } label: {
                    VStack(spacing: 8) {
                        DisplayScopeIllustration(scope: scope, isSelected: isSelected)
                            .frame(height: 46)
                        VStack(spacing: 2) {
                            Text(scope.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(scope.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

/// Laptop + external monitor; the screens a scope covers are tinted.
private struct DisplayScopeIllustration: View {
    let scope: DisplayScope
    let isSelected: Bool

    private var laptopLit: Bool { scope != .mainDisplay }
    /// The external monitor stands in for the main display.
    private var monitorLit: Bool { scope != .mainOnly }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // Laptop: screen with a notch over a base.
            VStack(spacing: 0) {
                screen(lit: laptopLit, width: 34, height: 22, notch: true, menuBar: false)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 42, height: 3)
            }
            // Monitor: screen with a menu bar over a stand.
            VStack(spacing: 0) {
                screen(lit: monitorLit, width: 44, height: 28, notch: false, menuBar: true)
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 4, height: 5)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 16, height: 2)
            }
        }
    }

    private func screen(lit: Bool, width: CGFloat, height: CGFloat, notch: Bool, menuBar: Bool) -> some View {
        let tint = isSelected ? Color.accentColor : Color.primary.opacity(0.55)
        return RoundedRectangle(cornerRadius: 3)
            .fill(lit ? tint.opacity(0.85) : Color.primary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                if notch {
                    Capsule().fill(Color.black).frame(width: 8, height: 3).offset(y: 1)
                } else if menuBar {
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(height: 3)
                        .padding(.horizontal, 1)
                        .padding(.top, 1)
                }
            }
            .frame(width: width, height: height)
    }
}

/// Card picker for Settings → Side Notch → Edge: Left and Right, each with
/// a drawing of a screen and the side notch centred on that edge. `blocked`
/// is the edge the Dock takes (DockSide), greyed out.
struct SideNotchEdgeCards: View {
    @Binding var selection: SideNotchEdge
    let blocked: SideNotchEdge?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SideNotchEdge.allCases, id: \.self) { edge in
                let isBlocked = blocked == edge
                // With the Dock on a side, the free edge is the one in use.
                let isSelected = blocked.map { $0.opposite == edge } ?? (selection == edge)
                SelectableCard(isSelected: isSelected) {
                    selection = edge
                } label: {
                    VStack(spacing: 8) {
                        SideNotchEdgeIllustration(edge: edge, isSelected: isSelected)
                            .frame(height: 46)
                        Text(edge.title)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .disabled(isBlocked)
                .opacity(isBlocked ? 0.4 : 1)
            }
        }
    }
}

/// A screen with a menu bar and the black side notch centred on one edge.
private struct SideNotchEdgeIllustration: View {
    let edge: SideNotchEdge
    let isSelected: Bool

    var body: some View {
        let width: CGFloat = 64
        let height: CGFloat = 40
        let tint = isSelected ? Color.accentColor : Color.primary.opacity(0.55)
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(tint.opacity(isSelected ? 0.85 : 0.35))
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.primary.opacity(0.35)).frame(height: 3)
                        .padding(.horizontal, 1).padding(.top, 1)
                }
                .overlay(alignment: edge == .right ? .trailing : .leading) {
                    // The real shape, at its own proportions.
                    let scale: CGFloat = 22 / SideNotchLayout.size.height
                    SideNotchShape(
                        edge: edge,
                        curlRadius: SideNotchLayout.curlRadius * scale,
                        cornerRadius: SideNotchLayout.cornerRadius * scale
                    )
                    .fill(Color.black)
                    .frame(
                        width: SideNotchLayout.size.width * scale,
                        height: SideNotchLayout.size.height * scale
                    )
                    .padding(edge == .right ? .trailing : .leading, 1)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                )
                .frame(width: width, height: height)
            Rectangle()
                .fill(Color.primary.opacity(0.35))
                .frame(width: 4, height: 4)
        }
    }
}

/// A cell's glyph for Settings, drawn in white/blue/orange on black. The
/// DuoGlyph is a stand-in (a ring around the Wi-Fi symbol); the real one
/// needs the Side Notch's own Wi-Fi and volume monitors.
struct SideNotchCellIcon: View {
    static let symbolScale: CGFloat = 0.68

    static func color(for cell: SideNotchCell) -> Color {
        switch cell {
        case .keepAwake: return Color(nsColor: .systemOrange)
        case .system: return Color(nsColor: .systemPurple)
        case .network: return Color(nsColor: .systemTeal)
        case .disk: return Color(nsColor: .systemGray)
        case .power: return Color(nsColor: .systemGreen)
        default: return .white
        }
    }

    let cell: SideNotchCell
    /// Ring diameter.
    let size: CGFloat

    var body: some View {
        switch cell {
        case .duo:
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(Color(nsColor: .systemGreen), style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0.72, to: 1)
                    .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "wifi")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        case .bluetooth:
            BluetoothCellGlyph(isOn: true, height: size * 0.68)
        default:
            Image(systemName: cell.icon)
                .font(.system(size: size * Self.symbolScale, weight: .medium))
                .foregroundStyle(Self.color(for: cell))
        }
    }
}

/// The Side Notch drawn small with its cells in `cells` order, on `edge`.
/// Cells slide to their new place while a row is dragged.
struct SideNotchOrderPreview: View {
    let cells: [SideNotchCell]
    let edge: SideNotchEdge

    var body: some View {
        let scale: CGFloat = 150 / SideNotchLayout.size.height
        let size = CGSize(width: SideNotchLayout.size.width * scale, height: SideNotchLayout.size.height * scale)
        ZStack(alignment: .topLeading) {
            SideNotchShape(
                edge: edge,
                curlRadius: SideNotchLayout.curlRadius * scale,
                cornerRadius: SideNotchLayout.cornerRadius * scale
            )
            .fill(Color.black)
            ForEach(Array(cells.enumerated()), id: \.element) { index, cell in
                SideNotchCellIcon(cell: cell, size: SideNotchLayout.ringDiameter * scale)
                    .position(x: size.width / 2, y: SideNotchLayout.cellCenterY(index) * scale)
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, alignment: edge == .right ? .trailing : .leading)
        .overlay(alignment: edge == .right ? .trailing : .leading) {
            // The screen edge the notch is welded to.
            Rectangle()
                .fill(Color.primary.opacity(0.35))
                .frame(width: 1)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: cells)
        .accessibilityLabel("Side Notch preview: " + cells.map(\.title).joined(separator: ", "))
    }
}

/// Sidebar icon for Side Notch: a screen outline with a black side notch on
/// its right edge, holding a tiny white ring. Fatter than the real shape so
/// the ring fits at 26 pt.
struct SideNotchSidebarIcon: View {
    var body: some View {
        let screen = CGSize(width: 19, height: 15)
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 2.5)
                .strokeBorder(Color.white, lineWidth: 1.4)
                .frame(width: screen.width, height: screen.height)
            ZStack {
                SideNotchShape(edge: .right, curlRadius: 2.2, cornerRadius: 3)
                    .fill(Color.black)
                Circle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: 3.6, height: 3.6)
                    .offset(x: -0.3)
            }
            .frame(width: 7, height: 12.6)
            .padding(.trailing, 1.4)
        }
        .frame(width: screen.width, height: screen.height)
    }
}
