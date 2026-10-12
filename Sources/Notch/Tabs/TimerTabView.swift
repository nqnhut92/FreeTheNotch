import SwiftUI

/// Countdown timer. A running timer surfaces as a Live Activity in the
/// collapsed notch and on the lock screen.
struct TimerTabView: View {
    @EnvironmentObject var timerStore: TimerStore

    var body: some View {
        VStack(spacing: 12) {
            Text(timerStore.formattedRemaining)
                .font(.system(size: 40, weight: .light, design: .monospaced))
                .padding(.top, 8)

            HStack(spacing: 8) {
                ForEach([5, 15, 25, 50], id: \.self) { minutes in
                    Button("\(minutes)m") { timerStore.setDuration(minutes * 60) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Button(timerStore.isRunning ? "Pause" : "Start") {
                    timerStore.toggle()
                }
                .buttonStyle(.borderedProminent)
                Button("Reset") { timerStore.reset() }
                    .buttonStyle(.bordered)
            }

            Text("A running timer shows in the collapsed notch.")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 12)
    }
}
