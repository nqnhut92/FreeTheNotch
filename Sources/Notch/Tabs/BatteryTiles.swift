import SwiftUI

/// One ring in the battery strip's device card.
struct BatteryTile: Identifiable, Equatable {
    let id: String
    let icon: String
    let percent: Int
    let label: String

    /// iOS shows one ring for both buds while their levels are this close,
    /// two otherwise.
    static let budSplitThreshold = 10
    static let maxTiles = 6

    /// Rings for connected devices, then for devices only seen nearby
    /// (AirPods in their case), at most `maxTiles`. AirPods split into buds
    /// and case like the macOS Batteries widget; other devices get one ring
    /// when they report a level.
    static func tiles(connected: [BTDevice], nearby: [BTDevice]) -> [BatteryTile] {
        var result: [BatteryTile] = []
        for device in connected + nearby {
            if device.kind == .airpods, let parts = device.parts {
                result += airPodsTiles(device, parts)
            } else if let percent = device.batteryPercent {
                result.append(
                    BatteryTile(id: device.id, icon: device.kind.symbolName, percent: percent, label: device.name))
            }
        }
        return Array(result.prefix(maxTiles))
    }

    private static func airPodsTiles(_ device: BTDevice, _ parts: BTBatteryParts) -> [BatteryTile] {
        var tiles: [BatteryTile] = []
        switch (parts.left, parts.right) {
        case (let l?, let r?) where abs(l - r) <= budSplitThreshold:
            tiles.append(BatteryTile(id: device.id + ".buds", icon: "airpodspro", percent: min(l, r), label: "AirPods"))
        default:
            if let l = parts.left {
                tiles.append(BatteryTile(id: device.id + ".l", icon: "airpodpro.left", percent: l, label: "Left bud"))
            }
            if let r = parts.right {
                tiles.append(
                    BatteryTile(id: device.id + ".r", icon: "airpodpro.right", percent: r, label: "Right bud"))
            }
        }
        if let c = parts.caseLevel {
            tiles.append(
                BatteryTile(
                    id: device.id + ".case", icon: "airpodspro.chargingcase.wireless.fill",
                    percent: c, label: "Case"))
        }
        if tiles.isEmpty, let percent = device.batteryPercent {
            tiles.append(BatteryTile(id: device.id, icon: "airpodspro", percent: percent, label: device.name))
        }
        return tiles
    }

    /// "45m", "2h 5m".
    static func duration(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// iOS Batteries-widget ring colours: green, orange at 20% and below, red at
/// 10% and below; green whenever charging.
enum BatteryRingTint: Equatable {
    case normal, low, critical

    init(percent: Int, charging: Bool) {
        if charging {
            self = .normal
        } else if percent <= 10 {
            self = .critical
        } else if percent <= 20 {
            self = .low
        } else {
            self = .normal
        }
    }

    var color: Color {
        switch self {
        case .normal: return .green
        case .low: return .orange
        case .critical: return .red
        }
    }
}
