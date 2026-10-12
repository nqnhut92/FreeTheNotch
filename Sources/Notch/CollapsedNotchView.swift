import SwiftUI

/// Content inside the closed island (NotchRootView draws the shape so it can
/// morph). One live activity at a time, by priority: HUD (volume/backlight)
/// > AI quota warning > Caps Lock > AI session > media (playing) > timer. Idle stays empty.
struct CollapsedNotchView: View {
    let screen: NSScreen

    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var media: MediaRemoteAdapter
    @EnvironmentObject var timerStore: TimerStore
    @EnvironmentObject var hud: HUDController
    @EnvironmentObject var capsLock: CapsLockManager
    @EnvironmentObject var aiActivities: AIActivityMonitor

    private var isNotch: Bool {
        DisplayGeometry.hasNotch(screen)
    }

    var body: some View {
        content
            .padding(.horizontal, isNotch ? 8 : 12)
    }

    @ViewBuilder
    private var content: some View {
        if hud.isHUDVisible {
            hudView
        } else if settings.capsLockEnabled && capsLock.isCapsLockActive {
            // Caps Lock indicator (Atoll-style): left ear, not center —
            // the physical notch covers the middle.
            HStack {
                Text("\u{21EA}")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
                    .padding(.leading, 4)
                Spacer()
            }
        } else if let activity = aiActivities.activities.first {
            AIActivityCompactView(activity: activity, count: aiActivities.activities.count)
        } else if settings.mediaEnabled && media.isPlaying {
            // Artwork and waveform flank the camera.
            HStack {
                artwork
                Spacer()
                WaveformView(color: media.artworkColor)
            }
        } else if timerStore.isActive {
            // Atoll's TimerLiveActivity (default .bar style): timer glyph in
            // the left ear, countdown + thin progress bar in the right ear.
            // The camera covers the middle, so nothing sits there.
            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.leading, 4)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(timerStore.formattedRemaining)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.25), value: timerStore.remainingSeconds)
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 44, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.orange)
                                .frame(width: 44 * CGFloat(min(max(timerStore.progressFraction, 0), 1)))
                                .animation(.smooth(duration: 0.25), value: timerStore.progressFraction)
                        }
                }
            }
        } else {
            // A Bluetooth connection drops a popup below the island
            // (BluetoothPopupView) and charging is not a live activity.
            Color.clear
        }
    }

    /// Atoll's CircularHUDView, simplified: progress ring and icon in the left
    /// ear, percentage in the right, so nothing crosses the physical notch.
    private var hudView: some View {
        HStack {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(hud.isMuted ? 0 : hud.level))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: hud.icon)
                    .foregroundStyle(.white)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 26, height: 26)
            Spacer()
            Text(hud.isMuted ? "--" : String(format: "%3d", Int(hud.level * 100)))
                .foregroundStyle(.white.opacity(0.9))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 30)
                .contentTransition(.numericText())
        }
        .transition(.opacity.combined(with: .scale(0.95)))
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let art = media.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
