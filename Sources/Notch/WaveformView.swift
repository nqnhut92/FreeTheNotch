import SwiftUI

/// Live-audio bars beside the artwork while music plays: rounded capsules
/// growing from the centre, tinted with the artwork's average colour like the
/// iOS Dynamic Island (Atoll-style).
struct WaveformView: View {
    var color: Color = .white
    @Environment(\.lockAnimationsPaused) private var paused

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: paused)) { timeline in
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: barHeight(i, date: timeline.date))
                }
            }
        }
        .frame(height: 16)
    }

    private func barHeight(_ i: Int, date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        return 4 + abs(sin(t * 3.2 + Double(i) * 0.9)) * 12
    }
}
