// Skin decorations: our own drawings (not in Atoll), no image assets.

import AppKit
import QuartzCore
import SwiftUI

/// Vines, Christmas lights or falling blossoms around the island, as Core
/// Animation layers (`SkinDecorationLayers`) the render server animates at
/// `motion`'s frame rate; still with Reduce Motion.
struct SkinDecorationView: View {
    let decoration: SkinDecoration
    let shapeSize: CGSize
    /// Settings previews pass `.still` while their window is in the background.
    var motion: SkinMotion = .smooth

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let canvasSize = SkinDecorationGeometry.canvasSize(for: shapeSize)
        SkinDecorationLayerView(
            decoration: decoration, shapeSize: shapeSize, frameRate: reduceMotion ? nil : motion.frameRate,
            isPaused: motion.isStill
        )
        .frame(width: canvasSize.width, height: canvasSize.height)
        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
    }
}

/// Hosts the decoration's layers in a layer this view owns.
private struct SkinDecorationLayerView: NSViewRepresentable {
    let decoration: SkinDecoration
    let shapeSize: CGSize
    let frameRate: Float?
    let isPaused: Bool

    func makeNSView(context: Context) -> SkinDecorationHostView { SkinDecorationHostView() }

    func updateNSView(_ view: SkinDecorationHostView, context: Context) {
        view.show(
            SkinDecorationHostView.Content(decoration: decoration, shapeSize: shapeSize, frameRate: frameRate),
            isPaused: isPaused)
    }
}

/// Layer-hosting view: its layer tree is ours, not AppKit's. Rebuilt only
/// when the decoration, the island's size or the frame rate changes. Never
/// takes clicks.
private final class SkinDecorationHostView: NSView {
    struct Content: Equatable {
        let decoration: SkinDecoration
        let shapeSize: CGSize
        let frameRate: Float?
    }

    /// Holds the decoration, y-down like the geometry.
    private let canvas = CALayer()
    private var content: Content?
    private var isPaused = false

    init() {
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        layer?.addSublayer(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.frame = bounds
        orientCanvas()
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }

    func show(_ content: Content, isPaused: Bool) {
        if content != self.content {
            self.content = content
            rebuild()
        }
        if isPaused != self.isPaused {
            self.isPaused = isPaused
            applyPause()
        }
    }

    /// The geometry is y-down; flip the canvas unless its parent already is.
    private func orientCanvas() {
        canvas.isGeometryFlipped = false
        canvas.isGeometryFlipped = !canvas.contentsAreFlipped()
    }

    private func rebuild() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        canvas.sublayers = nil
        guard let content else { return }
        let layers = SkinDecorationLayers.make(
            content.decoration, shapeSize: content.shapeSize, frameRate: content.frameRate)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for layer in layers {
            setScale(scale, on: layer)
            canvas.addSublayer(layer)
        }
        applyPause()
    }

    /// Sharp shapes and rasterized leaves on a Retina screen.
    private func setScale(_ scale: CGFloat, on layer: CALayer) {
        layer.contentsScale = scale
        layer.rasterizationScale = scale
        layer.mask.map { setScale(scale, on: $0) }
        for sublayer in layer.sublayers ?? [] { setScale(scale, on: sublayer) }
    }

    private func applyPause() {
        canvas.setClockPaused(isPaused)
    }
}
