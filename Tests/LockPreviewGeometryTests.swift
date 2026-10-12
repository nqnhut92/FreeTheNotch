import SwiftUI
import Testing

struct LockPreviewGeometryTests {
    private static let screen = CGSize(width: 1512, height: 982)
    private static var aspect: CGFloat { screen.width / screen.height }

    private static func approximately(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    @Test(arguments: [
        (CGRect(x: 10, y: 10, width: 20, height: 20), CGRect(x: 10, y: 10, width: 20, height: 20)),
        (CGRect(x: -5, y: -8, width: 20, height: 20), CGRect(x: 0, y: 0, width: 20, height: 20)),
        (CGRect(x: 95, y: 90, width: 20, height: 20), CGRect(x: 80, y: 80, width: 20, height: 20)),
    ])
    func clampedMovesWithoutResizing(_ rect: CGRect, expected: CGRect) {
        #expect(rect.clamped(to: CGRect(x: 0, y: 0, width: 100, height: 100)) == expected)
    }

    /// The top 260 pt of the widget window plus a 50 × 36 margin, grown to
    /// the screen's aspect ratio around its centre.
    @Test func widgetsRectFramesTheTopOfTheWidgets() {
        let rect = LockPreviewGeometry.widgetsRect(in: Self.screen)
        #expect(rect.minX == 476)
        #expect(rect.width == 560)
        #expect(Self.approximately(rect.width / rect.height, Self.aspect))
        #expect(Self.approximately(rect.midY, 340 - 36 + (260 + 72) / 2))
    }

    @Test func widgetsRectOfNothingIsEmpty() {
        #expect(LockPreviewGeometry.widgetsRect(in: .zero) == .zero)
    }

    @Test func panStaysOnTheScreen() {
        let base = LockPreviewGeometry.widgetsRect(in: Self.screen)
        let far = LockPreviewGeometry.clampedPan(CGSize(width: 10_000, height: 10_000), in: Self.screen)
        #expect(Self.approximately(far.width, Self.screen.width - base.maxX))
        #expect(Self.approximately(far.height, Self.screen.height - base.maxY))
        let back = LockPreviewGeometry.clampedPan(CGSize(width: -10_000, height: -10_000), in: Self.screen)
        #expect(Self.approximately(back.width, -base.minX))
        #expect(Self.approximately(back.height, -base.minY))
        let small = CGSize(width: 12, height: -7)
        #expect(LockPreviewGeometry.clampedPan(small, in: Self.screen) == small)
    }

    @Test func focusRectFollowsThePan() {
        let base = LockPreviewGeometry.widgetsRect(in: Self.screen)
        let moved = LockPreviewGeometry.focusRect(in: Self.screen, pan: CGSize(width: 20, height: 10))
        #expect(moved == base.offsetBy(dx: 20, dy: 10))
    }

    @Test func focusAnimatesAsOneRect() {
        var effect = LockPreviewFocus(focus: CGRect(x: 1, y: 2, width: 3, height: 4), viewWidth: 400)
        #expect(effect.animatableData.first.first == 1)
        #expect(effect.animatableData.second.second == 4)
        effect.animatableData = AnimatablePair(AnimatablePair(100, 50), AnimatablePair(200, 100))
        #expect(effect.focus == CGRect(x: 100, y: 50, width: 200, height: 100))
        let transform = effect.effectValue(size: .zero)
        // 400 pt across 200 pt of screen: twice the size, shifted to the crop.
        #expect(transform.m11 == 2)
        #expect(transform.m22 == 2)
        #expect(transform.m31 == -200)
        #expect(transform.m32 == -100)
    }
}
