import SwiftUI

/// A notch page's icon at a symbol font size. SF Symbols has no calculator
/// (the ± symbol did not read as one), so the calculator is drawn
/// (`CalculatorGlyph`). No reference equivalent.
struct NotchPageIcon: View {
    let page: NotchPage
    let size: CGFloat
    var weight: Font.Weight = .regular

    var body: some View {
        if page == .calculator {
            let bold = weight == .semibold || weight == .bold
            CalculatorGlyph(lineWidth: size * (bold ? 0.12 : 0.09))
                .frame(width: size * 0.8, height: size * 1.06)
                .frame(height: size * 1.2)
        } else {
            Image(systemName: page.icon)
                .font(.system(size: size, weight: weight))
        }
    }
}

/// Outline calculator: body, display bar, 3 × 3 keys. Uses the foreground style.
struct CalculatorGlyph: View {
    var lineWidth: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let inset = lineWidth / 2
            let body = CGRect(x: inset, y: inset, width: w - lineWidth, height: h - lineWidth)
            context.stroke(
                Path(roundedRect: body, cornerRadius: w * 0.2),
                with: .foreground, lineWidth: lineWidth)
            // Display.
            let pad = w * 0.2
            let display = CGRect(x: pad, y: pad, width: w - 2 * pad, height: h * 0.18)
            context.fill(Path(roundedRect: display, cornerRadius: display.height * 0.3), with: .foreground)
            // Keys.
            let top = display.maxY + h * 0.1
            let gridH = h - pad - top
            let key = min((w - 2 * pad) / 3, gridH / 3) * 0.62
            for row in 0..<3 {
                for col in 0..<3 {
                    let cx = pad + (w - 2 * pad) * (CGFloat(col) + 0.5) / 3
                    let cy = top + gridH * (CGFloat(row) + 0.5) / 3
                    context.fill(
                        Path(
                            roundedRect: CGRect(x: cx - key / 2, y: cy - key / 2, width: key, height: key),
                            cornerRadius: key * 0.3), with: .foreground)
                }
            }
        }
    }
}
