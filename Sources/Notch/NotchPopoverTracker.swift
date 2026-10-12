/// Keeps the notch open while one of its popovers (a separate window) is
/// showing: Atoll's `setMediaOutputPopoverActive`.
final class NotchPopoverTracker {
    static let shared = NotchPopoverTracker()

    var isOpen = false

    private init() {}
}
