// Presentation follows Atoll (GPL-3.0-or-later): components/Live activities/
// DynamicIslandBattery.swift, BatteryTemporaryActivityView's standard style.
// The AI quota warning itself has no reference equivalent.

import SwiftUI

/// A quota warning in the expanded battery-HUD shape, below the physical camera band.
struct AIUsageHUDView: View {
    let alert: AIQuotaAlertPolicy.Alert
    let notchHeight: CGFloat

    private static let horizontalPadding: CGFloat = 32
    private static let bottomPadding: CGFloat = 14
    private static let indicatorDiameter: CGFloat = 36
    private var fraction: Double { min(1, max(0, alert.usedPercent / 100)) }

    var body: some View {
        VStack(spacing: 7) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(.orange.opacity(0.2), lineWidth: 3)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    AIProviderGlyph(provider: alert.provider).foregroundStyle(.orange)
                }
                .frame(width: Self.indicatorDiameter, height: Self.indicatorDiameter)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.provider.title).font(.system(size: 14, weight: .semibold))
                    Text(alert.window.title + " quota used").font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 6)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }
            .foregroundStyle(.white)
            GeometryReader { geometry in
                Capsule().fill(.orange.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.orange).frame(width: max(0, geometry.size.width * fraction))
                    }
            }
            .frame(height: 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.bottom, Self.bottomPadding)
        .accessibilityLabel(
            "\(alert.provider.title) \(alert.window.title) quota \(alert.usedPercent.formatted()) percent used")
    }
}
