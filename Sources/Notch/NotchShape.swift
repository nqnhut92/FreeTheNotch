import SwiftUI

/// The island's silhouette (Atoll-style): square top corners flush with the
/// screen edge and rounded bottom corners. Both radii are animatable, so the
/// shape morphs between the closed and open island.
struct NotchShape: Shape {
    /// Kept for Atoll parity; the island always passes 0 (its top corners
    /// stay square against the screen edge).
    var topRadius: CGFloat = 0
    var bottomRadius: CGFloat = 14

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let t = min(topRadius, rect.width / 2, rect.height / 2)
        let b = min(bottomRadius, rect.width / 2, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + t))
        if t > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + t, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY))
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY))
        if t > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + t),
                control: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - b))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - b, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + b, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - b),
            control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
