// Skin decorations: our own drawings (not in Atoll), no image assets.

import SwiftUI

/// Vines, Christmas lights or falling blossoms around the island, drawn with
/// Canvas (no image assets). Animates at 30 fps; still with Reduce Motion.
struct SkinDecorationView: View {
    let decoration: SkinDecoration
    let shapeSize: CGSize
    /// Settings previews pass true while their window is in the background.
    var isPaused = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room around the island the drawing may use.
    private static let sideMargin: CGFloat = 16
    private static let drop: CGFloat = 90

    var body: some View {
        let canvasSize = CGSize(
            width: shapeSize.width + Self.sideMargin * 2,
            height: shapeSize.height + Self.drop)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || isPaused)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                let island = CGRect(x: Self.sideMargin, y: 0, width: shapeSize.width, height: shapeSize.height)
                switch decoration {
                case .vines: Self.drawVines(ctx, island: island, t: t)
                case .lights: Self.drawLights(ctx, island: island, t: t)
                case .blossoms: Self.drawBlossoms(ctx, island: island, t: t)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
    }

    // MARK: Vines

    private static let leafDark = Color(red: 0.16, green: 0.5, blue: 0.2)
    private static let leafLight = Color(red: 0.42, green: 0.78, blue: 0.3)
    private static let stem = Color(red: 0.2, green: 0.38, blue: 0.14)

    private static func drawVines(_ ctx: GraphicsContext, island: CGRect, t: Double) {
        let bottom = island.maxY - 1.5
        let r: CGFloat = 14

        // Vine along the bottom edge, sagging slightly, curling up both sides.
        var edge = Path()
        edge.move(to: CGPoint(x: island.minX + 1, y: island.minY + island.height * 0.35))
        edge.addQuadCurve(
            to: CGPoint(x: island.minX + r, y: bottom + 1),
            control: CGPoint(x: island.minX - 1, y: bottom))
        edge.addCurve(
            to: CGPoint(x: island.maxX - r, y: bottom + 1),
            control1: CGPoint(x: island.minX + island.width * 0.35, y: bottom + 6),
            control2: CGPoint(x: island.minX + island.width * 0.65, y: bottom + 6))
        edge.addQuadCurve(
            to: CGPoint(x: island.maxX - 1, y: island.minY + island.height * 0.35),
            control: CGPoint(x: island.maxX + 1, y: bottom))
        ctx.stroke(edge, with: .color(stem), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        drawLeaves(ctx, along: edge, spacing: 11, size: 6.5, t: t, seed: 1)

        // Strands hanging from the edge, longest at the corners.
        let strands: [(x: CGFloat, length: CGFloat, phase: Double)] = [
            (0.04, 46, 0.0), (0.2, 24, 1.3), (0.5, 16, 2.1), (0.83, 32, 0.7), (0.97, 54, 2.6),
        ]
        for (i, s) in strands.enumerated() {
            let x = island.minX + island.width * s.x
            let start = CGPoint(x: x, y: bottom + (s.x > 0.1 && s.x < 0.9 ? 4 : 0))
            var strand = Path()
            strand.move(to: start)
            let steps = 12
            for step in 1...steps {
                let p = CGFloat(step) / CGFloat(steps)
                let sway = sin(t * 0.9 + s.phase) * 5 * pow(p, 1.4)
                strand.addLine(
                    to: CGPoint(
                        x: start.x + sway + sin(p * 5 + CGFloat(i)) * 1.5,
                        y: start.y + s.length * p))
            }
            ctx.stroke(
                strand, with: .color(stem), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            drawLeaves(ctx, along: strand, spacing: 7.5, size: 5.5, t: t, seed: Double(i) + 3)
        }
    }

    /// Leaves alternating left/right along a path, gently fluttering.
    private static func drawLeaves(
        _ ctx: GraphicsContext, along path: Path, spacing: CGFloat,
        size: CGFloat, t: Double, seed: Double
    ) {
        let points = sample(path, spacing: spacing)
        for (i, sample) in points.enumerated() where i > 0 {
            let side: CGFloat = i.isMultiple(of: 2) ? 1 : -1
            let flutter = sin(t * 2.2 + Double(i) * 0.8 + seed) * 0.18
            let angle = sample.angle + side * (.pi / 3.2) + flutter
            let scale = 0.75 + 0.35 * CGFloat(abs(sin(Double(i) * 1.7 + seed)))
            var leaf = ctx
            leaf.translateBy(x: sample.point.x, y: sample.point.y)
            leaf.rotate(by: .radians(angle))
            let w = size * scale * 1.5
            let h = size * scale * 0.8
            var shape = Path()
            shape.move(to: .zero)
            shape.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w * 0.5, y: -h))
            shape.addQuadCurve(to: .zero, control: CGPoint(x: w * 0.5, y: h))
            leaf.fill(
                shape,
                with: .linearGradient(
                    Gradient(colors: [leafDark, leafLight]),
                    startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
            var vein = Path()
            vein.move(to: CGPoint(x: w * 0.1, y: 0))
            vein.addLine(to: CGPoint(x: w * 0.85, y: 0))
            leaf.stroke(vein, with: .color(stem.opacity(0.6)), lineWidth: 0.5)
        }
    }

    // MARK: Christmas lights

    private static let bulbColors: [Color] = [
        Color(red: 1, green: 0.25, blue: 0.25), Color(red: 0.25, green: 0.9, blue: 0.4),
        Color(red: 1, green: 0.82, blue: 0.2), Color(red: 0.3, green: 0.6, blue: 1),
        Color(red: 1, green: 0.45, blue: 0.85),
    ]

    private static func drawLights(_ ctx: GraphicsContext, island: CGRect, t: Double) {
        let bottom = island.maxY - 2
        // Start inside the rounded corners so the wire touches the island.
        let left = island.minX + 12
        let right = island.maxX - 12
        let swags = max(3, Int((right - left) / 46))
        let swagWidth = (right - left) / CGFloat(swags)
        var wire = Path()
        wire.move(to: CGPoint(x: left, y: bottom))
        var bulbs: [(CGPoint, CGFloat)] = []
        for i in 0..<swags {
            let x0 = left + CGFloat(i) * swagWidth
            let x1 = x0 + swagWidth
            let sag: CGFloat = 10
            wire.addQuadCurve(to: CGPoint(x: x1, y: bottom), control: CGPoint(x: (x0 + x1) / 2, y: bottom + sag * 2))
            // Bulbs on the swag (quadratic: y = bottom + sag * 4p(1-p)).
            for p in [0.2, 0.5, 0.8] as [CGFloat] {
                let x = x0 + swagWidth * p
                let y = bottom + sag * 4 * p * (1 - p)
                let slope = sag * 4 * (1 - 2 * p) / swagWidth
                bulbs.append((CGPoint(x: x, y: y), atan(slope)))
            }
        }
        // Short drops from both corners.
        for x in [left, right] {
            wire.move(to: CGPoint(x: x, y: bottom))
            wire.addLine(to: CGPoint(x: x, y: bottom + 12))
            bulbs.append((CGPoint(x: x, y: bottom + 12), 0))
        }
        ctx.stroke(
            wire, with: .color(Color(red: 0.12, green: 0.25, blue: 0.12)),
            style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

        for (i, bulb) in bulbs.enumerated() {
            let color = bulbColors[i % bulbColors.count]
            let twinkle = 0.55 + 0.45 * sin(t * 2.6 + Double(i) * 1.9)
            var b = ctx
            b.translateBy(x: bulb.0.x, y: bulb.0.y)
            b.rotate(by: .radians(bulb.1))
            // Glow.
            b.fill(
                Path(ellipseIn: CGRect(x: -8, y: -2, width: 16, height: 18)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.55 * twinkle), color.opacity(0)]),
                    center: CGPoint(x: 0, y: 7), startRadius: 0, endRadius: 9))
            // Cap and bulb.
            b.fill(
                Path(roundedRect: CGRect(x: -1.8, y: 0, width: 3.6, height: 3), cornerRadius: 0.8),
                with: .color(Color(white: 0.35)))
            b.fill(
                Path(ellipseIn: CGRect(x: -2.8, y: 2.4, width: 5.6, height: 7.5)),
                with: .color(color.opacity(0.45 + 0.55 * twinkle)))
            b.fill(
                Path(ellipseIn: CGRect(x: -1.2, y: 3.6, width: 1.6, height: 2.4)),
                with: .color(.white.opacity(0.7 * twinkle)))
        }
    }

    // MARK: Sakura

    private static let petalPink = Color(red: 1, green: 0.72, blue: 0.8)
    private static let petalDeep = Color(red: 0.96, green: 0.5, blue: 0.64)

    private static func drawBlossoms(_ ctx: GraphicsContext, island: CGRect, t: Double) {
        let bottom = island.maxY - 1
        // A twig along the right half of the bottom edge with flowers on it.
        var twig = Path()
        let start = CGPoint(x: island.maxX + 6, y: island.minY + island.height * 0.45)
        twig.move(to: start)
        twig.addCurve(
            to: CGPoint(x: island.minX + island.width * 0.45, y: bottom + 5),
            control1: CGPoint(x: island.maxX - 2, y: bottom + 6),
            control2: CGPoint(x: island.minX + island.width * 0.7, y: bottom + 2))
        var shoot = Path()
        shoot.move(to: CGPoint(x: island.maxX - 16, y: bottom + 3))
        shoot.addQuadCurve(
            to: CGPoint(x: island.maxX - 30, y: bottom + 20),
            control: CGPoint(x: island.maxX - 18, y: bottom + 14))
        let bark = Color(red: 0.36, green: 0.22, blue: 0.16)
        ctx.stroke(twig, with: .color(bark), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        ctx.stroke(shoot, with: .color(bark), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        for (i, s) in sample(twig, spacing: 15).enumerated() where i > 0 {
            drawFlower(
                ctx, at: CGPoint(x: s.point.x, y: s.point.y + (i.isMultiple(of: 2) ? 3 : -1)),
                size: i.isMultiple(of: 3) ? 4.5 : 3.6, rotation: Double(i) * 0.9 + sin(t * 0.8 + Double(i)) * 0.08)
        }
        drawFlower(ctx, at: CGPoint(x: island.maxX - 30, y: bottom + 20), size: 4.2, rotation: 0.4)
        drawFlower(ctx, at: CGPoint(x: island.maxX - 22, y: bottom + 12), size: 3.4, rotation: 1.1)

        // Falling petals: deterministic particles, each on its own loop.
        for i in 0..<14 {
            let seed = Double(i) * 12.9898
            let period = 5.5 + (sin(seed) + 1) * 2.5
            let p = ((t + abs(sin(seed * 3.1)) * period).truncatingRemainder(dividingBy: period)) / period
            let x0 = island.minX + island.width * CGFloat(abs(sin(seed * 7.3)))
            let x = x0 + CGFloat(sin(p * .pi * 2 * 1.2 + seed) * 7 + p * 14)
            let y = bottom + 4 + CGFloat(p) * (drop - 12)
            let fade = min(1, p / 0.12) * min(1, (1 - p) / 0.35)
            var petal = ctx
            petal.opacity = fade
            petal.translateBy(x: x, y: y)
            petal.rotate(by: .radians(p * .pi * 3 * (i.isMultiple(of: 2) ? 1 : -1) + seed))
            petal.scaleBy(x: 1, y: 0.55 + 0.45 * abs(sin(p * .pi * 4 + seed)))
            petal.fill(
                petalPath(size: 4.2),
                with: .linearGradient(
                    Gradient(colors: [petalPink, petalDeep]),
                    startPoint: CGPoint(x: 0, y: -4),
                    endPoint: CGPoint(x: 0, y: 4)))
        }
    }

    private static func petalPath(size: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size))
        path.addQuadCurve(to: CGPoint(x: -size * 0.3, y: -size), control: CGPoint(x: -size, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -size * 0.7))
        path.addLine(to: CGPoint(x: size * 0.3, y: -size))
        path.addQuadCurve(to: CGPoint(x: 0, y: size), control: CGPoint(x: size, y: 0))
        return path
    }

    private static func drawFlower(_ ctx: GraphicsContext, at point: CGPoint, size: CGFloat, rotation: Double) {
        var f = ctx
        f.translateBy(x: point.x, y: point.y)
        f.rotate(by: .radians(rotation))
        for k in 0..<5 {
            var petal = f
            petal.rotate(by: .degrees(Double(k) * 72))
            petal.translateBy(x: 0, y: -size * 0.9)
            petal.fill(
                petalPath(size: size * 0.75), with: .color(k.isMultiple(of: 2) ? petalPink : petalPink.opacity(0.9)))
        }
        f.fill(
            Path(ellipseIn: CGRect(x: -size * 0.32, y: -size * 0.32, width: size * 0.64, height: size * 0.64)),
            with: .color(petalDeep))
        f.fill(
            Path(ellipseIn: CGRect(x: -size * 0.14, y: -size * 0.14, width: size * 0.28, height: size * 0.28)),
            with: .color(Color(red: 1, green: 0.88, blue: 0.4)))
    }

    // MARK: Path sampling

    struct PathSample: Equatable {
        let point: CGPoint
        /// Direction of travel at `point`, in radians.
        let angle: CGFloat
    }

    /// Points every `spacing` along a path (curves flattened into short
    /// segments) with the local direction.
    static func sample(_ path: Path, spacing: CGFloat) -> [PathSample] {
        var points: [CGPoint] = []
        // Path is not a Sequence: forEach is its only element walk.
        // swift-format-ignore: ReplaceForEachWithForLoop
        path.forEach { element in
            switch element {
            case .move(let p): points.append(p)
            case .line(let p): points.append(p)
            case .quadCurve(let p, let c):
                let a = points.last ?? p
                for i in 1...16 {
                    let u = CGFloat(i) / 16
                    points.append(
                        CGPoint(
                            x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * c.x + u * u * p.x,
                            y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * c.y + u * u * p.y))
                }
            case .curve(let p, let c1, let c2):
                let a = points.last ?? p
                for i in 1...24 {
                    let u = CGFloat(i) / 24
                    let v = 1 - u
                    points.append(
                        CGPoint(
                            x: v * v * v * a.x + 3 * v * v * u * c1.x + 3 * v * u * u * c2.x + u * u * u * p.x,
                            y: v * v * v * a.y + 3 * v * v * u * c1.y + 3 * v * u * u * c2.y + u * u * u * p.y))
                }
            case .closeSubpath: break
            }
        }
        guard points.count > 1 else { return [] }
        var result: [PathSample] = []
        var carried: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            var d = spacing - carried
            while d <= length {
                let u = d / length
                result.append(PathSample(point: CGPoint(x: a.x + dx * u, y: a.y + dy * u), angle: atan2(dy, dx)))
                d += spacing
            }
            carried = length - (d - spacing)
        }
        return result
    }
}
