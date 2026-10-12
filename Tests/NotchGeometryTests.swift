import SwiftUI
import Testing

struct NotchShapeTests {
    @Test func aiQuotaHUDUsesBatteryNotificationDimensions() {
        #expect(DisplayGeometry.aiQuotaHUDSize(notchWidth: 170, notchHeight: 38) == CGSize(width: 320, height: 113))
        #expect(DisplayGeometry.aiQuotaHUDSize(notchWidth: 210, notchHeight: 24) == CGSize(width: 360, height: 99))
    }

    private static let rect = CGRect(x: 10, y: 20, width: 200, height: 40)

    private static func isFinite(_ path: Path) -> Bool {
        var finite = true
        // Path is not a Sequence: forEach is its only element walk.
        // swift-format-ignore: ReplaceForEachWithForLoop
        path.forEach { element in
            let points: [CGPoint]
            switch element {
            case .move(let p), .line(let p): points = [p]
            case .quadCurve(let p, let c): points = [p, c]
            case .curve(let p, let c1, let c2): points = [p, c1, c2]
            case .closeSubpath: points = []
            }
            finite = finite && points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        }
        return finite
    }

    @Test(arguments: [CGFloat(0), 14, 22, 40])
    func fillsItsRect(bottomRadius: CGFloat) {
        let bounds = NotchShape(bottomRadius: bottomRadius).path(in: Self.rect).boundingRect
        #expect(abs(bounds.minX - Self.rect.minX) < 1e-6)
        #expect(abs(bounds.minY - Self.rect.minY) < 1e-6)
        #expect(abs(bounds.width - Self.rect.width) < 1e-6)
        #expect(abs(bounds.height - Self.rect.height) < 1e-6)
    }

    /// AGENTS.md: the island's top corners are never rounded.
    @Test func topCornersAreSquareAndBottomCornersRound() {
        let shape = NotchShape()
        #expect(shape.topRadius == 0)
        let path = shape.path(in: Self.rect)
        #expect(path.contains(CGPoint(x: Self.rect.minX + 0.5, y: Self.rect.minY + 0.5)))
        #expect(path.contains(CGPoint(x: Self.rect.maxX - 0.5, y: Self.rect.minY + 0.5)))
        #expect(!path.contains(CGPoint(x: Self.rect.minX + 0.5, y: Self.rect.maxY - 0.5)))
        #expect(!path.contains(CGPoint(x: Self.rect.maxX - 0.5, y: Self.rect.maxY - 0.5)))
    }

    @Test func radiiClampToHalfTheSmallerSide() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        #expect(NotchShape(bottomRadius: 1000).path(in: rect) == NotchShape(bottomRadius: 20).path(in: rect))
        #expect(
            NotchShape(topRadius: 500, bottomRadius: 500).path(in: rect)
                == NotchShape(topRadius: 20, bottomRadius: 20).path(in: rect))
    }

    @Test(arguments: [CGRect.zero, CGRect(x: 0, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: 2, height: 90)])
    func degenerateRectsStayFinite(_ rect: CGRect) {
        #expect(Self.isFinite(NotchShape(topRadius: 6, bottomRadius: 14).path(in: rect)))
        #expect(Self.isFinite(SideNotchShape(edge: .right).path(in: rect)))
        #expect(Self.isFinite(SideNotchShape(edge: .left).path(in: rect)))
    }

    @Test func animatableDataRoundTrips() {
        var shape = NotchShape(topRadius: 0, bottomRadius: 16)
        #expect(shape.animatableData == AnimatablePair(0, 16))
        shape.animatableData = AnimatablePair(3, 22)
        #expect(shape.topRadius == 3)
        #expect(shape.bottomRadius == 22)
    }
}

struct SideNotchGeometryTests {
    @Test(arguments: [
        (CGFloat(0.75), CGSize(width: 53, height: 376)),
        (CGFloat(1.5), CGSize(width: 105, height: 752)),
    ])
    func windowAndShapeShareWholePointBounds(zoom: CGFloat, expected: CGSize) {
        // 186 px wide and 1332 px tall, at 44 points per 117 px, rounded outward.
        #expect(SideNotchLayout.windowSize(zoom: zoom) == expected)
    }

    @Test func pixelsConvertAtCodeNotchsRingSize() {
        #expect(SideNotchLayout.px(117) == 44)
        #expect(SideNotchLayout.px(0) == 0)
        #expect(abs(SideNotchLayout.px(234) - 88) < 1e-9)
        #expect(abs(SideNotchLayout.ringDiameter - 44) < 1e-9)
    }

    @Test func cellsStepByRingPlusSpacing() {
        let step = SideNotchLayout.ringDiameter + SideNotchLayout.cellSpacing
        for index in 1..<SideNotchLayout.cellCount {
            let delta = SideNotchLayout.cellCenterY(index) - SideNotchLayout.cellCenterY(index - 1)
            #expect(abs(delta - step) < 1e-9)
        }
    }

    @Test func cellsAreCentredInTheShape() {
        let first = SideNotchLayout.cellCenterY(0)
        let last = SideNotchLayout.cellCenterY(SideNotchLayout.cellCount - 1)
        #expect(abs((first + last) / 2 - SideNotchLayout.size.height / 2) < 1e-9)
        #expect(SideNotchLayout.cellCount == SideNotchCell.allCases.count)
    }

    @Test func leftEdgeMirrorsRightEdge() {
        let rect = CGRect(origin: CGPoint(x: 5, y: 7), size: SideNotchLayout.size)
        let right = SideNotchShape(edge: .right).path(in: rect)
        let left = SideNotchShape(edge: .left).path(in: rect)
        for i in 0...24 {
            for j in 0...24 {
                let x = rect.minX + rect.width * (CGFloat(i) + 0.5) / 25
                let y = rect.minY + rect.height * (CGFloat(j) + 0.5) / 25
                let mirrored = CGPoint(x: rect.minX + rect.maxX - x, y: y)
                #expect(right.contains(CGPoint(x: x, y: y)) == left.contains(mirrored))
            }
        }
    }

    @Test func weldedToItsEdge() {
        let rect = CGRect(origin: .zero, size: SideNotchLayout.size)
        let right = SideNotchShape(edge: .right).path(in: rect)
        // The body touches the screen edge mid-height; the corner away from
        // the edge, beside the flare, stays empty.
        #expect(right.contains(CGPoint(x: rect.maxX - 0.5, y: rect.midY)))
        #expect(!right.contains(CGPoint(x: rect.minX + 0.5, y: rect.minY + 0.5)))
    }
}

struct DockSideTests {
    @Test(arguments: [
        (DockSide.Side.left, SideNotchEdge.left, SideNotchEdge.right),
        (.left, .right, .right),
        (.right, .left, .left),
        (.right, .right, .left),
        (.bottom, .left, .left),
        (.bottom, .right, .right),
    ])
    func theNotchTakesTheEdgeTheDockLeavesFree(
        dock: DockSide.Side, preferred: SideNotchEdge, expected: SideNotchEdge
    ) {
        #expect(DockSide.effectiveEdge(dock: dock, preferred: preferred) == expected)
    }

    @Test func blockedEdge() {
        #expect(DockSide.blockedEdge(dock: .left) == .left)
        #expect(DockSide.blockedEdge(dock: .right) == .right)
        #expect(DockSide.blockedEdge(dock: .bottom) == nil)
    }
}
