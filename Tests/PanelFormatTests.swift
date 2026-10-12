import Foundation
import Testing

struct PanelFormatTests {
    private static let english = Locale(identifier: "en_US")
    private static let vietnamese = Locale(identifier: "vi_VN")

    @Test(
        arguments: [
            (0.0, "0 B"),
            (1023, "1,023 B"),  // String(format:locale:) groups thousands
            (1024, "1 KB"),
            (506 * 1024, "506 KB"),
            (1_048_575, "1 MB"),  // 1023.999 KB rounds up into the next unit
            (26 * 1024 * 1024, "26 MB"),
        ] as [(Double, String)])
    func bytes(_ value: Double, expected: String) {
        #expect(PanelFormat.bytes(value, locale: Self.english) == expected)
    }

    @Test(
        arguments: [
            (500.0, "500 B"),
            (7300, "7.3 KB"),
            (9_960, "10 KB"),  // 9.96 rounds to 10, which takes no decimal
            (999_960, "1.0 MB"),
            (616e9, "616 GB"),
        ] as [(Double, String)])
    func diskBytes(_ value: Double, expected: String) {
        #expect(PanelFormat.diskBytes(value, locale: Self.english) == expected)
    }

    @Test func usesTheLocaleDecimalSeparator() {
        #expect(PanelFormat.diskBytes(7300, locale: Self.vietnamese) == "7,3 KB")
        #expect(PanelFormat.rate(3400, locale: Self.vietnamese) == "3,3 KB/s")
        #expect(PanelFormat.watts(8.5, locale: Self.vietnamese) == "8,5 W")
        #expect(PanelFormat.diskBytesPrecise(42.594e12, locale: Self.vietnamese) == "42,59 TB")
    }

    @Test func rates() {
        #expect(PanelFormat.rate(1_048_575, locale: Self.english) == "1.0 MB/s")
        #expect(PanelFormat.rate(500, locale: Self.english) == "500 B/s")
        #expect(PanelFormat.bits(45_200_000, locale: Self.english) == "45 Mbps")
        #expect(PanelFormat.bits(4_520_000, locale: Self.english) == "4.5 Mbps")
    }

    @Test func smallValues() {
        #expect(PanelFormat.watts(25, locale: Self.english) == "25 W")
        #expect(PanelFormat.percent(0.25, locale: Self.english) == "25%")
        #expect(PanelFormat.temperature(celsius: 81.4, locale: Self.english) == "81 °C")
        #expect(PanelFormat.temperature(celsius: nil) == "-")
    }

    @Test(
        arguments: [
            (0.0, "0min"),
            (-5, "0min"),
            (42 * 60, "42min"),
            (5 * 3600 + 13 * 60, "5h 13min"),
            (3 * 86_400 + 12 * 3600 + 5 * 60, "3d 12h"),
        ] as [(TimeInterval, String)])
    func uptime(_ seconds: TimeInterval, expected: String) {
        #expect(PanelFormat.uptime(seconds) == expected)
    }

    @Test(
        arguments: [
            (0.0, 1024.0, 1.0),
            (3, 1024, 5),
            (1500, 1024, 2048),
            (1_500_000, 1024, 2_097_152),
            (42, 1000, 50),
        ] as [(Double, Double, Double)])
    func graphCeiling(_ peak: Double, unitStep: Double, expected: Double) {
        #expect(PanelFormat.graphCeiling(peak, unitStep: unitStep) == expected)
    }
}
