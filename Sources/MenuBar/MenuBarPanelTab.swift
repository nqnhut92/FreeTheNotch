import Foundation

/// The menu bar panel's tabs, also shown one at a time by the Side Notch's
/// system cells.
enum MenuBarPanelTab: String, CaseIterable {
    case keepAwake, system, network, disk, power, tools

    var icon: String {
        switch self {
        case .keepAwake: return "moon.zzz.fill"
        case .system: return "cpu"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        }
    }

    /// Section title above the card (uppercased by PanelSectionTitle)
    /// and the tab's tooltip.
    var title: String {
        switch self {
        case .keepAwake: return "Keep awake"
        case .system: return "System"
        case .network: return "Network"
        case .disk: return "Disks"
        case .power: return "Power"
        case .tools: return "Utilities"
        }
    }

    /// What the tab reads that is sampled only while it shows.
    var samplingNeeds: PanelSamplingNeeds {
        switch self {
        case .system: return [.processes, .temperatures]
        case .network: return [.network]
        case .disk: return [.disks]
        case .power: return [.processes, .temperatures]
        case .keepAwake, .tools: return []
        }
    }
}

/// Samples a popover needs while it shows. Nothing is sampled for a closed
/// popover, like Vorssaint's `releasePanelResources()` on close.
struct PanelSamplingNeeds: OptionSet, Hashable {
    let rawValue: Int

    /// Per-app CPU, GPU, memory and energy (ProcessMonitor).
    static let processes = PanelSamplingNeeds(rawValue: 1 << 0)
    /// Per-app network rates (ProcessMonitor, through nettop).
    static let network = PanelSamplingNeeds(rawValue: 1 << 1)
    /// CPU, GPU and battery temperatures (SystemMonitor, SMC).
    static let temperatures = PanelSamplingNeeds(rawValue: 1 << 2)
    /// Volume list and SMART health (DiskMonitor, diskutil).
    static let disks = PanelSamplingNeeds(rawValue: 1 << 3)
}
