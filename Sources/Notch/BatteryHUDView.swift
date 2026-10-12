// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// components/Live activities/DynamicIslandBattery.swift —
// BatteryTemporaryHUDMetrics, BatteryCompactStatusRow and
// BatteryTemporaryActivityView with Atoll's default styles (charging compact,
// low and full battery standard).

import SwiftUI

extension BatteryHUDKind {
    /// Atoll's `metrics(style:closedNotchWidth:baseHeight:)` for the default styles.
    func size(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        switch self {
        case .charging: return CGSize(width: notchWidth + 180, height: notchHeight)
        case .lowBattery: return CGSize(width: notchWidth + 150, height: notchHeight + 75)
        case .fullBattery: return CGSize(width: notchWidth + 140, height: notchHeight + 70)
        }
    }

    var bottomRadius: CGFloat {
        switch self {
        case .charging: return 16
        case .lowBattery: return 40
        case .fullBattery: return 36
        }
    }

    var isCompact: Bool { self == .charging }
}

struct BatteryHUDView: View {
    let kind: BatteryHUDKind
    let batteryLevel: Int
    let isLowPowerMode: Bool

    @State private var pulse = false
    @State private var showBatteryIndicator = false
    @State private var changeBatteryIndicator = true

    private var batteryTint: Color {
        switch kind {
        case .charging:
            if isLowPowerMode { return .yellow }
            if batteryLevel <= 20 { return .red }
            return .green
        case .lowBattery:
            return isLowPowerMode ? .yellow : .red
        case .fullBattery:
            return isLowPowerMode ? .yellow : .green
        }
    }

    var body: some View {
        content
            .onAppear(perform: prepareAnimations)
    }

    @ViewBuilder
    private var content: some View {
        if kind.isCompact {
            BatteryCompactStatusRow(title: "Charging", batteryLevel: batteryLevel, tint: batteryTint)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: kind == .lowBattery ? 2 : 3) {
                        standardTitle
                        standardDescription
                    }
                    Spacer()
                    standardIndicator
                }
                .padding(.leading, kind == .lowBattery ? 40 : 35)
                .padding(.trailing, kind == .lowBattery ? 45 : 40)
                .padding(.bottom, 20)
            }
        }
    }

    private var standardTitle: some View {
        HStack(spacing: 5) {
            Text(kind == .lowBattery ? "Battery Low" : "Full Battery")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
            Text("\(batteryLevel)%")
                .font(.system(size: kind == .lowBattery ? 12 : 13, weight: .semibold))
                .foregroundStyle(batteryTint)
        }
    }

    @ViewBuilder
    private var standardDescription: some View {
        switch kind {
        case .charging:
            EmptyView()
        case .lowBattery:
            if isLowPowerMode {
                (Text("Low Power Mode enabled")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 10, weight: .medium))
                    + Text(", it is recommended to charge it.")
                    .foregroundStyle(.gray.opacity(0.6))
                    .font(.system(size: 10, weight: .medium)))
            } else {
                Text("Turn on Low Power Mode or it\nis recommended to charge it.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.6))
                    .lineLimit(2)
            }
        case .fullBattery:
            Text("Your Mac is fully charged.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.gray.opacity(0.6))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var standardIndicator: some View {
        switch kind {
        case .charging:
            EmptyView()
        case .lowBattery:
            lowIndicator(tint: isLowPowerMode ? .yellow : .red, pulsing: !isLowPowerMode)
        case .fullBattery:
            if showBatteryIndicator {
                fullIndicator(tint: isLowPowerMode ? .yellow : .green)
                    .transition(.opacity.combined(with: .scale))
            } else {
                magSafeIndicator
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    /// Atoll's redLowIndicator / yellowLowIndicator (yellow does not pulse).
    private func lowIndicator(tint: Color, pulsing: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(tint.opacity(0.2))
                .frame(width: 70, height: 40)
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.4))
                    .frame(width: 40, height: 24)
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
            .padding(.trailing, 5)
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.gradient)
                .frame(width: 8, height: 14)
                .opacity(pulsing ? (pulse ? 1 : 0.3) : 1)
                .offset(x: -15)
            if pulsing {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(tint.opacity(0.9), lineWidth: 1.5)
                    .frame(width: pulse ? 8 : 30, height: pulse ? 14 : 32)
                    .offset(x: -15)
                    .opacity(pulse ? 0.3 : 1)
            }
        }
    }

    /// Atoll's greenFullIndicator / yellowFullIndicator.
    private func fullIndicator(tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(tint.opacity(0.2))
                .frame(width: 70, height: 40)
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.4))
                    .frame(width: 44, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tint.gradient)
                            .frame(width: 34, height: 14)
                            .opacity(pulse ? 1 : 0.4)
                    )
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
        }
    }

    private var magSafeIndicator: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.gray.opacity(0.15))
                .frame(width: 30, height: 5)
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.2).gradient)
                    .frame(width: 30, height: 40)
                Circle()
                    .fill(changeBatteryIndicator ? .orange : .green)
                    .shadow(color: changeBatteryIndicator ? .orange : .green, radius: 5)
                    .frame(width: 5, height: 5)
            }
            Rectangle()
                .fill(.white.opacity(0.4))
                .frame(width: 3, height: 32)
        }
    }

    private func prepareAnimations() {
        pulse = false
        showBatteryIndicator = kind == .fullBattery
        changeBatteryIndicator = true

        switch kind {
        case .charging:
            break
        case .lowBattery:
            if !isLowPowerMode {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        case .fullBattery:
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.spring(duration: 0.4)) { showBatteryIndicator = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.spring(duration: 0.2)) { changeBatteryIndicator = false }
            }
        }
    }
}

/// Atoll's BatteryCompactStatusRow: title in the left ear, % and a battery
/// glyph in the right ear.
private struct BatteryCompactStatusRow: View {
    let title: String
    let batteryLevel: Int
    let tint: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            HStack(spacing: 6) {
                Text("\(batteryLevel)%")
                    .font(.system(size: 14))
                    .foregroundStyle(tint)
                HStack(spacing: 1.5) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(0.3))
                        GeometryReader { geo in
                            let clamped = max(0, min(batteryLevel, 100))
                            Rectangle()
                                .fill(tint.gradient)
                                .frame(width: max(0, CGFloat(clamped) / 100 * geo.size.width))
                        }
                    }
                    .frame(width: 28, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(batteryLevel == 100 ? tint.gradient : tint.opacity(0.3).gradient)
                        .frame(width: 2, height: 6)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}
