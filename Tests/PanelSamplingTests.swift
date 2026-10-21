import Foundation
import Testing

struct PanelSamplingTests {
    // MARK: Demand

    @Test func samplesWhileAnyClientNeedsIt() {
        var demand = SamplingDemand<String>()
        let changes = [
            demand.set(true, by: "panel"),
            demand.set(true, by: "strip"),
            demand.set(false, by: "panel"),
        ]
        #expect(changes == [true, false, false])
        #expect(demand.isActive)
        let lastChange = demand.set(false, by: "strip")
        #expect(lastChange)
        #expect(!demand.isActive)
    }

    @Test func removingAnAbsentClientChangesNothing() {
        var demand = SamplingDemand<String>()
        let changed = demand.set(false, by: "panel")
        #expect(!changed)
        #expect(!demand.isActive)
    }

    // MARK: Popover needs

    static let cellNeeds: [(SideNotchPopoverKind, PanelSamplingNeeds)] = [
        (.duo, [.processes]),
        (.bluetooth, []),
        (.keepAwake, []),
        (.system, [.processes, .temperatures]),
        (.network, [.network]),
        (.disk, [.disks]),
        (.power, [.processes, .temperatures]),
    ]

    @Test(arguments: cellNeeds)
    func eachCellSamplesWhatItShows(kind: SideNotchPopoverKind, expected: PanelSamplingNeeds) {
        // The panel tab only matters for the full panel.
        #expect(kind.samplingNeeds(panelTab: .network) == expected)
    }

    static let tabNeeds: [(MenuBarPanelTab, PanelSamplingNeeds)] = [
        (.keepAwake, []),
        (.system, [.processes, .temperatures]),
        (.network, [.network]),
        (.disk, [.disks]),
        (.power, [.processes, .temperatures]),
        (.tools, []),
    ]

    @Test(arguments: tabNeeds)
    func fullPanelSamplesItsSelectedTab(tab: MenuBarPanelTab, expected: PanelSamplingNeeds) {
        #expect(SideNotchPopoverKind.panel.samplingNeeds(panelTab: tab) == expected)
    }

    /// A closed popover kept nettop and the per-app sampling running.
    @Test func nothingIsSampledWithNoPopoverShown() {
        #expect(SideNotchPopoverKind.samplingNeeds(shown: [], panelTab: .network).isEmpty)
    }

    @Test func shownPopoversAddUp() {
        let needs = SideNotchPopoverKind.samplingNeeds(shown: [.duo, .network], panelTab: .keepAwake)
        #expect(needs == [.processes, .network])
    }
}
