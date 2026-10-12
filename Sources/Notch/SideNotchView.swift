// The Bluetooth rune and the cell contents have no reference equivalent;
// the cell positions follow CodeNotch's layout (see SideNotchShape.swift).

import SwiftUI

/// The Bluetooth rune (ᛒ over ᚼ). SF Symbols has none. A vertical stroke,
/// two points on the right, two tails on the left crossing at the middle.
/// Stroke it; `rect` should be about twice as tall as wide.
struct BluetoothRune: Shape {
    func path(in rect: CGRect) -> Path {
        let h = rect.height
        let x0 = rect.midX
        let a = h * 0.24
        func p(_ dx: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x0 + dx, y: rect.minY + h * y) }
        var path = Path()
        path.move(to: p(-a, 0.27))
        path.addLine(to: p(a, 0.74))
        path.addLine(to: p(0, 1))
        path.addLine(to: p(0, 0))
        path.addLine(to: p(a, 0.26))
        path.addLine(to: p(-a, 0.73))
        return path
    }
}

/// Bluetooth logo for the side notch: system blue while Bluetooth is on
/// (like macOS's own Bluetooth controls), dimmed white while it is off.
struct BluetoothCellGlyph: View {
    var isOn: Bool
    /// Height of the rune.
    var height: CGFloat

    var body: some View {
        BluetoothRune()
            .stroke(style: StrokeStyle(lineWidth: height * 0.1, lineCap: .round, lineJoin: .round))
            .frame(width: height * 0.6, height: height)
            .foregroundStyle(isOn ? Color(nsColor: .systemBlue) : Color.white.opacity(0.3))
            .accessibilityLabel(isOn ? "Bluetooth on" : "Bluetooth off")
    }
}

/// Everything drawn in the side notch: the black body and its cells.
struct SideNotchView: View {
    @ObservedObject var battery: BatteryHUDController
    @ObservedObject var wifi: WiFiMonitor
    @ObservedObject var volume: OutputVolumeMonitor
    @ObservedObject var bluetooth: BluetoothMonitor
    let edge: SideNotchEdge
    let zoom: CGFloat
    let canvasSize: CGSize
    /// Top to bottom.
    let cells: [SideNotchCell]

    /// DuoGlyph scale whose ring (17 pt + 1.6 pt stroke at 1×) matches
    /// CodeNotch's 44 pt ring.
    static let glyphScale: CGFloat = SideNotchLayout.ringDiameter / 18.6

    var body: some View {
        // Drawn at the zoom (vector), not scaled afterwards.
        let z = zoom
        ZStack(alignment: .topLeading) {
            SideNotchShape(
                edge: edge,
                curlRadius: SideNotchLayout.curlRadius * z,
                cornerRadius: SideNotchLayout.cornerRadius * z
            )
            .fill(Color.black)
            ForEach(Array(cells.enumerated()), id: \.element) { index, cell in
                cellView(cell, at: CGPoint(x: canvasSize.width / 2, y: SideNotchLayout.cellCenterY(index) * z))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .environment(\.colorScheme, .dark)
    }

    /// One cell, centred on `center`.
    @ViewBuilder
    private func cellView(_ cell: SideNotchCell, at center: CGPoint) -> some View {
        let z = zoom
        switch cell {
        case .duo:
            // The canvas is 24 × 22 at 1×, ring centred at (12, 12): place
            // the ring's centre, not the frame's, on the cell centre.
            let glyph = Self.glyphScale * z
            DuoGlyphView(battery: battery, wifi: wifi, volume: volume, scale: glyph)
                .foregroundStyle(.white)
                .position(
                    x: center.x + (DuoGlyphCanvas.size.width / 2 - 12) * glyph,
                    y: center.y + (DuoGlyphCanvas.size.height / 2 - 12) * glyph)
        case .bluetooth:
            BluetoothCellGlyph(isOn: bluetooth.isPoweredOn, height: SideNotchLayout.ringDiameter * 0.68 * z)
                .position(center)
        default:
            Image(systemName: cell.icon)
                .font(.system(size: SideNotchLayout.ringDiameter * SideNotchCellIcon.symbolScale * z, weight: .medium))
                .foregroundStyle(SideNotchCellIcon.color(for: cell))
                .accessibilityLabel(cell.title)
                .position(center)
        }
    }
}
