import SwiftUI

/// The output list (`MediaOutputList`) as a panel under the lock-screen player's buttons, with an arrow at the
/// output button, as the popover has in the notch. A popover cannot open on the lock screen, so the player draws it.
struct LockOutputPanel: View {
    let usesMusicAirPlay: Bool
    /// Distance from the panel's right edge to the middle of the output button.
    let arrowInset: CGFloat

    private static let cornerRadius: CGFloat = 22
    private static let arrowHeight: CGFloat = 10
    private static let arrowHalfWidth: CGFloat = 14

    var body: some View {
        let shape = PanelShape(
            cornerRadius: Self.cornerRadius, arrowHeight: Self.arrowHeight, arrowHalfWidth: Self.arrowHalfWidth,
            arrowInset: arrowInset)
        MediaOutputList(usesMusicAirPlay: usesMusicAirPlay)
            .padding(.top, Self.arrowHeight)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .background(shape.fill(.ultraThinMaterial))
            .background(shape.fill(Color.black.opacity(0.6)))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}

/// A rounded rectangle with an arrow on its top edge, `arrowInset` from the right.
private struct PanelShape: Shape {
    let cornerRadius: CGFloat
    let arrowHeight: CGFloat
    let arrowHalfWidth: CGFloat
    let arrowInset: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: rect.minX, y: rect.minY + arrowHeight, width: rect.width, height: rect.height - arrowHeight)
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)
        let tipX = rect.maxX - arrowInset
        // A soft tip, as on a popover. The base sits a point inside the body so no seam shows.
        let base = body.minY + 1
        path.move(to: CGPoint(x: tipX - arrowHalfWidth, y: base))
        path.addCurve(
            to: CGPoint(x: tipX, y: rect.minY),
            control1: CGPoint(x: tipX - arrowHalfWidth * 0.45, y: body.minY),
            control2: CGPoint(x: tipX - arrowHalfWidth * 0.3, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: tipX + arrowHalfWidth, y: base),
            control1: CGPoint(x: tipX + arrowHalfWidth * 0.3, y: rect.minY),
            control2: CGPoint(x: tipX + arrowHalfWidth * 0.45, y: body.minY))
        path.closeSubpath()
        return path
    }
}
