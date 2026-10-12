import SwiftUI
import Testing

struct NotchSkinTests {
    /// AGENTS.md: skins are fixed combos, in this order.
    @Test func skinsAreTheFixedSet() {
        #expect(NotchSkin.allCases == [.none, .jungle, .cozyCat, .christmas, .sakura, .custom])
    }

    /// Persisted in settings: renaming a case would reset users' skins.
    @Test func rawValuesAreStable() {
        #expect(NotchSkin.allCases.map(\.rawValue) == ["none", "jungle", "cozyCat", "christmas", "sakura", "custom"])
        #expect(NotchSkin(rawValue: "sakura") == .sakura)
    }

    @Test func decorations() {
        #expect(NotchSkin.jungle.decoration == .vines)
        #expect(NotchSkin.christmas.decoration == .lights)
        #expect(NotchSkin.sakura.decoration == .blossoms)
        #expect([NotchSkin.none, .cozyCat, .custom].allSatisfy { $0.decoration == nil })
    }
}

struct PathSamplingTests {
    private typealias Sample = SkinDecorationView.PathSample

    private static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private static func near(_ a: Sample, _ point: CGPoint, angle: CGFloat) -> Bool {
        abs(a.point.x - point.x) < 1e-9 && abs(a.point.y - point.y) < 1e-9 && abs(a.angle - angle) < 1e-9
    }

    @Test func straightLineEverySpacing() {
        let samples = SkinDecorationView.sample(
            Self.polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]), spacing: 10)
        #expect(samples.map(\.point.x) == stride(from: 10, through: 100, by: 10).map { CGFloat($0) })
        #expect(samples.allSatisfy { $0.point.y == 0 && $0.angle == 0 })
    }

    @Test func angleFollowsTheDirection() {
        let down = SkinDecorationView.sample(Self.polyline([.zero, CGPoint(x: 0, y: 30)]), spacing: 10)
        #expect(down.count == 3)
        #expect(down.allSatisfy { abs($0.angle - .pi / 2) < 1e-9 })
    }

    /// The spacing is measured along the path, across the corner.
    @Test func spacingCarriesAcrossCorners() {
        let samples = SkinDecorationView.sample(
            Self.polyline([.zero, CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]), spacing: 4)
        #expect(samples.count == 5)
        guard samples.count == 5 else { return }
        #expect(Self.near(samples[0], CGPoint(x: 4, y: 0), angle: 0))
        #expect(Self.near(samples[1], CGPoint(x: 8, y: 0), angle: 0))
        #expect(Self.near(samples[2], CGPoint(x: 10, y: 2), angle: .pi / 2))
        #expect(Self.near(samples[3], CGPoint(x: 10, y: 6), angle: .pi / 2))
        #expect(Self.near(samples[4], CGPoint(x: 10, y: 10), angle: .pi / 2))
    }

    @Test func emptyPathsHaveNoSamples() {
        #expect(SkinDecorationView.sample(Path(), spacing: 5).isEmpty)
        var single = Path()
        single.move(to: CGPoint(x: 3, y: 3))
        #expect(SkinDecorationView.sample(single, spacing: 5).isEmpty)
    }

    @Test func curvesAreSampledAlongTheirLength() {
        var arc = Path()
        arc.move(to: .zero)
        arc.addQuadCurve(to: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 50))
        let samples = SkinDecorationView.sample(arc, spacing: 10)
        // The curve is longer than its 100 pt chord and shorter than the
        // 141 pt control polygon.
        #expect((10...14).contains(samples.count))
        #expect(samples.allSatisfy { $0.point.y >= 0 && $0.point.y <= 25 })
    }
}
