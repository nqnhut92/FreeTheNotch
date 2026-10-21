import Foundation

/// One popover per Side Notch cell, plus the full panel the menu bar icon
/// opens when the Side Notch is off.
enum SideNotchPopoverKind: String {
    case duo, bluetooth, keepAwake, system, network, disk, power, panel

    /// The panel tab a system cell shows on its own.
    var tab: MenuBarPanelTab? {
        MenuBarPanelTab(rawValue: rawValue)
    }

    /// What this popover needs sampled while it shows. The full panel needs
    /// what its selected tab shows.
    func samplingNeeds(panelTab: MenuBarPanelTab) -> PanelSamplingNeeds {
        switch self {
        // The Battery tab lists the apps using significant energy.
        case .duo: return [.processes]
        case .bluetooth: return []
        case .panel: return panelTab.samplingNeeds
        case .keepAwake, .system, .network, .disk, .power: return tab?.samplingNeeds ?? []
        }
    }

    /// Everything the popovers on screen need; nothing when none shows.
    static func samplingNeeds(shown kinds: some Sequence<Self>, panelTab: MenuBarPanelTab) -> PanelSamplingNeeds {
        kinds.reduce(into: PanelSamplingNeeds()) { $0.formUnion($1.samplingNeeds(panelTab: panelTab)) }
    }
}
