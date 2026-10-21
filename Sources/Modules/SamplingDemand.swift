import Foundation

/// Who needs a monitor's optional samples right now. The monitor samples
/// while at least one client holds a demand, so one view going away does not
/// stop the samples another still shows.
struct SamplingDemand<Client: Hashable> {
    private(set) var clients: Set<Client> = []

    var isActive: Bool { !clients.isEmpty }

    /// Adds or removes `client`'s demand. Returns true when this turned
    /// sampling on or off.
    @discardableResult
    mutating func set(_ isNeeded: Bool, by client: Client) -> Bool {
        let wasActive = isActive
        if isNeeded {
            clients.insert(client)
        } else {
            clients.remove(client)
        }
        return wasActive != isActive
    }
}
