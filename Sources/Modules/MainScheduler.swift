import Foundation

/// Runs `work` on the main queue after `delay` seconds. Injected where a
/// test has to run delayed work by hand.
typealias MainScheduler = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void

enum MainQueue {
    static let after: MainScheduler = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
