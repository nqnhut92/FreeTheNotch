import SwiftUI

/// The Settings preview's framing, as plain geometry in screen points.
enum LockPreviewGeometry {
    /// How much of the widget window's top "Widgets" frames: the rings and
    /// event rows; a drag shows the rest.
    static let widgetsHeight: CGFloat = 260
    /// Margin around the widgets in that frame.
    static let widgetsMargin = CGSize(width: 50, height: 36)

    /// The top of the widget window with a margin, grown to the screen's
    /// aspect ratio (so the card keeps its size) and kept on the screen.
    static func widgetsRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let window = LockScreenLayout.widgetFrame(in: size)
        let widgets = CGRect(
            x: window.minX, y: window.minY, width: window.width, height: min(window.height, widgetsHeight)
        )
        .insetBy(dx: -widgetsMargin.width, dy: -widgetsMargin.height)
        let aspect = size.width / size.height
        let width = min(size.width, max(widgets.width, widgets.height * aspect))
        let height = width / aspect
        let x = min(max(0, widgets.midX - width / 2), size.width - width)
        let y = min(max(0, widgets.midY - height / 2), size.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The widgets frame moved by `pan`, kept on the screen.
    static func focusRect(in size: CGSize, pan: CGSize) -> CGRect {
        widgetsRect(in: size).offsetBy(dx: pan.width, dy: pan.height).clamped(to: CGRect(origin: .zero, size: size))
    }

    /// `pan` limited so the frame stays on the screen.
    static func clampedPan(_ pan: CGSize, in size: CGSize) -> CGSize {
        let base = widgetsRect(in: size)
        let moved = focusRect(in: size, pan: pan)
        return CGSize(width: moved.minX - base.minX, height: moved.minY - base.minY)
    }
}

extension CGRect {
    /// Moved (not resized) to lie inside `bounds`.
    func clamped(to bounds: CGRect) -> CGRect {
        CGRect(
            x: min(max(bounds.minX, minX), bounds.maxX - width),
            y: min(max(bounds.minY, minY), bounds.maxY - height),
            width: width, height: height)
    }
}

/// Shows `focus` (screen points) across `viewWidth`. One transform whose
/// rect is interpolated as a whole: animating `scaleEffect` and `offset`
/// separately makes the picture swing and stutter between Screen and Widgets.
struct LockPreviewFocus: GeometryEffect {
    var focus: CGRect
    let viewWidth: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(focus.minX, focus.minY), AnimatablePair(focus.width, focus.height)) }
        set {
            focus = CGRect(
                x: newValue.first.first, y: newValue.first.second,
                width: newValue.second.first, height: newValue.second.second)
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let scale = viewWidth / max(focus.width, 1)
        return ProjectionTransform(
            CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: -focus.minX * scale, ty: -focus.minY * scale))
    }
}
