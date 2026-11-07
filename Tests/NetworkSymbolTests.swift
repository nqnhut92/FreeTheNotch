import Foundation
import Testing

struct NetworkSymbolTests {
    @Test(arguments: [
        (true, 3, NetworkSymbol.ethernet),
        (true, 0, NetworkSymbol.ethernet),
        (false, 2, NetworkSymbol.wifi(bars: 2)),
        (false, 0, NetworkSymbol.wifi(bars: 0)),
    ])
    func wiredLinkWinsOverWiFi(hasWiredLink: Bool, wifiBars: Int, expected: NetworkSymbol) {
        #expect(NetworkSymbol(hasWiredLink: hasWiredLink, wifiBars: wifiBars) == expected)
    }

    @Test(arguments: [
        (NetworkSymbol.ethernet, "Ethernet connected"),
        (NetworkSymbol.wifi(bars: 3), "Wi-Fi 3 of 3 bars"),
        (NetworkSymbol.wifi(bars: 1), "Wi-Fi 1 of 3 bars"),
        (NetworkSymbol.wifi(bars: 0), "Wi-Fi not connected"),
    ])
    func spokenDescription(symbol: NetworkSymbol, expected: String) {
        #expect(symbol.accessibilityDescription == expected)
    }
}
