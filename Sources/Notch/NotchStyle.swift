import SwiftUI

/// Animation and colours shared by the island's views.
enum NotchStyle {
    static let aiQuotaHUDCornerRadius: CGFloat = 40
    /// The spring every island morph uses, so the shape and its content
    /// move together.
    static let morph = Animation.spring(response: 0.42, dampingFraction: 1)

    /// Every card inside the open notch (Clipboard items, AI Usage accounts, calendar events and reminders,
    /// the calculator display, the battery strip) uses one surface.
    static let cardCornerRadius: CGFloat = 14
    static let cardFill = Color.white.opacity(0.07)
    static let cardHighlightFill = Color.white.opacity(0.12)
    /// A hairline edge so a card reads against the black island.
    static let cardEdge = Color.white.opacity(0.1)
    static let cardEdgeWidth: CGFloat = 0.8
    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }
}

/// The shared card surface; `isHighlighted` is the hover state where a card reacts to the pointer.
struct NotchCardBackground: View {
    var isHighlighted = false

    var body: some View {
        NotchStyle.cardShape
            .fill(isHighlighted ? NotchStyle.cardHighlightFill : NotchStyle.cardFill)
            .overlay(NotchStyle.cardShape.strokeBorder(NotchStyle.cardEdge, lineWidth: NotchStyle.cardEdgeWidth))
    }
}

extension ShapeStyle where Self == Color {
    /// Secondary text and glyphs on the black island.
    static var notchSecondary: Color { Color(white: 0.65) }
}
