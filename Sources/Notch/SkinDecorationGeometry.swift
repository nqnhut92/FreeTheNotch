// Skin decorations: our own drawings (not in Atoll), no image assets.

import CoreGraphics
import Foundation

/// Where every part of a skin decoration is, as plain geometry in a y-down
/// space around the island (`SkinDecorationLayers` turns it into Core
/// Animation layers). Positions are functions of time so one period can be
/// sampled into keyframes.
enum SkinDecorationGeometry {
    /// Room around the island the drawing may use.
    static let sideMargin: CGFloat = 16
    static let drop: CGFloat = 90

    /// The island's rectangle inside the decoration's canvas.
    static func island(for shapeSize: CGSize) -> CGRect {
        CGRect(x: sideMargin, y: 0, width: shapeSize.width, height: shapeSize.height)
    }

    static func canvasSize(for shapeSize: CGSize) -> CGSize {
        CGSize(width: shapeSize.width + sideMargin * 2, height: shapeSize.height + drop)
    }

    // MARK: Leaves

    /// A leaf at rest: its base point, its direction without the flutter,
    /// and its size. The leaf flutters `flutterAmplitude` radians either
    /// way, `flutterPhase` into the cycle.
    struct Leaf: Equatable {
        var base: CGPoint
        var angle: CGFloat
        var flutterPhase: Double
        var width: CGFloat
        var height: CGFloat
    }

    static let flutterSpeed = 2.2
    static let flutterAmplitude = 0.18

    /// Leaves alternating left and right along `polyline`, every `spacing`.
    static func leaves(along polyline: Polyline, spacing: CGFloat, size: CGFloat, seed: Double) -> [Leaf] {
        polyline.samples(spacing: spacing).enumerated().compactMap { index, sample in
            guard index > 0 else { return nil }
            let side: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let scale = 0.75 + 0.35 * CGFloat(abs(sin(Double(index) * 1.7 + seed)))
            return Leaf(
                base: sample.point, angle: sample.angle + side * (.pi / 3.2),
                flutterPhase: Double(index) * 0.8 + seed,
                width: size * scale * 1.5, height: size * scale * 0.8)
        }
    }

    // MARK: Vines

    /// A strand hanging from the bottom edge: where along the island, how
    /// long, and where in its sway it starts.
    struct Strand: Equatable {
        let x: CGFloat
        let length: CGFloat
        let phase: Double
    }

    /// Longest at the corners.
    static let strands = [
        Strand(x: 0.04, length: 46, phase: 0), Strand(x: 0.2, length: 24, phase: 1.3),
        Strand(x: 0.5, length: 16, phase: 2.1), Strand(x: 0.83, length: 32, phase: 0.7),
        Strand(x: 0.97, length: 54, phase: 2.6),
    ]
    static let swaySpeed = 0.9
    static let swayReach: CGFloat = 5
    static let strandSteps = 12

    /// Vine along the bottom edge, sagging slightly, curling up both sides.
    static func edgeVine(island: CGRect) -> Polyline {
        let bottom = island.maxY - 1.5
        let curl: CGFloat = 14
        var vine = Polyline(start: CGPoint(x: island.minX + 1, y: island.minY + island.height * 0.35))
        vine.addQuadCurve(
            to: CGPoint(x: island.minX + curl, y: bottom + 1), control: CGPoint(x: island.minX - 1, y: bottom))
        vine.addCurve(
            to: CGPoint(x: island.maxX - curl, y: bottom + 1),
            control1: CGPoint(x: island.minX + island.width * 0.35, y: bottom + 6),
            control2: CGPoint(x: island.minX + island.width * 0.65, y: bottom + 6))
        vine.addQuadCurve(
            to: CGPoint(x: island.maxX - 1, y: island.minY + island.height * 0.35),
            control: CGPoint(x: island.maxX + 1, y: bottom))
        return vine
    }

    static func edgeLeaves(island: CGRect) -> [Leaf] {
        leaves(along: edgeVine(island: island), spacing: 11, size: 6.5, seed: 1)
    }

    /// Strand `index` at `time` seconds into its sway: its top stays put,
    /// its tip swings furthest.
    static func strand(_ index: Int, island: CGRect, time: Double) -> Polyline {
        let strand = strands[index]
        let bottom = island.maxY - 1.5
        let x = island.minX + island.width * strand.x
        let start = CGPoint(x: x, y: bottom + (strand.x > 0.1 && strand.x < 0.9 ? 4 : 0))
        var line = Polyline(start: start)
        for step in 1...strandSteps {
            let progress = CGFloat(step) / CGFloat(strandSteps)
            let sway = CGFloat(sin(time * swaySpeed + strand.phase)) * swayReach * pow(progress, 1.4)
            line.addLine(
                to: CGPoint(
                    x: start.x + sway + sin(progress * 5 + CGFloat(index)) * 1.5,
                    y: start.y + strand.length * progress))
        }
        return line
    }

    /// The leaves of strand `index` at `time`. The count is the one at rest,
    /// so a leaf keeps its identity while the strand sways.
    static func strandLeaves(_ index: Int, island: CGRect, time: Double) -> [Leaf] {
        let restCount = strandLeafCount(index, island: island)
        let leaves = leaves(
            along: strand(index, island: island, time: time), spacing: 7.5, size: 5.5, seed: Double(index) + 3)
        guard let last = leaves.last else { return [] }
        return Array((leaves + Array(repeating: last, count: max(0, restCount - leaves.count))).prefix(restCount))
    }

    static func strandLeafCount(_ index: Int, island: CGRect) -> Int {
        leaves(along: strand(index, island: island, time: 0), spacing: 7.5, size: 5.5, seed: Double(index) + 3).count
    }

    // MARK: Christmas lights

    /// A bulb: where it hangs, its tilt, and where in its twinkle it starts.
    struct Bulb: Equatable {
        let point: CGPoint
        let angle: CGFloat
        let twinklePhase: Double
    }

    static let twinkleSpeed = 2.6
    static let sag: CGFloat = 10

    /// The wire: swags from corner to corner, then a short drop at each
    /// corner, as separate pieces.
    static func lightsWire(island: CGRect) -> [Polyline] {
        let (left, right, bottom, swags, swagWidth) = lightsLayout(island: island)
        var wire = Polyline(start: CGPoint(x: left, y: bottom))
        for index in 0..<swags {
            let x0 = left + CGFloat(index) * swagWidth
            let x1 = x0 + swagWidth
            wire.addQuadCurve(to: CGPoint(x: x1, y: bottom), control: CGPoint(x: (x0 + x1) / 2, y: bottom + sag * 2))
        }
        let drops = [left, right].map { x in
            var drop = Polyline(start: CGPoint(x: x, y: bottom))
            drop.addLine(to: CGPoint(x: x, y: bottom + 12))
            return drop
        }
        return [wire] + drops
    }

    static func bulbs(island: CGRect) -> [Bulb] {
        let (left, right, bottom, swags, swagWidth) = lightsLayout(island: island)
        var placed: [(CGPoint, CGFloat)] = []
        for index in 0..<swags {
            let x0 = left + CGFloat(index) * swagWidth
            // On the swag (quadratic: y = bottom + sag * 4p(1-p)).
            for p in [0.2, 0.5, 0.8] as [CGFloat] {
                let slope = sag * 4 * (1 - 2 * p) / swagWidth
                placed.append((CGPoint(x: x0 + swagWidth * p, y: bottom + sag * 4 * p * (1 - p)), atan(slope)))
            }
        }
        for x in [left, right] { placed.append((CGPoint(x: x, y: bottom + 12), 0)) }
        return placed.enumerated().map { index, bulb in
            Bulb(point: bulb.0, angle: bulb.1, twinklePhase: Double(index) * 1.9)
        }
    }

    /// Starts inside the rounded corners so the wire touches the island.
    private static func lightsLayout(
        island: CGRect
    ) -> (left: CGFloat, right: CGFloat, bottom: CGFloat, swags: Int, swagWidth: CGFloat) {
        let left = island.minX + 12
        let right = island.maxX - 12
        let swags = max(3, Int((right - left) / 46))
        return (left, right, island.maxY - 2, swags, (right - left) / CGFloat(swags))
    }

    // MARK: Sakura

    /// A flower on the twig; `wobblePhase` nil keeps it still.
    struct Flower: Equatable {
        let point: CGPoint
        let size: CGFloat
        let rotation: Double
        let wobblePhase: Double?
    }

    static let wobbleSpeed = 0.8
    static let wobbleAmplitude = 0.08

    /// A twig along the right half of the bottom edge, and a shoot below it.
    static func twig(island: CGRect) -> (twig: Polyline, shoot: Polyline) {
        let bottom = island.maxY - 1
        var twig = Polyline(start: CGPoint(x: island.maxX + 6, y: island.minY + island.height * 0.45))
        twig.addCurve(
            to: CGPoint(x: island.minX + island.width * 0.45, y: bottom + 5),
            control1: CGPoint(x: island.maxX - 2, y: bottom + 6),
            control2: CGPoint(x: island.minX + island.width * 0.7, y: bottom + 2))
        var shoot = Polyline(start: CGPoint(x: island.maxX - 16, y: bottom + 3))
        shoot.addQuadCurve(
            to: CGPoint(x: island.maxX - 30, y: bottom + 20), control: CGPoint(x: island.maxX - 18, y: bottom + 14))
        return (twig, shoot)
    }

    static func flowers(island: CGRect) -> [Flower] {
        let bottom = island.maxY - 1
        let onTwig = twig(island: island).twig.samples(spacing: 15).enumerated().compactMap {
            index, sample -> Flower? in
            guard index > 0 else { return nil }
            return Flower(
                point: CGPoint(x: sample.point.x, y: sample.point.y + (index.isMultiple(of: 2) ? 3 : -1)),
                size: index.isMultiple(of: 3) ? 4.5 : 3.6, rotation: Double(index) * 0.9,
                wobblePhase: Double(index))
        }
        return onTwig + [
            Flower(point: CGPoint(x: island.maxX - 30, y: bottom + 20), size: 4.2, rotation: 0.4, wobblePhase: nil),
            Flower(point: CGPoint(x: island.maxX - 22, y: bottom + 12), size: 3.4, rotation: 1.1, wobblePhase: nil),
        ]
    }

    /// A falling petal: deterministic, each on its own loop.
    struct Petal: Equatable {
        let index: Int

        static let count = 14
        static let size: CGFloat = 4.2

        private var seed: Double { Double(index) * 12.9898 }

        /// Seconds per fall.
        var period: Double { 5.5 + (sin(seed) + 1) * 2.5 }

        /// Seconds into the fall at time 0.
        var startOffset: Double { abs(sin(seed * 3.1)) * period }

        /// The petal `progress` (0…1) into its fall.
        func state(progress p: Double, island: CGRect) -> PetalState {
            let bottom = island.maxY - 1
            let x0 = island.minX + island.width * CGFloat(abs(sin(seed * 7.3)))
            return PetalState(
                center: CGPoint(
                    x: x0 + CGFloat(sin(p * .pi * 2 * 1.2 + seed) * 7 + p * 14),
                    y: bottom + 4 + CGFloat(p) * (drop - 12)),
                rotation: p * .pi * 3 * (index.isMultiple(of: 2) ? 1 : -1) + seed,
                scaleY: 0.55 + 0.45 * abs(sin(p * .pi * 4 + seed)),
                opacity: min(1, p / 0.12) * min(1, (1 - p) / 0.35))
        }
    }

    struct PetalState: Equatable {
        let center: CGPoint
        let rotation: Double
        let scaleY: Double
        let opacity: Double
    }
}

// MARK: - Polyline

/// A path flattened into points as it is built (quadratic curves into 16
/// segments, cubic into 24), with arc-length sampling.
struct Polyline: Equatable {
    private(set) var points: [CGPoint]

    init(start: CGPoint) { points = [start] }

    mutating func addLine(to point: CGPoint) { points.append(point) }

    mutating func addQuadCurve(to end: CGPoint, control: CGPoint) {
        let start = points[points.count - 1]
        for step in 1...16 {
            let u = CGFloat(step) / 16
            let v = 1 - u
            points.append(
                CGPoint(
                    x: v * v * start.x + 2 * v * u * control.x + u * u * end.x,
                    y: v * v * start.y + 2 * v * u * control.y + u * u * end.y))
        }
    }

    mutating func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        let start = points[points.count - 1]
        for step in 1...24 {
            let u = CGFloat(step) / 24
            let v = 1 - u
            points.append(
                CGPoint(
                    x: v * v * v * start.x + 3 * v * v * u * control1.x + 3 * v * u * u * control2.x + u * u * u
                        * end.x,
                    y: v * v * v * start.y + 3 * v * v * u * control1.y + 3 * v * u * u * control2.y + u * u * u
                        * end.y))
        }
    }

    var cgPath: CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        return path
    }

    struct Sample: Equatable {
        let point: CGPoint
        /// Direction of travel at `point`, in radians.
        let angle: CGFloat
    }

    /// Points every `spacing` along the line, with the local direction.
    func samples(spacing: CGFloat) -> [Sample] {
        guard points.count > 1, spacing > 0 else { return [] }
        var result: [Sample] = []
        var carried: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            var distance = spacing - carried
            while distance <= length {
                let u = distance / length
                result.append(Sample(point: CGPoint(x: a.x + dx * u, y: a.y + dy * u), angle: atan2(dy, dx)))
                distance += spacing
            }
            carried = length - (distance - spacing)
        }
        return result
    }
}
