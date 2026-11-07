import SwiftUI

/// The `<···>` Ethernet mark from the macOS menu bar. SF Symbols has no public
/// equivalent (`chevron.left.chevron.right` lacks the dots), so it is drawn:
/// two chevrons around three dots, as one filled path so it takes the
/// foreground style like a symbol.
struct EthernetSymbolShape: Shape {
    /// Width : height of the mark, close to the `wifi` symbol's footprint.
    static let aspectRatio: CGFloat = 10.0 / 7.0

    // Proportions of the rect's height.
    private static let lineWidthRatio: CGFloat = 0.17
    private static let chevronWidthRatio: CGFloat = 0.42
    private static let dotDiameterRatio: CGFloat = 0.19
    /// Dot pitch as a proportion of the rect's width.
    private static let dotPitchRatio: CGFloat = 0.2

    func path(in rect: CGRect) -> Path {
        let lineWidth = rect.height * Self.lineWidthRatio
        let inset = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let chevronWidth = rect.height * Self.chevronWidthRatio

        var chevrons = Path()
        chevrons.move(to: CGPoint(x: inset.minX + chevronWidth, y: inset.minY))
        chevrons.addLine(to: CGPoint(x: inset.minX, y: inset.midY))
        chevrons.addLine(to: CGPoint(x: inset.minX + chevronWidth, y: inset.maxY))
        chevrons.move(to: CGPoint(x: inset.maxX - chevronWidth, y: inset.minY))
        chevrons.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
        chevrons.addLine(to: CGPoint(x: inset.maxX - chevronWidth, y: inset.maxY))

        var path = chevrons.strokedPath(
            StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        let diameter = rect.height * Self.dotDiameterRatio
        let pitch = rect.width * Self.dotPitchRatio
        for offset in [-pitch, 0, pitch] {
            path.addEllipse(
                in: CGRect(
                    x: rect.midX + offset - diameter / 2, y: rect.midY - diameter / 2,
                    width: diameter, height: diameter))
        }
        return path
    }
}
