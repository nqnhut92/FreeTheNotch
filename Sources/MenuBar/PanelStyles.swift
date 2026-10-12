import SwiftUI

// Shared styles for the menu-bar panel. Visual design follows Vorssaint's
// panel (vorssaint/vorssaint-utils, GPL-3.0-or-later): dark cards, usage
// bars, sparklines.

// MARK: - Surface tokens (Vorssaint Theme.swift: PanelSurface)

enum PanelSurface {
    static func baseFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.68) : Color.black.opacity(0.42)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.38) : Color.white.opacity(0.075)
    }

    /// Increase Contrast raises the hairlines that separate cards.
    static func border(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.24 : 0.09)
            : Color.white.opacity(raised ? 0.28 : 0.11)
    }
}

// MARK: - Metric colors (Vorssaint Theme.swift: PanelMetricColor)

/// System colors in dark mode, darker custom tones in light mode so they stay
/// readable on the pale panel. Dynamic, so no colorScheme plumbing is needed.
enum PanelMetricColor {
    static let green = adaptive(.systemGreen, light: (0.00, 0.44, 0.18))
    static let cyan = adaptive(.systemCyan, light: (0.00, 0.43, 0.54))
    static let mint = adaptive(.systemMint, light: (0.00, 0.44, 0.40))
    static let yellow = adaptive(.systemYellow, light: (0.56, 0.36, 0.00))
    static let red = adaptive(.systemRed, light: (0.68, 0.08, 0.10))
    static let orange = adaptive(.systemOrange, light: (0.68, 0.30, 0.00))
    static let pink = adaptive(.systemPink, light: (0.68, 0.06, 0.34))

    private static func adaptive(_ dark: NSColor, light: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? dark
                    : NSColor(srgbRed: light.0, green: light.1, blue: light.2, alpha: 1)
            })
    }
}

// MARK: - Card

private struct PanelCardModifier: ViewModifier {
    var padded: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padded ? 10 : 0)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PanelSurface.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
            )
    }
}

extension View {
    /// A card holding a list of rows is not padded: each row brings its own insets.
    func panelCard(padded: Bool = true) -> some View { modifier(PanelCardModifier(padded: padded)) }
}

// MARK: - Glass text

/// On the see-through glass panel, dark mode's secondary (~57% white) and
/// tertiary (~31%) text is unreadable. `Text` ignores custom foreground
/// levels (`.foregroundStyle(a, b, c)` only affects shapes), so panel text
/// uses these explicit styles: whiter on glass, the system levels otherwise.
private struct GlassPanelTextKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var glassPanelText: Bool {
        get { self[GlassPanelTextKey.self] }
        set { self[GlassPanelTextKey.self] = newValue }
    }
}

struct PanelTextStyle: ShapeStyle {
    var glassOpacity: Double
    var fallback: HierarchicalShapeStyle

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.glassPanelText
            ? AnyShapeStyle(Color.white.opacity(glassOpacity))
            : AnyShapeStyle(fallback)
    }
}

extension ShapeStyle where Self == PanelTextStyle {
    static var panelSecondary: PanelTextStyle { PanelTextStyle(glassOpacity: 0.92, fallback: .secondary) }
    static var panelTertiary: PanelTextStyle { PanelTextStyle(glassOpacity: 0.85, fallback: .tertiary) }
}

extension View {
    /// Turns on the glass text styles. Apply it again inside any nested
    /// NSHostingView (OverlayScrollView): environment does not cross it.
    func glassPanelText(_ enabled: Bool = true) -> some View {
        environment(\.glassPanelText, enabled)
    }
}

// MARK: - Buttons

/// Small pill button for the panel, instead of `.bordered`: the system
/// bezel derives from the foreground hierarchy, which the glass panel
/// whitens into a pale pill with white text.
struct PanelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let base = colorScheme == .dark ? Color.white : Color.black
        configuration.label
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(base.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Headers

/// "SYSTEM", "KEEP AWAKE": uppercased, kerned, ABOVE the card.
struct PanelSectionTitle: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(.panelSecondary)
    }
}

/// Vorssaint's PanelSection (non-collapsible, as in the tabbed panel):
/// title row, 8pt, then the card.
struct PanelSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                PanelSectionTitle(text: title)
                Spacer(minLength: 0)
            }
            content
        }
    }
}

// MARK: - Usage bar

/// 5pt capsule bar. Color steps: normal -> yellow -> red.
struct UsageBar: View {
    var fraction: Double
    var warnAt: Double = 0.6
    var criticalAt: Double = 0.85
    var normalColor: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(barColor)
                    .frame(width: max(3, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 5)
    }

    private var barColor: Color {
        if fraction >= criticalAt { return PanelMetricColor.red }
        if fraction >= warnAt { return PanelMetricColor.yellow }
        return normalColor
    }
}

/// 6pt disk bar: <75% accent, 75–90% yellow, >=90% red.
struct DiskUsageBar: View {
    var fraction: Double
    var body: some View {
        UsageBar(fraction: fraction, warnAt: 0.75, criticalAt: 0.9, normalColor: .accentColor)
            .frame(height: 6)
    }
}

// MARK: - Memory pressure pill

struct PressurePill: View {
    /// 1 = normal, 2 = warning, 4 = critical.
    var level: Int

    private var color: Color {
        switch level {
        case 4: return PanelMetricColor.red
        case 2: return PanelMetricColor.yellow
        default: return PanelMetricColor.green
        }
    }

    private var label: String {
        switch level {
        case 4: return "Critical"
        case 2: return "Caution"
        default: return "Normal"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.6), radius: 2)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.13)))
    }
}

// MARK: - Key/value row

/// "Battery temperature" .... "36 °C" — the shared Power-tab row layout.
struct PanelMetricRow: View {
    var icon: String
    var iconColor: Color
    var label: String
    var caption: String?
    var value: String

    init(
        icon: String, iconColor: Color = .secondary,
        label: String, caption: String? = nil, value: String
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.caption = caption
        self.value = value
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.74))
                if let caption {
                    Text(caption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.panelSecondary)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}
