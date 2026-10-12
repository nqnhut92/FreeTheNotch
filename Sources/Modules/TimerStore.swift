import AppKit
import Foundation

/// Countdown timer. While running it surfaces as a Live Activity in the
/// collapsed notch and on the lock screen.
@MainActor
final class TimerStore: ObservableObject {
    @Published private(set) var totalSeconds: Int = 25 * 60
    @Published private(set) var remainingSeconds: Int = 25 * 60
    @Published private(set) var isRunning = false

    private var timer: Timer?
    private var endDate: Date?
    private let now: () -> Date
    private let onFinish: () -> Void

    /// - Parameters:
    ///   - now: The clock; tests pass a fake one.
    ///   - onFinish: Runs when the countdown reaches zero.
    init(now: @escaping () -> Date = Date.init, onFinish: @escaping () -> Void = { NSSound.beep() }) {
        self.now = now
        self.onFinish = onFinish
    }

    var formattedRemaining: String {
        DurationFormat.clock(remainingSeconds, showsHours: totalSeconds >= 3600)
    }

    /// Running, or paused part-way (Atoll keeps the live activity up while
    /// paused). Finished (0 left) or reset (full) is not active.
    var isActive: Bool {
        isRunning || (remainingSeconds > 0 && remainingSeconds < totalSeconds)
    }

    var progressFraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - Double(remainingSeconds) / Double(totalSeconds)
    }

    func setDuration(_ seconds: Int) {
        pause()
        totalSeconds = seconds
        remainingSeconds = seconds
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard remainingSeconds > 0 else { return }
        isRunning = true
        endDate = now().addingTimeInterval(TimeInterval(remainingSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        endDate = nil
    }

    func reset() {
        pause()
        remainingSeconds = totalSeconds
    }

    /// Re-reads the remaining time from the clock. The timer calls it twice a
    /// second; counting from the end date keeps it exact across sleep.
    func tick() {
        guard let endDate else { return }
        let left = Int(endDate.timeIntervalSince(now()).rounded(.up))
        if left <= 0 {
            remainingSeconds = 0
            pause()
            onFinish()
        } else {
            remainingSeconds = left
        }
    }
}
