// Ring and dot layout adapted from DuoBar (github.com/Mikeli7666/DuoBar), MIT:
// UI/DuoGlyphView.swift (DuoArcShape, DuoRingGeometry) and
// UI/DuoGlyphMetrics.swift (bottom-gap arc). Differences: the 5 dots are
// output volume and sit on the ring's own circle, the battery number cuts
// across the top of the ring, and the centre is the stock `wifi` symbol.

import SwiftUI

/// Live Duo indicator: observes battery, Wi-Fi and volume.
struct DuoGlyphView: View {
    @ObservedObject var battery: BatteryHUDController
    @ObservedObject var wifi: WiFiMonitor
    @ObservedObject var volume: OutputVolumeMonitor
    var scale: CGFloat = 1

    var body: some View {
        DuoGlyphCanvas(
            batteryLevel: Int(battery.level.rounded()),
            isCharging: battery.isCharging,
            isPluggedIn: battery.isPluggedIn,
            wifiBars: wifi.bars,
            volumeLevel: Double(volume.level),
            isMuted: volume.isMuted,
            scale: scale
        )
    }
}

/// Glance-only glyph. Uses the foreground style; only the charging (green)
/// and low-battery (red) ring are coloured.
struct DuoGlyphCanvas: View {
    let batteryLevel: Int
    let isCharging: Bool
    /// On power adapter. Plugged in but not charging = macOS "charging on
    /// hold" (charge limit, Optimized Charging, full): plug instead of bolt.
    var isPluggedIn = false
    /// 0 = Wi-Fi off or not associated (whole symbol dimmed), 1–3 = arcs lit.
    let wifiBars: Int
    let volumeLevel: Double
    let isMuted: Bool
    /// Drawn at this scale (vector), not stretched afterwards.
    var scale: CGFloat = 1
    /// Off for the Settings sidebar icon, where the number is too small to read.
    var showsNumber = true

    /// Size at scale 1.
    static let size = CGSize(width: 24, height: 22)

    // Geometry in points. The 96° bottom gap is the smallest that holds
    // 5 dots at 15° pitch with clear space to the ring's round caps.
    private static let center = CGPoint(x: 12, y: 12)
    private static let radius: CGFloat = 8.5
    private static let lineWidth: CGFloat = 1.6
    private static let gapDegrees: Double = 96
    private static let dotDiameter: CGFloat = 1.5
    private static let dotPitchDegrees: Double = 15
    private static let dimOpacity: Double = 0.3

    private var ringColor: Color? {
        if isCharging { return .green }
        if batteryLevel < 20, !isPluggedIn { return .red }
        return nil  // foreground style
    }

    /// 1 dot ≈ 20 %: any audible level lights at least one dot.
    private var activeDots: Int {
        guard !isMuted else { return 0 }
        return min(5, max(0, Int((volumeLevel * 5 - 0.001).rounded(.up))))
    }

    var body: some View {
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            let c = Self.center
            let r = Self.radius
            let start = 90 + Self.gapDegrees / 2
            let end = 450 - Self.gapDegrees / 2
            let shading: GraphicsContext.Shading = ringColor.map { .color($0) } ?? .foreground
            let stroke = StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)

            func arc(_ progress: Double) -> Path {
                var path = Path()
                // SwiftUI's y axis points down: `clockwise: false` sweeps
                // through 270° (the top), as DuoBar's DuoArcShape does.
                path.addArc(
                    center: c, radius: r, startAngle: .degrees(start),
                    endAngle: .degrees(start + (end - start) * progress), clockwise: false)
                return path
            }

            // Ring: dim track, then the battery level from bottom-left, clockwise.
            var track = context
            track.opacity = Self.dimOpacity
            track.stroke(arc(1), with: shading, style: stroke)
            let progress = min(max(Double(batteryLevel) / 100, 0), 1)
            if progress > 0 {
                context.stroke(arc(progress), with: shading, style: stroke)
            }

            // Battery number across the top of the ring (no % sign); the
            // bolt (charging) or plug (on hold) sits to the right of the number.
            // Green while charging, like the ring; on hold stays uncoloured.
            let number = context.resolve(
                Text("\(batteryLevel)").font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundColor(isCharging ? .green : nil)
            )
            let numberSize = number.measure(in: Self.size)
            let topY = c.y - r
            var label = CGRect(
                x: c.x - numberSize.width / 2, y: topY - numberSize.height / 2,
                width: numberSize.width, height: numberSize.height)
            let numberCenter = CGPoint(x: label.midX, y: label.midY)
            var boltRect: CGRect?
            let powerSymbol: SymbolID? = isCharging ? .bolt : (isPluggedIn ? .plug : nil)
            if let powerSymbol {
                let boltSize = powerSymbol == .bolt ? CGSize(width: 4, height: 5.5) : CGSize(width: 3.6, height: 5.5)
                let rect = CGRect(
                    x: label.maxX + 0.3, y: topY - boltSize.height / 2,
                    width: boltSize.width, height: boltSize.height)
                boltRect = rect
                label = label.union(rect)
            }
            // Cut the ring under the label so the number reads cleanly.
            if showsNumber {
                var cut = context
                cut.blendMode = .clear
                cut.fill(
                    Path(roundedRect: label.insetBy(dx: -1, dy: 0.5), cornerRadius: 1.5),
                    with: .color(.black))
                context.draw(number, at: numberCenter, anchor: .center)
                if let boltRect, let powerSymbol, let bolt = context.resolveSymbol(id: powerSymbol) {
                    context.draw(bolt, in: boltRect)
                }
            }

            // Volume: 5 dots on the ring's circle, left to right across the gap.
            for index in 0..<5 {
                let degrees = 90 + Double(2 - index) * Self.dotPitchDegrees
                let radians = degrees * .pi / 180
                let p = CGPoint(x: c.x + CGFloat(cos(radians)) * r, y: c.y + CGFloat(sin(radians)) * r)
                let d = Self.dotDiameter
                var dot = context
                if index >= activeDots { dot.opacity = Self.dimOpacity }
                dot.fill(
                    Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                    with: .foreground)
            }
        } symbols: {
            // Only drawn while charging: green with the number.
            Image(systemName: "bolt.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.green)
                .tag(SymbolID.bolt)
            Image(systemName: "powerplug.portrait.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .tag(SymbolID.plug)
        }
        .overlay {
            // Wi-Fi: stock symbol, lit arcs follow the signal. An overlay
            // view so its font size follows `scale`.
            Image(systemName: "wifi", variableValue: Self.wifiVariableValue(bars: wifiBars))
                .font(.system(size: 7.5 * scale, weight: .semibold))
                .position(x: Self.center.x * scale, y: (Self.center.y + 0.5) * scale)
        }
        .frame(width: Self.size.width * scale, height: Self.size.height * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private enum SymbolID: Hashable { case bolt, plug }

    /// DuoBar's WiFiSignalLevel.symbolVariableValue. An exact 2/3 sits just
    /// under the symbol's second-layer threshold and would light only the dot.
    static func wifiVariableValue(bars: Int) -> Double {
        switch bars {
        case 3...: return 1
        case 2: return 0.62
        case 1: return 0.25
        default: return 0
        }
    }

    private var accessibilitySummary: String {
        let battery =
            "Battery \(batteryLevel) percent"
            + (isCharging ? ", charging" : isPluggedIn ? ", on power, not charging" : "")
        let network = wifiBars > 0 ? "Wi-Fi \(wifiBars) of 3 bars" : "Wi-Fi not connected"
        let sound = isMuted ? "volume muted" : "volume \(Int((volumeLevel * 100).rounded())) percent"
        return "\(battery), \(network), \(sound)"
    }
}
