import CoreGraphics
import Testing

struct LockScreenLayoutTests {
    private static func approximately(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    /// 14" MacBook Pro: the clock leaves 340 pt, the login area 320 pt.
    @Test func widgetFrameOnAFourteenInchScreen() {
        let frame = LockScreenLayout.widgetFrame(in: CGSize(width: 1512, height: 982))
        #expect(frame == CGRect(x: 526, y: 340, width: 460, height: 322))
    }

    /// Taller screens put the widgets 30 % down and give them the rest.
    @Test func widgetFrameOnATallScreen() {
        let frame = LockScreenLayout.widgetFrame(in: CGSize(width: 2560, height: 1440))
        #expect(frame == CGRect(x: 1050, y: 432, width: 460, height: 688))
    }

    /// A short screen moves the top up so the window keeps its minimum
    /// height above the login area.
    @Test func widgetFrameOnAShortScreenKeepsItsMinimumHeight() {
        let frame = LockScreenLayout.widgetFrame(in: CGSize(width: 800, height: 600))
        #expect(frame.minY == 60)
        #expect(frame.height == LockScreenLayout.minimumWidgetHeight)
        #expect(frame.maxY == 600 - LockScreenLayout.loginAreaHeight)
    }

    @Test func artworkControlsSitUnderTheArtwork() {
        // 982 × (0.36 + 0.17) + 20, inside the window (662 − 116 = 546).
        let top = LockScreenLayout.artworkControlsTop(in: CGSize(width: 1512, height: 982))
        #expect(Self.approximately(top, 540.46))
    }

    @Test(arguments: [CGFloat(600), 700, 982, 1440, 2160])
    func artworkControlsNeverLeaveTheWidgetWindow(height: CGFloat) {
        let size = CGSize(width: 1512, height: height)
        let top = LockScreenLayout.artworkControlsTop(in: size)
        #expect(top <= LockScreenLayout.widgetFrame(in: size).maxY - LockScreenLayout.artworkControlsHeight)
    }

    @Test func artworkControlsOnAShortScreenAreClamped() {
        // 600 × 0.53 + 20 = 338 would run past the window's 280 − 116.
        #expect(LockScreenLayout.artworkControlsTop(in: CGSize(width: 800, height: 600)) == 164)
    }

    @Test func widgetPlacementInAppKitCoordinates() {
        let screen = CGRect(x: 1512, y: -200, width: 1512, height: 982)
        let placement = LockScreenLayout.widgetPlacement(onScreenFrame: screen)
        // Top-left 340 pt down becomes a bottom-left origin: 782 − 662.
        #expect(placement.frame == CGRect(x: 1512 + 526, y: 120, width: 460, height: 322))
        #expect(Self.approximately(placement.controlsOffset, 540.46 - 340))
    }

    @Test func lockNotchSnapsUpToWholePoints() {
        #expect(LockNotchLayout.snapped(CGSize(width: 184.2, height: 32.5)) == CGSize(width: 185, height: 33))
        #expect(LockNotchLayout.snapped(CGSize(width: 200, height: 32)) == CGSize(width: 200, height: 32))
    }

    @Test func lockNotchWindowAddsTheEarsAndPadding() {
        // 185 + 2 × (33 − 12) + 2 × 14.
        #expect(LockNotchLayout.windowSize(notchSize: CGSize(width: 185, height: 33)) == CGSize(width: 255, height: 33))
        // A notch lower than the inset has no ears.
        #expect(LockNotchLayout.indicatorSize(notchHeight: 10) == 0)
    }

    @Test func lockNotchWindowIsCentredOnTheTopEdge() {
        let frame = LockNotchLayout.windowFrame(
            size: CGSize(width: 255, height: 33), onScreenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        #expect(frame == CGRect(x: 628.5, y: 949, width: 255, height: 33))
    }
}
