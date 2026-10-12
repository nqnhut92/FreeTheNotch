import SwiftUI

/// Animation and colours shared by the island's views.
enum NotchStyle {
    static let aiQuotaHUDCornerRadius: CGFloat = 40
    /// The spring every island morph uses, so the shape and its content
    /// move together.
    static let morph = Animation.spring(response: 0.42, dampingFraction: 1)
}

extension ShapeStyle where Self == Color {
    /// Secondary text and glyphs on the black island.
    static var notchSecondary: Color { Color(white: 0.65) }
}
