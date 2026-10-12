import Testing

struct BatteryTileTests {
    private static func airPods(
        _ id: String = "pods", left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, overall: Int? = nil
    ) -> BTDevice {
        BTDevice(
            id: id, name: "Nick's AirPods", kind: .airpods, isConnected: true, batteryPercent: overall,
            parts: BTBatteryParts(left: left, right: right, caseLevel: caseLevel))
    }

    private static func device(_ id: String, kind: BTKind = .mouse, percent: Int?) -> BTDevice {
        BTDevice(id: id, name: id.capitalized, kind: kind, isConnected: true, batteryPercent: percent)
    }

    @Test func closeBudsShareOneRingAtTheLowerLevel() {
        let tiles = BatteryTile.tiles(connected: [Self.airPods(left: 80, right: 90, caseLevel: 50)], nearby: [])
        #expect(tiles.map(\.id) == ["pods.buds", "pods.case"])
        #expect(tiles.map(\.percent) == [80, 50])
        #expect(tiles.map(\.label) == ["AirPods", "Case"])
    }

    @Test func distantBudsSplit() {
        let tiles = BatteryTile.tiles(connected: [Self.airPods(left: 80, right: 91)], nearby: [])
        #expect(tiles.map(\.id) == ["pods.l", "pods.r"])
        #expect(tiles.map(\.percent) == [80, 91])
    }

    @Test func aSingleBudGetsItsOwnRing() {
        let tiles = BatteryTile.tiles(connected: [Self.airPods(right: 40, caseLevel: 100)], nearby: [])
        #expect(tiles.map(\.label) == ["Right bud", "Case"])
    }

    @Test func airPodsWithoutPartsFallBackToTheirLevel() {
        let tiles = BatteryTile.tiles(connected: [Self.airPods(overall: 70)], nearby: [])
        #expect(tiles == [BatteryTile(id: "pods", icon: "airpodspro", percent: 70, label: "Nick's AirPods")])
        #expect(BatteryTile.tiles(connected: [Self.airPods()], nearby: []).isEmpty)
    }

    @Test func devicesWithoutALevelAreSkipped() {
        let tiles = BatteryTile.tiles(
            connected: [Self.device("mouse", percent: 55), Self.device("keychron", kind: .keyboard, percent: nil)],
            nearby: [])
        #expect(tiles == [BatteryTile(id: "mouse", icon: "computermouse.fill", percent: 55, label: "Mouse")])
    }

    @Test func connectedComeFirstAndTheCardHoldsSix() {
        let connected = (1...4).map { Self.device("m\($0)", percent: $0 * 10) }
        let nearby = [Self.airPods("case", left: 10, right: 60, caseLevel: 30)]
        let tiles = BatteryTile.tiles(connected: connected, nearby: nearby)
        #expect(tiles.map(\.id) == ["m1", "m2", "m3", "m4", "case.l", "case.r"])
    }

    @Test(arguments: [(45, "45m"), (60, "1h 0m"), (125, "2h 5m")])
    func durations(_ minutes: Int, expected: String) {
        #expect(BatteryTile.duration(minutes: minutes) == expected)
    }

    @Test(arguments: [
        (100, false, BatteryRingTint.normal),
        (21, false, .normal),
        (20, false, .low),
        (11, false, .low),
        (10, false, .critical),
        (0, false, .critical),
        (5, true, .normal),
    ])
    func ringTint(percent: Int, charging: Bool, expected: BatteryRingTint) {
        #expect(BatteryRingTint(percent: percent, charging: charging) == expected)
    }
}
