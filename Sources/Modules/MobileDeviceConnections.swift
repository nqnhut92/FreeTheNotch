import Foundation

/// When each reachable iPhone or iPad joined this Mac. A device that syncs
/// over Wi-Fi joins moments before its sync, which is how the device-sync
/// activity tells it from one that has been connected for a while. No
/// reference equivalent in Atoll or Vorssaint.
@MainActor
final class MobileDeviceConnections {
    /// Join time by device UDID, for the devices connected now.
    private(set) var connectedAt: [String: Date] = [:]
    private var isSubscribed = false

    /// Starts listening on the main run loop. The object must outlive the
    /// subscription, which is never cancelled: the device-sync monitor
    /// that owns it lives as long as the app.
    func start() {
        guard !isSubscribed else { return }
        isSubscribed = MobileDeviceNames.subscribe(
            context: Unmanaged.passUnretained(self).toOpaque(), callback: Self.deviceChanged)
    }

    private func record(message: UInt32, identifier: String) {
        switch message {
        case MobileDeviceNames.connectedMessage:
            // A device already here on a cable also joins over Wi-Fi; the
            // first time stands.
            if connectedAt[identifier] == nil { connectedAt[identifier] = Date() }
        case MobileDeviceNames.disconnectedMessage:
            connectedAt[identifier] = nil
        default:
            break
        }
    }

    private static let deviceChanged: MobileDeviceNames.ConnectionCallback = { info, context in
        guard let context else { return }
        // The device pointer is only good during the callback.
        let device = info.load(as: UnsafeRawPointer.self)
        let message = info.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.stride, as: UInt32.self)
        guard let identifier = MobileDeviceNames.identifier(of: device) else { return }
        let address = UInt(bitPattern: context)
        DispatchQueue.main.async {
            guard let context = UnsafeRawPointer(bitPattern: address) else { return }
            Unmanaged<MobileDeviceConnections>.fromOpaque(context).takeUnretainedValue()
                .record(message: message, identifier: identifier)
        }
    }
}
