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
    private typealias Sample = Polyline.Sample

    private static func polyline(_ points: [CGPoint]) -> Polyline {
        var line = Polyline(start: points[0])
        for point in points.dropFirst() { line.addLine(to: point) }
        return line
    }

    private static func near(_ a: Sample, _ point: CGPoint, angle: CGFloat) -> Bool {
        abs(a.point.x - point.x) < 1e-9 && abs(a.point.y - point.y) < 1e-9 && abs(a.angle - angle) < 1e-9
    }

    @Test func straightLineEverySpacing() {
        let samples = Self.polyline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]).samples(spacing: 10)
        #expect(samples.map(\.point.x) == stride(from: 10, through: 100, by: 10).map { CGFloat($0) })
        #expect(samples.allSatisfy { $0.point.y == 0 && $0.angle == 0 })
    }

    @Test func angleFollowsTheDirection() {
        let down = Self.polyline([.zero, CGPoint(x: 0, y: 30)]).samples(spacing: 10)
        #expect(down.count == 3)
        #expect(down.allSatisfy { abs($0.angle - .pi / 2) < 1e-9 })
    }

    /// The spacing is measured along the path, across the corner.
    @Test func spacingCarriesAcrossCorners() {
        let samples = Self.polyline([.zero, CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]).samples(spacing: 4)
        #expect(samples.count == 5)
        guard samples.count == 5 else { return }
        #expect(Self.near(samples[0], CGPoint(x: 4, y: 0), angle: 0))
        #expect(Self.near(samples[1], CGPoint(x: 8, y: 0), angle: 0))
        #expect(Self.near(samples[2], CGPoint(x: 10, y: 2), angle: .pi / 2))
        #expect(Self.near(samples[3], CGPoint(x: 10, y: 6), angle: .pi / 2))
        #expect(Self.near(samples[4], CGPoint(x: 10, y: 10), angle: .pi / 2))
    }

    @Test func aSinglePointHasNoSamples() {
        #expect(Polyline(start: CGPoint(x: 3, y: 3)).samples(spacing: 5).isEmpty)
    }

    @Test func curvesAreSampledAlongTheirLength() {
        var arc = Polyline(start: .zero)
        arc.addQuadCurve(to: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 50))
        let samples = arc.samples(spacing: 10)
        // The curve is longer than its 100 pt chord and shorter than the
        // 141 pt control polygon.
        #expect((10...14).contains(samples.count))
        #expect(samples.allSatisfy { $0.point.y >= 0 && $0.point.y <= 25 })
    }
}

struct SkinDecorationGeometryTests {
    private static let island = SkinDecorationGeometry.island(for: CGSize(width: 300, height: 32))

    @Test func theCanvasLeavesRoomAroundTheIsland() {
        #expect(
            SkinDecorationGeometry.canvasSize(for: CGSize(width: 300, height: 32)) == CGSize(width: 332, height: 122))
        #expect(Self.island == CGRect(x: 16, y: 0, width: 300, height: 32))
    }

    /// The top of a strand hangs from the vine; only the rest sways.
    @Test(arguments: SkinDecorationGeometry.strands.indices)
    func aStrandSwaysFromAFixedTop(index: Int) throws {
        let quarter = SkinDecorationGeometry.strand(index, island: Self.island, time: 0.25 * 2 * .pi / 0.9)
        let rest = SkinDecorationGeometry.strand(index, island: Self.island, time: 0)
        #expect(quarter.points.first == rest.points.first)
        #expect(quarter.points.count == rest.points.count)
        let quarterTip = try #require(quarter.points.last)
        let restTip = try #require(rest.points.last)
        #expect(quarterTip.x != restTip.x)
        #expect(quarterTip.y == restTip.y)
    }

    /// Keyframed leaves need the same leaf count in every pose.
    @Test(arguments: SkinDecorationGeometry.strands.indices)
    func aStrandKeepsItsLeafCountWhileSwaying(index: Int) {
        let count = SkinDecorationGeometry.strandLeafCount(index, island: Self.island)
        let poses = (0..<12).map {
            SkinDecorationGeometry.strandLeaves(index, island: Self.island, time: Double($0) * 0.6)
        }
        #expect(count > 0)
        #expect(poses.allSatisfy { $0.count == count })
    }

    /// Mid-edge the vine is nearly level, so neighbouring leaves point to
    /// opposite sides of it.
    @Test func leavesAlternateSides() {
        let leaves = SkinDecorationGeometry.edgeLeaves(island: Self.island)
        let middle = leaves.count / 2
        #expect((leaves[middle].angle > 0) != (leaves[middle + 1].angle > 0))
    }

    /// 300 pt island: the wire runs from x = 28 to 304, six swags of 46 pt,
    /// three bulbs on each, and one at the end of each corner drop.
    @Test func lightsHangThreeBulbsPerSwagAndOnePerDrop() throws {
        let bulbs = SkinDecorationGeometry.bulbs(island: Self.island)
        #expect(bulbs.count == 6 * 3 + 2)
        let middle = try #require(bulbs.dropFirst().first)
        #expect(abs(middle.point.x - (28 + 23)) < 1e-9)
        #expect(abs(middle.point.y - (30 + 10)) < 1e-9)
        #expect(middle.angle == 0)
    }

    /// A petal fades in from nothing and out to nothing, so its loop does
    /// not jump.
    @Test(arguments: 0..<SkinDecorationGeometry.Petal.count)
    func petalsFadeAtBothEndsOfTheirFall(index: Int) {
        let petal = SkinDecorationGeometry.Petal(index: index)
        #expect(petal.state(progress: 0, island: Self.island).opacity == 0)
        #expect(petal.state(progress: 1, island: Self.island).opacity == 0)
        #expect(petal.state(progress: 0.5, island: Self.island).opacity == 1)
        #expect((5.5...10.5).contains(petal.period))
        #expect((0...petal.period).contains(petal.startOffset))
    }
}
