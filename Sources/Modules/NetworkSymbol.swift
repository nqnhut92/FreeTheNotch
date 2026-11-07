import Foundation

/// What the Duo glyph's centre shows for the network.
///
/// A wired link wins over Wi-Fi: on a desk with a cable plugged in, the
/// Ethernet symbol says where traffic goes, the way macOS's own menu bar
/// swaps the Wi-Fi fan for `<···>` when Ethernet is connected.
enum NetworkSymbol: Equatable {
    case ethernet
    /// 0 = Wi-Fi off or not associated, 1–3 = arcs lit.
    case wifi(bars: Int)

    init(hasWiredLink: Bool, wifiBars: Int) {
        self = hasWiredLink ? .ethernet : .wifi(bars: wifiBars)
    }

    var accessibilityDescription: String {
        switch self {
        case .ethernet: return "Ethernet connected"
        case .wifi(let bars) where bars > 0: return "Wi-Fi \(bars) of 3 bars"
        case .wifi: return "Wi-Fi not connected"
        }
    }
}
