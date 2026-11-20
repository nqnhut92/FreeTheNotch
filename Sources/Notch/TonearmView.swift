import SwiftUI

/// The tonearm. It rests off the record while paused and lies on it while playing. Dragging it onto or off the
/// record plays or pauses; a click toggles.
struct TonearmView: View {
    static let coordinateSpaceName = "turntable"

    let isPlaying: Bool
    let setPlaying: (Bool) -> Void

    @State private var angle = TonearmGeometry.restingAngle
    @State private var isDragging = false

    private static let armWidth = 6.5
    private static let hitWidth = 36.0
    private static let dragThreshold = 3.0
    private static let settle = Animation.spring(duration: 0.6, bounce: 0.15)
    private static let pivotOuterDiameter = 44.0
    private static let pivotMidDiameter = 32.0
    private static let pivotCapDiameter = 22.0
    private static let counterweightWidth = 14.0
    private static let counterweightLength = 15.0
    private static let counterweightOffset = 20.0
    private static let headshellWidth = 14.5
    private static let headshellLength = 26.0
    private static let collarWidth = 8.5
    private static let collarLength = 6.0

    private var pivot: CGPoint { TonearmGeometry.pivot }
    private var stylus: CGPoint { TonearmGeometry.stylus }

    /// Length of the arm from pivot to stylus in the 300 × 300 canvas.
    private var armLength: Double {
        hypot(stylus.x - pivot.x, stylus.y - pivot.y)
    }

    /// Clockwise angle in degrees from straight down (+y) to the playing arm axis.
    private var baseAxisDegrees: Double {
        atan2(pivot.x - stylus.x, stylus.y - pivot.y) * 180 / .pi
    }

    private var isLowered: Bool {
        TonearmGeometry.isOnRecord(angle)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            pivotBase
                .position(pivot)

            armAssembly
                .frame(width: TonearmGeometry.canvasSide, height: TonearmGeometry.canvasSide, alignment: .topLeading)
                .contentShape(armPath.strokedPath(StrokeStyle(lineWidth: Self.hitWidth, lineCap: .round)))
                .modifier(GrabPointerStyle(isDragging: isDragging))
                .gesture(drag)
                .rotationEffect(
                    .degrees(angle),
                    anchor: UnitPoint(
                        x: pivot.x / TonearmGeometry.canvasSide,
                        y: pivot.y / TonearmGeometry.canvasSide
                    )
                )
        }
        .frame(width: TonearmGeometry.canvasSide, height: TonearmGeometry.canvasSide, alignment: .topLeading)
        .onAppear { angle = playingAngle(isPlaying) }
        .onChange(of: isPlaying) { _, playing in
            guard !isDragging else { return }
            withAnimation(Self.settle) { angle = playingAngle(playing) }
        }
        .accessibilityElement()
        .accessibilityLabel("Tonearm")
        .accessibilityValue(isPlaying ? "On the record" : "Lifted")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { setPlaying(!isPlaying) }
    }

    /// Stationary machined-aluminum gimbal base plate mounted at the pivot.
    private var pivotBase: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(white: 0.88),
                            Color(white: 0.66),
                            Color(white: 0.94),
                            Color(white: 0.60),
                            Color(white: 0.88),
                        ],
                        center: .center
                    )
                )
                .overlay(Circle().stroke(Color.black.opacity(0.28), lineWidth: 1.0))
                .frame(width: Self.pivotOuterDiameter, height: Self.pivotOuterDiameter)
                .shadow(color: Color.black.opacity(0.26), radius: 5, x: 1, y: 3)

            Circle()
                .stroke(Color.black.opacity(0.18), lineWidth: 1.0)
                .frame(width: Self.pivotMidDiameter, height: Self.pivotMidDiameter)
        }
    }

    /// Rotating arm assembly: counterweight, brushed tube, headshell, and central gimbal cap.
    private var armAssembly: some View {
        ZStack {
            // Oriented along the arm axis with origin at pivot (0, 0) and stylus at (0, +armLength).
            ZStack {
                counterweight
                    .offset(y: -Self.counterweightOffset)

                armTube
                    .offset(y: (armLength - Self.headshellLength / 2 - Self.counterweightOffset) / 2)

                collar
                    .offset(y: armLength - Self.headshellLength / 2 - Self.collarLength / 2)

                headshell
                    .offset(y: armLength)
            }
            .rotationEffect(.degrees(baseAxisDegrees))
            .shadow(
                color: Color.black.opacity(isLowered ? 0.36 : 0.22),
                radius: isLowered ? 4.0 : 8.0,
                x: isLowered ? 3.0 : 7.0,
                y: isLowered ? 5.0 : 10.0
            )

            pivotCap
        }
        .position(pivot)
    }

    private var counterweight: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(metallicHorizontalGradient)
                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.black.opacity(0.24), lineWidth: 0.6))
                .frame(width: Self.counterweightWidth, height: Self.counterweightLength)
            Rectangle()
                .fill(Color(white: 0.16))
                .frame(width: Self.counterweightWidth - 2, height: 2.5)
        }
    }

    private var armTube: some View {
        let totalLength = armLength - Self.headshellLength / 2 + Self.counterweightOffset
        return Capsule()
            .fill(metallicHorizontalGradient)
            .overlay(Capsule().stroke(Color.black.opacity(0.16), lineWidth: 0.5))
            .frame(width: Self.armWidth, height: totalLength)
    }

    private var collar: some View {
        RoundedRectangle(cornerRadius: 1.2)
            .fill(metallicHorizontalGradient)
            .overlay(RoundedRectangle(cornerRadius: 1.2).stroke(Color.black.opacity(0.28), lineWidth: 0.5))
            .frame(width: Self.collarWidth, height: Self.collarLength)
    }

    private var headshell: some View {
        ZStack(alignment: .trailing) {
            // Finger lift lever protruding to the right side of the cartridge.
            Capsule()
                .fill(Color(white: 0.16))
                .frame(width: 11, height: 2.2)
                .offset(x: 9, y: 2)

            // Matte-black cartridge body with subtle top-left sheen and two silver mounting screws.
            RoundedRectangle(cornerRadius: 2.5)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.24), Color(white: 0.12), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                )
                .frame(width: Self.headshellWidth, height: Self.headshellLength)

            HStack(spacing: 4.5) {
                Circle().fill(Color(white: 0.72)).frame(width: 2.2, height: 2.2)
                Circle().fill(Color(white: 0.72)).frame(width: 2.2, height: 2.2)
            }
            .frame(width: Self.headshellWidth)
            .offset(y: 4)
        }
    }

    private var pivotCap: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [
                        Color(white: 0.94),
                        Color(white: 0.68),
                        Color(white: 0.98),
                        Color(white: 0.62),
                        Color(white: 0.94),
                    ],
                    center: .center
                )
            )
            .overlay(Circle().stroke(Color.black.opacity(0.26), lineWidth: 0.8))
            .frame(width: Self.pivotCapDiameter, height: Self.pivotCapDiameter)
            .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0.5, y: 1.5)
    }

    private var metallicHorizontalGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(white: 0.58),
                Color(white: 0.96),
                Color(white: 0.78),
                Color(white: 0.48),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var armPath: Path {
        Path { path in
            path.move(to: pivot)
            path.addLine(to: stylus)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                guard hypot(value.translation.width, value.translation.height) > Self.dragThreshold else { return }
                isDragging = true
                angle = TonearmGeometry.angle(pointingAt: value.location)
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) > Self.dragThreshold
                isDragging = false
                if moved {
                    let lowered = TonearmGeometry.isOnRecord(angle)
                    withAnimation(Self.settle) { angle = playingAngle(lowered) }
                    setPlaying(lowered)
                } else {
                    setPlaying(!isPlaying)
                }
            }
    }

    private func playingAngle(_ playing: Bool) -> Double {
        playing ? TonearmGeometry.playingAngle : TonearmGeometry.restingAngle
    }
}

/// The grab cursor on the arm; `pointerStyle` needs macOS 15, so older systems keep the arrow.
private struct GrabPointerStyle: ViewModifier {
    let isDragging: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(isDragging ? .grabActive : .grabIdle)
        } else {
            content
        }
    }
}
