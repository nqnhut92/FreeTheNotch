import Foundation

/// Steadies the per-app energy list across samples with an exponential
/// moving average per app, so one busy sampling window does not reorder the
/// list. An app seen for the first time starts at its sampled value; an app
/// missing from a sample counts as 0 and fades out.
struct EnergySmoother {
    /// Time constant of the average: after this long a step change has
    /// moved the average about 63% of the way.
    static let timeConstant: TimeInterval = 20
    /// Averages below this (percent of one core) are dropped.
    static let dropBelow = 0.1

    private(set) var averages: [pid_t: Double] = [:]

    /// Folds in one sample (percent of one core per app) taken `elapsed`
    /// seconds after the previous one, and returns the new averages.
    @discardableResult
    mutating func add(_ sample: [pid_t: Double], elapsed: TimeInterval) -> [pid_t: Double] {
        let weight = 1 - exp(-max(0, elapsed) / Self.timeConstant)
        var next: [pid_t: Double] = [:]
        for pid in Set(averages.keys).union(sample.keys) {
            let value = sample[pid] ?? 0
            let average = averages[pid].map { $0 + weight * (value - $0) } ?? value
            if average >= Self.dropBelow { next[pid] = average }
        }
        averages = next
        return next
    }
}

/// Membership of the "Using Significant Energy" list, with separate join and
/// leave thresholds so an app hovering around one value does not blink in
/// and out of the list.
struct SignificantEnergyFilter {
    /// Percent of one core at which an app joins the list.
    static let joinThreshold = 20.0
    /// A listed app stays until its share drops below this.
    static let leaveThreshold = 10.0

    private(set) var listed: Set<pid_t> = []

    @discardableResult
    mutating func update(_ shares: [pid_t: Double]) -> Set<pid_t> {
        listed = Set(
            shares.compactMap { pid, share in
                let threshold = listed.contains(pid) ? Self.leaveThreshold : Self.joinThreshold
                return share >= threshold ? pid : nil
            })
        return listed
    }
}
