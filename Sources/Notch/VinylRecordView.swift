import SwiftUI

/// A vinyl record on a brushed-aluminum platter with the song's artwork as its label.
/// The record and label turn while `isSpinning`; the platter, diagonal light sheen and center spindle stay fixed.
struct VinylRecordView: View {
    let artwork: NSImage?
    let isSpinning: Bool

    @State private var spin = VinylSpin()

    private static let platterShadowOpacity = 0.30
    private static let platterShadowRadius = 10.0
    private static let platterShadowOffsetY = 5.0
    private static let platterInnerBevelScale = 0.962
    private static let vinylScale = 0.946
    private static let grooveInnerScale = 0.485
    private static let grooveOuterScale = 0.922
    private static let grooveCount = 34
    private static let trackGapIndices: Set<Int> = [11, 23]
    private static let labelScale = 0.43
    private static let labelInnerRingScale = 0.38
    private static let labelSpindleWellScale = 0.135
    private static let spindleScale = 0.056
    private static let labelMarkScale = 0.09
    private static let labelMarkOffset = 0.30

    var body: some View {
        GeometryReader { proxy in
            let diameter = proxy.size.width
            ZStack {
                platterRim(diameter: diameter)
                TimelineView(.animation(paused: !isSpinning)) { timeline in
                    spinningDisc(diameter: diameter)
                        .rotationEffect(.degrees(spin.angle(at: timeline.date)))
                }
                staticLighting(diameter: diameter)
                spindle(diameter: diameter * Self.spindleScale)
            }
            .frame(width: diameter, height: diameter)
        }
        .onAppear { spin.setSpinning(isSpinning, at: .now) }
        .onChange(of: isSpinning) { _, spinning in spin.setSpinning(spinning, at: .now) }
        .accessibilityHidden(true)
    }

    /// Stationary brushed-aluminum platter rim underneath the vinyl.
    private func platterRim(diameter: Double) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.93),
                            Color(white: 0.78),
                            Color(white: 0.62),
                            Color(white: 0.76),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.8))
                .shadow(
                    color: Color.black.opacity(Self.platterShadowOpacity),
                    radius: Self.platterShadowRadius,
                    x: 0,
                    y: Self.platterShadowOffsetY
                )

            Circle()
                .fill(Color(white: 0.14))
                .frame(
                    width: diameter * Self.platterInnerBevelScale,
                    height: diameter * Self.platterInnerBevelScale
                )
        }
        .frame(width: diameter, height: diameter)
    }

    /// The rotating black vinyl body, micro-grooves, and album artwork label.
    private func spinningDisc(diameter: Double) -> some View {
        let vinylDiameter = diameter * Self.vinylScale
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.10), Color(white: 0.065), Color(white: 0.05)],
                        center: .center,
                        startRadius: vinylDiameter * 0.2,
                        endRadius: vinylDiameter * 0.5
                    )
                )
                .frame(width: vinylDiameter, height: vinylDiameter)

            grooves(diameter: diameter)
            label(diameter: diameter * Self.labelScale)
        }
        .frame(width: diameter, height: diameter)
    }

    /// Concentric micro-grooves with subtle track-divider gaps so the surface reads like pressed vinyl.
    private func grooves(diameter: Double) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let innerRadius = (diameter * Self.grooveInnerScale) / 2
            let outerRadius = (diameter * Self.grooveOuterScale) / 2
            let step = (outerRadius - innerRadius) / Double(Self.grooveCount)

            for index in 0...Self.grooveCount {
                if Self.trackGapIndices.contains(index) { continue }
                let radius = innerRadius + Double(index) * step
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                let brightness = index.isMultiple(of: 3) ? 0.15 : 0.08
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(brightness)),
                    lineWidth: 0.65
                )
            }

            // Subtle lead-out groove ring near the paper label.
            let runoutRadius = (diameter * (Self.labelScale + 0.028)) / 2
            let runoutRect = CGRect(
                x: center.x - runoutRadius,
                y: center.y - runoutRadius,
                width: runoutRadius * 2,
                height: runoutRadius * 2
            )
            context.stroke(
                Path(ellipseIn: runoutRect),
                with: .color(Color.white.opacity(0.11)),
                lineWidth: 0.7
            )
        }
        .frame(width: diameter, height: diameter)
    }

    private func label(diameter: Double) -> some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.accentColor
                    Circle()
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        .frame(
                            width: diameter * (Self.labelInnerRingScale / Self.labelScale),
                            height: diameter * (Self.labelInnerRingScale / Self.labelScale)
                        )
                    // A mark off the centre, so a turning record without artwork can be seen turning.
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: diameter * Self.labelMarkScale, height: diameter * Self.labelMarkScale)
                        .offset(y: -diameter * Self.labelMarkOffset)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.28), lineWidth: 1.2)
        )
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.14), lineWidth: 0.8)
                .frame(
                    width: diameter * (Self.labelSpindleWellScale / Self.labelScale),
                    height: diameter * (Self.labelSpindleWellScale / Self.labelScale)
                )
        )
    }

    /// Stationary diagonal light reflection across the grooves, matching top-left room lighting.
    private func staticLighting(diameter: Double) -> some View {
        let vinylDiameter = diameter * Self.vinylScale
        let grooveMaskWidth = (vinylDiameter - diameter * Self.labelScale) / 2
        let midGrooveDiameter = (vinylDiameter + diameter * Self.labelScale) / 2

        return ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .white.opacity(0.04), location: 0.06),
                            .init(color: .white.opacity(0.20), location: 0.12),
                            .init(color: .white.opacity(0.04), location: 0.19),
                            .init(color: .clear, location: 0.28),
                            .init(color: .clear, location: 0.50),
                            .init(color: .white.opacity(0.04), location: 0.56),
                            .init(color: .white.opacity(0.17), location: 0.62),
                            .init(color: .white.opacity(0.04), location: 0.69),
                            .init(color: .clear, location: 0.78),
                            .init(color: .clear, location: 1.00),
                        ],
                        center: .center,
                        angle: .degrees(-185)
                    ),
                    lineWidth: grooveMaskWidth
                )
                .frame(width: midGrooveDiameter, height: midGrooveDiameter)
                .blur(radius: 1.5)
                .clipShape(Circle().inset(by: (diameter - vinylDiameter) / 2))

            // Crisp top-left edge highlight on the vinyl rim.
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.clear, Color.black.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
                .frame(width: vinylDiameter, height: vinylDiameter)
        }
        .frame(width: diameter, height: diameter)
    }

    /// Stationary 3D brushed-silver center spindle.
    private func spindle(diameter: Double) -> some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [
                        Color(white: 0.88),
                        Color(white: 0.64),
                        Color(white: 0.96),
                        Color(white: 0.58),
                        Color(white: 0.88),
                    ],
                    center: .center
                )
            )
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.32), lineWidth: 0.8)
            )
            .frame(width: diameter, height: diameter)
            .shadow(color: Color.black.opacity(0.40), radius: 2, x: 1, y: 1.5)
    }
}
