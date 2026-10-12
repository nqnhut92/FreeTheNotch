import Foundation
import Testing

struct CPUSamplingTests {
    // MARK: Load ticks

    @Test func busyFractionOfElapsedTicks() throws {
        let before = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let after = CPUTicks(user: 200, system: 100, idle: 1550, nice: 0)
        // 150 busy ticks out of 850.
        #expect(try #require(after.busyFraction(since: before)) == 150.0 / 850.0)
    }

    @Test func countersThatWrapStillGiveTheDelta() throws {
        let before = CPUTicks(user: .max - 9, system: 5, idle: .max - 79, nice: 0)
        let after = CPUTicks(user: 10, system: 5, idle: 0, nice: 0)
        // 20 user ticks and 80 idle ticks across the wrap.
        #expect(try #require(after.busyFraction(since: before)) == 0.2)
    }

    @Test func noElapsedTicksHasNoFraction() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        #expect(ticks.busyFraction(since: ticks) == nil)
    }

    // MARK: Core topology

    /// M4 Pro: logical CPUs 0…3 are Efficiency cores, 4…13 Performance, while
    /// perflevel0 is Performance.
    @Test func mapsSamplerSlotsToCoreClasses() {
        let cores = (0..<14).map { (id: $0, type: $0 < 4 ? "E" : "P") }
        let groups = CPUCoreTopology.groups(
            levels: [(name: "Performance", count: 10), (name: "Efficiency", count: 4)],
            cores: cores, slots: Array(0..<14))
        #expect(
            groups == [
                CPUCoreGroup(name: "Performance", indices: Array(4..<14)),
                CPUCoreGroup(name: "Efficiency", indices: Array(0..<4)),
            ])
    }

    @Test func followsSlotOrderNotLogicalIDs() {
        // Sampler slot 0 is logical CPU 2 (a P core), and so on.
        let groups = CPUCoreTopology.groups(
            levels: [(name: "Performance", count: 2), (name: "Efficiency", count: 2)],
            cores: [(id: 0, type: "E"), (id: 1, type: "E"), (id: 2, type: "P"), (id: 3, type: "P")],
            slots: [2, 0, 3, 1])
        #expect(groups.map(\.indices) == [[0, 2], [1, 3]])
    }

    @Test func fallsBackToOneGroupWhenCountsDisagree() {
        let groups = CPUCoreTopology.groups(
            levels: [(name: "Performance", count: 3), (name: "Efficiency", count: 4)],
            cores: (0..<6).map { (id: $0, type: $0 < 4 ? "E" : "P") },
            slots: Array(0..<6))
        #expect(groups == [CPUCoreGroup(name: "CPU", indices: Array(0..<6))])
    }

    @Test func noSlotsMeansNoGroups() {
        #expect(CPUCoreTopology.groups(levels: [], cores: [], slots: []).isEmpty)
        #expect(CPUCoreTopology.groups(for: 0).isEmpty)
    }

    @Test func fasterCoresGetWiderBars() {
        #expect(CPUCoreGroup(name: "Super", indices: []).weight == 1.5)
        #expect(CPUCoreGroup(name: "Performance", indices: []).weight == 1.25)
        #expect(CPUCoreGroup(name: "Efficiency", indices: []).weight == 1)
    }

    // MARK: Temperature sensors

    @Test(
        arguments: [
            ("Apple M1", CPUTemperaturePlatform.appleM1Family),
            ("Apple M2 Max", .appleM2Family),
            ("Apple M3 Pro", .appleM3Family),
            ("Apple M4 Pro", .appleM4Family),
            ("  Apple M5  ", .appleM5Family),
            ("Apple M6", .unmappedAppleSilicon),
            ("Apple M10", .unmappedAppleSilicon),
            ("Apple A18 Pro", .generic),
            ("Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz", .generic),
        ] as [(String, CPUTemperaturePlatform)])
    func platformFromBrandString(_ brand: String, expected: CPUTemperaturePlatform) {
        #expect(CPUTemperatureSelector.platform(brandString: brand) == expected)
    }

    @Test func coreKeysArePerGeneration() {
        #expect(CPUTemperatureSelector.isCPUCoreKey("Te05", platform: .appleM4Family))
        #expect(!CPUTemperatureSelector.isCPUCoreKey("Tp1h", platform: .appleM4Family))
        #expect(CPUTemperatureSelector.isCPUCoreKey("Tp1h", platform: .appleM2Family))
        #expect(!CPUTemperatureSelector.isCPUCoreKey("Tp01", platform: .unmappedAppleSilicon))
    }

    @Test func tfKeysCountOnlyOnM3() {
        #expect(CPUTemperatureSelector.isCPUTemperatureKey("Tf04", platform: .appleM3Family))
        #expect(!CPUTemperatureSelector.isCPUTemperatureKey("Tf04", platform: .appleM4Family))
        #expect(CPUTemperatureSelector.isCPUTemperatureKey("Tp09", platform: .generic))
        #expect(!CPUTemperatureSelector.isCPUTemperatureKey("Tg05", platform: .appleM4Family))
    }

    // MARK: Battery maximum capacity

    private func capacity(_ json: String) throws -> Int? {
        MaxCapacityProbe.percent(in: try JSONSerialization.jsonObject(with: Data(json.utf8)))
    }

    @Test func readsTheNestedPercentString() throws {
        let json = """
            {"SPPowerDataType": [{"_name": "spbattery_information",
              "sppower_battery_health_info": {"sppower_battery_cycle_count": 120,
                "sppower_battery_health": "Good",
                "sppower_battery_health_maximum_capacity": "98%"}}]}
            """
        #expect(try capacity(json) == 98)
    }

    @Test func readsANumber() throws {
        #expect(try capacity(#"{"_items": [{"Maximum Capacity": 87}]}"#) == 87)
    }

    @Test(arguments: [
        #"{"sppower_battery_health_maximum_capacity": "101%"}"#,
        #"{"sppower_battery_health_maximum_capacity": "0%"}"#,
        #"{"sppower_battery_health_maximum_capacity": true}"#,
        #"{"sppower_battery_cycle_count": 98}"#,
    ])
    func ignoresImplausibleValues(_ json: String) throws {
        #expect(try capacity(json) == nil)
    }
}
