import CoreGraphics
import Testing

struct ArrayMovingTests {
    private static let items = ["a", "b", "c", "d"]

    @Test(arguments: [
        ("a", "c", ["b", "c", "a", "d"]),
        ("d", "b", ["a", "d", "b", "c"]),
        ("b", "c", ["a", "c", "b", "d"]),
        ("b", "b", ["a", "b", "c", "d"]),
        ("x", "b", ["a", "b", "c", "d"]),
        ("a", "x", ["a", "b", "c", "d"]),
    ])
    func movesIntoTheTargetsPlace(item: String, target: String, expected: [String]) {
        #expect(Self.items.moving(item, onto: target) == expected)
    }
}

struct AppInfoTests {
    @Test(arguments: [
        (2026, "2026 Nicholas Nguyen"),
        (2027, "2026-2027 Nicholas Nguyen"),
        (2031, "2026-2031 Nicholas Nguyen"),
        // A clock set to the past still shows the first year.
        (2020, "2026 Nicholas Nguyen"),
    ])
    func authorLine(year: Int, expected: String) {
        #expect(AppInfo.authorLine(year: year) == expected)
    }

    @Test func versionLine() {
        let full = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "20261012.161857"]
        #expect(AppInfo.versionLine(info: full) == "Version 0.1.0 (build-20261012.161857)")
        #expect(AppInfo.versionLine(info: ["CFBundleShortVersionString": "0.2.0"]) == "Version 0.2.0")
        #expect(AppInfo.versionLine(info: nil) == "Version 0.1")
    }
}

struct DisplayGeometryTests {
    private static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func menuBarHeightIsWhatTheVisibleFrameLeaves() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        #expect(DisplayGeometry.menuBarHeight(frame: Self.screen, visibleFrame: visible, safeAreaTop: 32) == 38)
    }

    /// A hidden menu bar leaves nothing to measure: the notch's safe area,
    /// else the classic 24 pt.
    @Test func menuBarHeightFallsBack() {
        #expect(DisplayGeometry.menuBarHeight(frame: Self.screen, visibleFrame: Self.screen, safeAreaTop: 32) == 32)
        #expect(
            DisplayGeometry.menuBarHeight(frame: Self.screen, visibleFrame: Self.screen, safeAreaTop: 0)
                == DisplayGeometry.fallbackMenuBarHeight)
        // One point is not a menu bar.
        let almost = CGRect(x: 0, y: 0, width: 1512, height: 981)
        #expect(DisplayGeometry.menuBarHeight(frame: Self.screen, visibleFrame: almost, safeAreaTop: 0) == 24)
    }

    @Test func physicalNotchWidthIsWhatTheAuxiliaryAreasLeave() {
        let left = CGRect(x: 0, y: 944, width: 664, height: 38)
        let right = CGRect(x: 848, y: 944, width: 664, height: 38)
        #expect(
            DisplayGeometry.physicalNotchWidth(screenWidth: 1512, auxiliaryLeft: left, auxiliaryRight: right) == 184)
    }

    @Test func physicalNotchWidthFallsBackWithoutBothAreas() {
        let left = CGRect(x: 0, y: 944, width: 664, height: 38)
        #expect(DisplayGeometry.physicalNotchWidth(screenWidth: 1512, auxiliaryLeft: nil, auxiliaryRight: nil) == 170)
        #expect(DisplayGeometry.physicalNotchWidth(screenWidth: 1512, auxiliaryLeft: left, auxiliaryRight: nil) == 170)
    }

    @Test func liveActivityAddsBothEars() {
        #expect(DisplayGeometry.liveActivityWidth(notchWidth: 184) == 308)
    }
}
