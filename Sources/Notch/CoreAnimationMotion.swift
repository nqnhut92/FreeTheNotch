// Our own (no reference equivalent): Atoll has no skins.

import AppKit
import QuartzCore
import SwiftUI

/// Moves SwiftUI content along a `SkinMotionCurve` with a Core Animation
/// keyframe animation. The render server plays it, so the app does no work
/// per frame; a `TimelineView` would rebuild the content, Lottie view
/// included, on every frame.
struct CoreAnimationMotion<Content: View>: NSViewRepresentable {
    /// Nil holds the content at rest.
    let curve: SkinMotionCurve?
    /// Frames per second the render server is asked for.
    let frameRate: Float
    /// Freezes the movement where it is.
    let isPaused: Bool
    /// The pivot, in unit coordinates of the content (SwiftUI's anchor).
    var anchor: UnitPoint = .top
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> CoreAnimationMotionView<Content> {
        CoreAnimationMotionView(rootView: content)
    }

    func updateNSView(_ view: CoreAnimationMotionView<Content>, context: Context) {
        view.host.rootView = content
        view.setMotion(
            CoreAnimationMotionView<Content>.Motion(curve: curve, frameRate: frameRate, anchor: anchor),
            isPaused: isPaused)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView view: CoreAnimationMotionView<Content>, context: Context
    ) -> CGSize? {
        view.host.fittingSize
    }
}

/// Hosts the content and owns its animation. Never takes clicks.
final class CoreAnimationMotionView<Content: View>: NSView {
    struct Motion: Equatable {
        var curve: SkinMotionCurve?
        var frameRate: Float
        var anchor: UnitPoint
    }

    let host: NSHostingView<Content>
    private var motion: Motion?
    private var isPaused = false
    /// Size and orientation the running animation was built for.
    private var builtFor: (size: CGSize, isFlipped: Bool)?

    private static var animationKey: String { "skinMotion" }
    /// Keyframes per period; the render server interpolates between them.
    private static var keyframeCount: Int { 60 }

    init(rootView: Content) {
        host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        host.frame = bounds
        rebuildIfNeeded()
    }

    func setMotion(_ motion: Motion, isPaused: Bool) {
        if motion != self.motion {
            self.motion = motion
            builtFor = nil
            rebuildIfNeeded()
        }
        if isPaused != self.isPaused {
            self.isPaused = isPaused
            applyPause()
        }
    }

    private func rebuildIfNeeded() {
        guard let layer = host.layer else { return }
        let size = host.bounds.size
        let isFlipped = layer.contentsAreFlipped()
        if let builtFor, builtFor.size == size, builtFor.isFlipped == isFlipped { return }
        layer.removeAnimation(forKey: Self.animationKey)
        builtFor = (size, isFlipped)
        guard let motion, let curve = motion.curve, size.width > 0, size.height > 0 else { return }
        layer.add(Self.animation(curve, motion: motion, layer: layer, isFlipped: isFlipped), forKey: Self.animationKey)
        applyPause()
    }

    /// Keyframes in the layer's own space. CA applies `transform` about the
    /// layer's anchor point, and the bounds are y-up unless the content is
    /// flipped.
    private static func animation(
        _ curve: SkinMotionCurve, motion: Motion, layer: CALayer, isFlipped: Bool
    ) -> CAKeyframeAnimation {
        let size = layer.bounds.size
        let pivot = CGPoint(x: motion.anchor.x * size.width, y: motion.anchor.y * size.height)
        let layerAnchor = CGPoint(x: layer.anchorPoint.x * size.width, y: layer.anchorPoint.y * size.height)
        let values = curve.keyframes(count: keyframeCount, anchor: pivot).map { transform in
            let local = isFlipped ? transform : transform.inYUpSpace(height: size.height)
            let aboutAnchor = CGAffineTransform(translationX: layerAnchor.x, y: layerAnchor.y)
                .concatenating(local)
                .concatenating(CGAffineTransform(translationX: -layerAnchor.x, y: -layerAnchor.y))
            return NSValue(caTransform3D: CATransform3DMakeAffineTransform(aboutAnchor))
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = values
        animation.duration = curve.period
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = CAFrameRateRange(
            minimum: motion.frameRate, maximum: motion.frameRate, preferred: motion.frameRate)
        return animation
    }

    private func applyPause() {
        host.layer?.setClockPaused(isPaused)
    }
}

extension CALayer {
    /// Core Animation's pause: stops the layer's clock (and its sublayers')
    /// where it is, and restarts it from there.
    func setClockPaused(_ isPaused: Bool) {
        if isPaused {
            guard speed != 0 else { return }
            let now = convertTime(CACurrentMediaTime(), from: nil)
            speed = 0
            timeOffset = now
        } else {
            guard speed == 0 else { return }
            let pausedAt = timeOffset
            speed = 1
            timeOffset = 0
            beginTime = 0
            beginTime = convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
    }
}
