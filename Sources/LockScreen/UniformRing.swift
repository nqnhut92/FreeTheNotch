import SwiftUI

/// The lock screen's ring: the same arc for every widget, so battery,
/// AirPods, temperature and AQI line up exactly. Atoll-style: open at the
/// bottom (145° start, 250° sweep), with a marker dot at the end of the
/// progress arc.
struct UniformRing<Center: View>: View {
    let fraction: Double
    /// One colour, or a gradient along the arc. Never empty.
    let colors: [Color]
    let trackColor: Color
    let center: Center

    private static var startAngle: Double { 145 }
    private static var sweep: Double { 250 }
    private static var lineWidth: CGFloat { 6 }

    init(
        fraction: Double, color: Color, trackColor: Color = Color.white.opacity(0.22),
        @ViewBuilder center: () -> Center
    ) {
        self.init(fraction: fraction, gradientColors: [color], trackColor: trackColor, center: center)
    }

    init(
        fraction: Double, gradientColors: [Color], trackColor: Color = Color.white.opacity(0.22),
        @ViewBuilder center: () -> Center
    ) {
        self.fraction = fraction
        self.colors = gradientColors.isEmpty ? [.white] : gradientColors
        self.trackColor = trackColor
        self.center = center()
    }

    /// A single colour still needs two stops.
    private var gradient: AngularGradient {
        AngularGradient(
            colors: colors.count > 1 ? colors : colors + colors, center: .center,
            startAngle: .degrees(Self.startAngle), endAngle: .degrees(Self.startAngle + Self.sweep))
    }

    var body: some View {
        GeometryReader { proxy in
            let radius = (min(proxy.size.width, proxy.size.height) - Self.lineWidth) / 2
            let centerPoint = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radians = (Self.startAngle + Self.sweep * fraction) * .pi / 180
            let marker = CGPoint(
                x: centerPoint.x + radius * cos(radians),
                y: centerPoint.y + radius * sin(radians)
            )
            let stroke = StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)

            ZStack {
                ArcShape(startAngle: Self.startAngle, sweep: Self.sweep, lineWidth: Self.lineWidth)
                    .stroke(trackColor, style: stroke)
                ArcShape(startAngle: Self.startAngle, sweep: Self.sweep * fraction, lineWidth: Self.lineWidth)
                    .stroke(gradient, style: stroke)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.22), lineWidth: 0.5))
                    .frame(width: Self.lineWidth + 2.5, height: Self.lineWidth + 2.5)
                    .position(marker)
                center
            }
        }
        .animation(.easeInOut(duration: 0.35), value: fraction)
    }
}

/// An arc of the ring. The sweep animates, so the arc grows and shrinks
/// with the marker instead of snapping.
private struct ArcShape: Shape {
    let startAngle: Double
    var sweep: Double
    let lineWidth: CGFloat

    var animatableData: Double {
        get { sweep }
        set { sweep = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: (min(rect.width, rect.height) - lineWidth) / 2,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweep),
            clockwise: false
        )
        return path
    }
}
