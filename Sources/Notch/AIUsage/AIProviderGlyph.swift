import SwiftUI

/// Vector provider marks drawn in SwiftUI so no third-party logo assets are bundled.
struct AIProviderGlyph: View {
    let provider: AIUsageProvider

    private static let frameSize: CGFloat = 26
    private static let claudeSize: CGFloat = 20
    private static let codexSize: CGFloat = 19
    private static let codexStrokeWidth: CGFloat = 1.45

    var body: some View {
        Group {
            switch provider {
            case .claude:
                ClaudeSunburstShape()
                    .fill()
                    .frame(width: Self.claudeSize, height: Self.claudeSize)
            case .codex:
                CodexBlossomShape()
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: Self.codexStrokeWidth, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: Self.codexSize, height: Self.codexSize)
            }
        }
        .frame(width: Self.frameSize, height: Self.frameSize)
    }
}

/// Filled 12-ray sunburst matching Claude's rounded-petal mark.
private struct ClaudeSunburstShape: Shape {
    private static let hubRadiusRatio: CGFloat = 0.14
    private static let baseHalfWidthRatio: CGFloat = 0.058
    private static let tipRadiusRatio: CGFloat = 0.042

    /// Angle (degrees from top) and length ratio for each of the 12 rays.
    private static let rays: [(angle: Double, length: CGFloat)] = [
        (0, 0.47),
        (30, 0.42),
        (62, 0.46),
        (92, 0.41),
        (120, 0.47),
        (151, 0.43),
        (180, 0.46),
        (210, 0.41),
        (241, 0.47),
        (271, 0.42),
        (300, 0.46),
        (331, 0.43),
    ]

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let hubRadius = size * Self.hubRadiusRatio
        let baseHalf = size * Self.baseHalfWidthRatio
        let tipRadius = size * Self.tipRadiusRatio

        var path = Path()
        path.addEllipse(
            in: CGRect(
                x: center.x - hubRadius, y: center.y - hubRadius,
                width: hubRadius * 2, height: hubRadius * 2))

        for ray in Self.rays {
            let theta = (ray.angle - 90) * .pi / 180
            let dir = CGVector(dx: cos(theta), dy: sin(theta))
            let perp = CGVector(dx: -dir.dy, dy: dir.dx)
            let tipCenter = CGPoint(
                x: center.x + dir.dx * (size * ray.length - tipRadius),
                y: center.y + dir.dy * (size * ray.length - tipRadius))
            let startLeft = CGPoint(
                x: center.x + dir.dx * (hubRadius * 0.6) + perp.dx * baseHalf,
                y: center.y + dir.dy * (hubRadius * 0.6) + perp.dy * baseHalf)
            let startRight = CGPoint(
                x: center.x + dir.dx * (hubRadius * 0.6) - perp.dx * baseHalf,
                y: center.y + dir.dy * (hubRadius * 0.6) - perp.dy * baseHalf)
            let tipRight = CGPoint(
                x: tipCenter.x - perp.dx * tipRadius,
                y: tipCenter.y - perp.dy * tipRadius)
            let tipApex = CGPoint(
                x: tipCenter.x + dir.dx * tipRadius,
                y: tipCenter.y + dir.dy * tipRadius)
            let tipLeft = CGPoint(
                x: tipCenter.x + perp.dx * tipRadius,
                y: tipCenter.y + perp.dy * tipRadius)

            path.move(to: startLeft)
            path.addLine(to: tipLeft)
            path.addQuadCurve(
                to: tipApex, control: CGPoint(x: tipLeft.x + dir.dx * tipRadius, y: tipLeft.y + dir.dy * tipRadius))
            path.addQuadCurve(
                to: tipRight, control: CGPoint(x: tipRight.x + dir.dx * tipRadius, y: tipRight.y + dir.dy * tipRadius))
            path.addLine(to: startRight)
            path.closeSubpath()
        }
        return path
    }
}

/// Six-petal hexagonal knot matching OpenAI / Codex's geometric blossom.
private struct CodexBlossomShape: Shape {
    private static let petalCount = 6
    private static let innerRadiusRatio: CGFloat = 0.125
    private static let legLengthRatio: CGFloat = 0.23

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let innerRadius = size * Self.innerRadiusRatio
        let legLength = size * Self.legLengthRatio
        let arcRadius = innerRadius * CGFloat(sqrt(3.0)) / 2

        var path = Path()
        for index in 0..<Self.petalCount {
            let baseAngle = Double(index) * (.pi / 3)
            let start = CGPoint(
                x: center.x + innerRadius * CGFloat(cos(baseAngle)),
                y: center.y + innerRadius * CGFloat(sin(baseAngle)))
            let dirAngle = baseAngle + (.pi / 3)
            let dir = CGVector(dx: cos(dirAngle), dy: sin(dirAngle))
            let outward = CGVector(dx: dir.dy, dy: -dir.dx)

            let outerStart = CGPoint(
                x: start.x + dir.dx * legLength,
                y: start.y + dir.dy * legLength)
            let arcCenter = CGPoint(
                x: outerStart.x + outward.dx * arcRadius,
                y: outerStart.y + outward.dy * arcRadius)
            let arcEnd = CGPoint(
                x: arcCenter.x + outward.dx * arcRadius,
                y: arcCenter.y + outward.dy * arcRadius)
            let returnEnd = CGPoint(
                x: arcEnd.x - dir.dx * (legLength + innerRadius * 0.5),
                y: arcEnd.y - dir.dy * (legLength + innerRadius * 0.5))

            path.move(to: start)
            path.addLine(to: outerStart)
            path.addArc(
                center: arcCenter,
                radius: arcRadius,
                startAngle: Angle(radians: dirAngle + .pi / 2),
                endAngle: Angle(radians: dirAngle - .pi / 2),
                clockwise: true)
            path.addLine(to: returnEnd)
        }
        return path
    }
}
