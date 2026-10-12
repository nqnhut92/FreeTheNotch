import Foundation
import Testing

struct BluetoothToolParserTests {
    /// Trimmed from a real `system_profiler SPBluetoothDataType -json`: AirPods
    /// with per-part levels (curly apostrophe), a Keychron keyboard that
    /// reports no battery, a mouse with one level, and two devices that are
    /// not connected.
    private static let profiler = Data(
        """
        {"SPBluetoothDataType": [{
          "controller_properties": {"controller_state": "attrib_on"},
          "device_connected": [
            {"Nick\u{2019}s AirPods Pro": {"device_address": "AA:AA", "device_minorType": "Headphones",
              "device_batteryLevelLeft": "85%", "device_batteryLevelRight": "90%",
              "device_batteryLevelCase": "40%"}},
            {"Keychron K2": {"device_address": "BB:BB", "device_minorType": "Keyboard"}},
            {"MX Master 3": {"device_address": "CC:CC", "device_minorType": "Mouse",
              "device_batteryLevelMain": "70%"}}
          ],
          "device_not_connected": [
            {"AirPods Max": {"device_address": "DD:DD", "device_minorType": "Headphones"}},
            {"Old AirPods": {"device_batteryLevelLeft": "20%", "device_batteryLevelCase": "55%"}}
          ]
        }]}
        """.utf8)

    @Test func keyboardWithoutBatteryReportingHasNoLevel() {
        #expect(BluetoothToolParser.batteryPercent(name: "Keychron K2", systemProfiler: Self.profiler) == nil)
        #expect(BluetoothToolParser.batteryParts(name: "Keychron K2", systemProfiler: Self.profiler) == nil)
    }

    @Test func combinedLevelIsTheHighestPart() {
        #expect(BluetoothToolParser.batteryPercent(name: "AirPods Pro", systemProfiler: Self.profiler) == 90)
        #expect(BluetoothToolParser.batteryPercent(name: "MX Master 3", systemProfiler: Self.profiler) == 70)
    }

    @Test func partsMatchAcrossApostropheSpellings() {
        let parts = BluetoothToolParser.batteryParts(name: "Nick's AirPods Pro", systemProfiler: Self.profiler)
        #expect(parts == BTBatteryParts(left: 85, right: 90, caseLevel: 40))
    }

    @Test func disconnectedDevicesHaveNoConnectedLevel() {
        #expect(BluetoothToolParser.batteryPercent(name: "Old AirPods", systemProfiler: Self.profiler) == nil)
    }

    @Test func nearbyListsDevicesWithLevels() {
        let nearby = BluetoothToolParser.nearbyDevices(systemProfiler: Self.profiler)
        #expect(nearby.map(\.name) == ["MX Master 3", "Nick\u{2019}s AirPods Pro", "Old AirPods"])
        #expect(nearby.map(\.batteryPercent) == [70, 90, 55])
        #expect(nearby.map(\.kind) == [.mouse, .airpods, .airpods])
        #expect(nearby[2].parts == BTBatteryParts(left: 20, right: nil, caseLevel: 55))
        #expect(nearby.allSatisfy { !$0.isConnected && $0.id.hasPrefix("nearby.") })
    }

    @Test func accessoryTypesByLowercasedName() {
        #expect(
            BluetoothToolParser.accessoryTypes(systemProfiler: Self.profiler) == [
                "nick\u{2019}s airpods pro": "Headphones",
                "keychron k2": "Keyboard",
                "mx master 3": "Mouse",
                "airpods max": "Headphones",
            ])
    }

    @Test func malformedOutputYieldsNothing() {
        let junk = Data("not json".utf8)
        #expect(BluetoothToolParser.batteryPercent(name: "AirPods", systemProfiler: junk) == nil)
        #expect(BluetoothToolParser.nearbyDevices(systemProfiler: junk).isEmpty)
        #expect(BluetoothToolParser.accessoryTypes(systemProfiler: junk).isEmpty)
    }

    @Test func pmsetAccessoryLines() {
        let output = Data(
            """
            Now drawing from 'AC Power'
             -InternalBattery-0 (id=4653155)\t100%; charged; 0:00 remaining present: true
             -Magic Mouse (id=1234)\t62%; discharging; (no estimate) present: true

            """.utf8)
        #expect(BluetoothToolParser.batteryPercent(name: "Magic Mouse", pmset: output) == 62)
        #expect(BluetoothToolParser.batteryPercent(name: "Keychron K2", pmset: output) == nil)
        #expect(BluetoothToolParser.batteryPercent(name: "", pmset: output) == nil)
    }

    @Test(arguments: [
        ("Keychron K2", String?.some("Keyboard"), BTKind.keyboard),
        ("Beats Flex", nil, .airpods),
        ("Magic Trackpad", "Mouse", .trackpad),
        ("Logitech MX Anywhere", nil, .mouse),
        ("Soundcore", "Speaker", .speaker),
        ("Xbox Controller", "Gamepad", .gamepad),
        ("Thing", nil, .generic),
    ])
    func kindFromNameAndType(_ name: String, minorType: String?, expected: BTKind) {
        #expect(BTKind(name: name, minorType: minorType) == expected)
    }

    @Test func batteryValuesAcceptNumbersAndPercentStrings() {
        #expect(BluetoothToolParser.batteryValue("85%") == 85)
        #expect(BluetoothToolParser.batteryValue(85.0) == 85)
        #expect(BluetoothToolParser.batteryValue(70) == 70)
        #expect(BluetoothToolParser.batteryValue(101) == nil)
        #expect(BluetoothToolParser.batteryValue("n/a") == nil)
    }

    @Test func mergedPartsKeepTheHigherLevel() {
        let a = BTBatteryParts(left: 80, right: nil, caseLevel: 30)
        let b = BTBatteryParts(left: 70, right: 60, caseLevel: nil)
        #expect(a.merged(with: b) == BTBatteryParts(left: 80, right: 60, caseLevel: 30))
        #expect(BTBatteryParts().isEmpty)
    }
}
