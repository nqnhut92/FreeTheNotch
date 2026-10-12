import SwiftUI

// Hand-drawn sparkline, ported from Vorssaint's Sparkline + GraphCeilingLabel
// (vorssaint/vorssaint-utils, GPL-3.0-or-later): the data spans the full
// height, the fill closes to the baseline, the zero baseline sits between
// fill and line, and the ceiling label straddles a dashed rule at the top.
struct PanelSparkline: View {
    var values: [Double]
    var color: Color
    /// Fixed ceiling (e.g. 1.0 for percent graphs). Nil = autoscale to peak.
    var maxValue: Double?
    var height: CGFloat = 30
    var fillOpacity: Double = 0.16
    var showsZeroBaseline: Bool = true
    /// Scale label at the top-left for auto-scaled graphs, e.g. "20 KB/s", "50 W".
    var ceilingLabel: String?

    var body: some View {
        SparklineShape(
            values: values, color: color, maxValue: maxValue,
            fillOpacity: fillOpacity, showsZeroBaseline: showsZeroBaseline
        )
        .frame(height: height)
        .graphCeilingLabel(ceilingLabel)
    }
}

/// Two overlaid sparklines sharing one ceiling, for fair down/up comparison.
/// Download/read is drawn first (bottom, 0.16 fill + baseline), upload/write
/// on top (0.08 fill), as in Vorssaint's Network and Disk sections.
struct PanelDualSparkline: View {
    var first: [Double]
    var firstColor: Color
    var second: [Double]
    var secondColor: Color
    /// Ceiling for both series. Nil = autoscale to the joint peak.
    var maxValue: Double?
    var height: CGFloat = 30
    var ceilingLabel: String?

    private var jointCeiling: Double {
        if let maxValue { return maxValue }
        return max(first.max() ?? 0, second.max() ?? 0, 0.0001)
    }

    var body: some View {
        ZStack {
            SparklineShape(
                values: first, color: firstColor, maxValue: jointCeiling,
                fillOpacity: 0.16, showsZeroBaseline: true)
            SparklineShape(
                values: second, color: secondColor, maxValue: jointCeiling,
                fillOpacity: 0.08, showsZeroBaseline: false)
        }
        .frame(height: height)
        .graphCeilingLabel(ceilingLabel)
    }
}

private struct SparklineShape: View {
    var values: [Double]
    var color: Color
    var maxValue: Double?
    var fillOpacity: Double
    var lineWidth: CGFloat = 1.5
    var showsZeroBaseline: Bool

    var body: some View {
        GeometryReader { geometry in
            let baselineY = max(0.5, geometry.size.height - 0.5)
            let points = points(in: geometry.size, baselineY: baselineY)
            if points.count >= 2 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: baselineY))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: baselineY))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(fillOpacity), color.opacity(0)],
                            startPoint: .top, endPoint: .bottom)
                    )
                    if showsZeroBaseline {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: baselineY))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: baselineY))
                        }
                        .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                    }
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize, baselineY: CGFloat) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let peak = max(maxValue ?? (values.max() ?? 1), 0.0001)
        let topY: CGFloat = 0.5
        let plotHeight = max(1, baselineY - topY)
        let lastIndex = values.count - 1
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(lastIndex)
            let normalized = min(1, max(0, value / peak))
            return CGPoint(x: x, y: baselineY - plotHeight * CGFloat(normalized))
        }
    }
}

extension View {
    /// Dashed rule at the top of the graph with its value centered on it, so
    /// the number reads as the scale and not as a sample.
    @ViewBuilder
    fileprivate func graphCeilingLabel(_ text: String?) -> some View {
        if let text {
            self
                .overlay {
                    GeometryReader { geometry in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0.5))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: 0.5))
                        }
                        .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                    .allowsHitTesting(false)
                }
                // Over the oldest samples, so the newest stay clear.
                .overlay(alignment: .topLeading) {
                    Text(text)
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.panelSecondary)
                        .padding(.horizontal, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                        .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                        .allowsHitTesting(false)
                }
        } else {
            self
        }
    }
}
