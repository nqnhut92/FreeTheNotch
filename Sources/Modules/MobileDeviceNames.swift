import Foundation
import os

/// Names of the iPhones and iPads this Mac can reach over USB or Wi-Fi, read
/// through the private MobileDevice framework (the one Finder's device sync
/// uses). The name is a lockdown value that needs no pairing session. No
/// reference equivalent in Atoll or Vorssaint.
enum MobileDeviceNames {
    private typealias CreateDeviceList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias DeviceCall = @convention(c) (UnsafeRawPointer) -> Int32
    private typealias CopyValue = @convention(c) (UnsafeRawPointer, CFString?, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyIdentifier = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>?
    private typealias Subscribe =
        @convention(c) (
            ConnectionCallback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>
        ) -> Int32

    /// Called on the subscribing thread's run loop when a device joins or
    /// leaves. The first argument points at the device followed by a
    /// `UInt32` message (`connectedMessage`, `disconnectedMessage`); the
    /// second is the subscriber's context.
    typealias ConnectionCallback = @convention(c) (UnsafeRawPointer, UnsafeMutableRawPointer?) -> Void

    static let connectedMessage: UInt32 = 1
    static let disconnectedMessage: UInt32 = 2

    /// A reachable device: its UDID and the name its owner gave it.
    struct Device {
        let identifier: String
        let name: String
    }

    private struct Functions {
        let createDeviceList: CreateDeviceList
        let connect: DeviceCall
        let disconnect: DeviceCall
        let copyValue: CopyValue
        let copyIdentifier: CopyIdentifier
        let subscribe: Subscribe
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"
    private static let deviceNameKey = "DeviceName"
    /// `AMDeviceConnect`'s success code.
    private static let success: Int32 = 0

    /// Nil when the framework or a symbol is gone: no names, and the
    /// activity shows its fallback label.
    private static let functions: Functions? = {
        guard
            let handle = dlopen(frameworkPath, RTLD_NOW),
            let list = dlsym(handle, "AMDCreateDeviceList"),
            let connect = dlsym(handle, "AMDeviceConnect"),
            let disconnect = dlsym(handle, "AMDeviceDisconnect"),
            let copy = dlsym(handle, "AMDeviceCopyValue"),
            let identifier = dlsym(handle, "AMDeviceCopyDeviceIdentifier"),
            let subscribe = dlsym(handle, "AMDeviceNotificationSubscribe")
        else {
            Logger.modules.error("[FreeTheNotch] MobileDevice unavailable: device names are not read")
            return nil
        }
        return Functions(
            createDeviceList: unsafeBitCast(list, to: CreateDeviceList.self),
            connect: unsafeBitCast(connect, to: DeviceCall.self),
            disconnect: unsafeBitCast(disconnect, to: DeviceCall.self),
            copyValue: unsafeBitCast(copy, to: CopyValue.self),
            copyIdentifier: unsafeBitCast(identifier, to: CopyIdentifier.self),
            subscribe: unsafeBitCast(subscribe, to: Subscribe.self))
    }()

    /// Loads the framework ahead of the first lookup. It finds devices in
    /// the background after loading, so a list asked for right away is
    /// still empty.
    static func preload() {
        _ = functions
    }

    /// The connected devices, each once (a device on a cable and on Wi-Fi
    /// is listed twice). Talks to each device, so it can block: never call
    /// it on the main thread.
    static func connected() -> [Device] {
        guard let functions, let listed = functions.createDeviceList()?.takeRetainedValue() as [AnyObject]? else {
            return []
        }
        var devices: [Device] = []
        for entry in listed {
            let pointer = UnsafeRawPointer(Unmanaged.passUnretained(entry).toOpaque())
            guard let identifier = identifier(of: pointer),
                !devices.contains(where: { $0.identifier == identifier }),
                functions.connect(pointer) == success
            else { continue }
            defer { _ = functions.disconnect(pointer) }
            guard
                let name = functions.copyValue(pointer, nil, deviceNameKey as CFString)?.takeRetainedValue() as? String
            else { continue }
            devices.append(Device(identifier: identifier, name: name))
        }
        Logger.modules.notice(
            "[FreeTheNotch] Devices listed: \(listed.count, privacy: .public), named: \(devices.count, privacy: .public)"
        )
        return devices
    }

    /// The device's UDID. Local: it does not talk to the device.
    static func identifier(of device: UnsafeRawPointer) -> String? {
        functions?.copyIdentifier(device)?.takeRetainedValue() as String?
    }

    /// Asks for `callback` whenever a device joins or leaves, on the calling
    /// thread's run loop. Devices already connected are reported at once.
    /// False when the framework is unavailable.
    static func subscribe(context: UnsafeMutableRawPointer, callback: ConnectionCallback) -> Bool {
        guard let functions else { return false }
        var subscription: UnsafeMutableRawPointer?
        return functions.subscribe(callback, 0, 0, context, &subscription) == success
    }
}
