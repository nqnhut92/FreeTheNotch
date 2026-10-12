import CoreGraphics

/// A page of the open island. Also the app-wide height model: the island's
/// shape, its hit area and the fixed window size all come from here.
enum NotchPage: String, CaseIterable, Identifiable {
    case home, clipboard, aiUsage, timer, calculator, qr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .clipboard: return "Clipboard"
        case .aiUsage: return "AI Usage"
        case .timer: return "Timer"
        case .qr: return "QR"
        case .calculator: return "Calculator"
        }
    }

    /// SF Symbol name. The calculator's is not drawn (`NotchPageIcon` draws
    /// its own glyph) but stays for anything that needs a symbol name.
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .clipboard: return "doc.on.doc"
        case .aiUsage: return "chart.bar.xaxis"
        case .timer: return "timer"
        case .qr: return "qrcode"
        case .calculator: return "plus.forwardslash.minus"
        }
    }

    // MARK: Heights

    /// Body height under the menu-bar band, before the Home extras. QR needs
    /// the code plus the field and the buttons, so it is the tallest page.
    var baseBodyHeight: CGFloat {
        switch self {
        case .home: return 176
        case .clipboard: return 230
        case .aiUsage: return 290
        case .timer: return 200
        case .qr: return 300
        case .calculator: return 212
        }
    }

    /// The Up next line under the player. The player keeps its size and the
    /// island grows by this instead.
    static let upNextHeight: CGFloat = 30

    /// Battery strip under the Home content.
    static let batteryStripHeight: CGFloat = 92
    static let batteryStripSpacing: CGFloat = 10

    /// Quote of the Day line at the top of Home (same spacing as the strip).
    static let quoteHeight: CGFloat = 22
    /// Room between the icon row and the quote.
    static let quoteTopGap: CGFloat = 8

    /// Bottom padding of the open island's body.
    static let bottomPadding: CGFloat = 12

    /// Height the Home extras add: the battery strip and the quote line.
    static func homeExtrasHeight(quote: Bool, batteryStrip: Bool) -> CGFloat {
        (batteryStrip ? batteryStripHeight + batteryStripSpacing : 0)
            + (quote ? quoteTopGap + quoteHeight + batteryStripSpacing : 0)
    }

    /// Body height for a given state. Home shows the player when there is a
    /// media session and the standalone month (its height follows the week
    /// count) when there is none; Up next only exists beside the player.
    static func bodyHeight(
        for page: NotchPage, showsPlayer: Bool, showsUpNext: Bool,
        homeQuote: Bool, homeBatteryStrip: Bool, calendarWeeks: Int
    ) -> CGFloat {
        guard page == .home else { return page.baseBodyHeight }
        let extras = homeExtrasHeight(quote: homeQuote, batteryStrip: homeBatteryStrip)
        guard showsPlayer else { return StandaloneCalendarMetrics.bodyHeight(weeks: calendarWeeks) + extras }
        return page.baseBodyHeight + (showsUpNext ? upNextHeight : 0) + extras
    }

    /// Window height budget: the tallest body any state can ask for (a
    /// 6-week month with the battery strip and the quote line).
    static let tallest: CGFloat = max(
        qr.baseBodyHeight,
        StandaloneCalendarMetrics.bodyHeight(weeks: 6) + homeExtrasHeight(quote: true, batteryStrip: true),
        home.baseBodyHeight + upNextHeight + homeExtrasHeight(quote: true, batteryStrip: true))
}

/// Fixed sizes of the standalone month pane, so the island height can be
/// computed from the number of weeks.
enum StandaloneCalendarMetrics {
    static let topPadding: CGFloat = 4
    static let headerHeight: CGFloat = 24
    static let weekdayRowHeight: CGFloat = 14
    static let sectionSpacing: CGFloat = 8
    /// Atoll's day cell minHeight.
    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 6

    static func bodyHeight(weeks: Int) -> CGFloat {
        let rows = CGFloat(max(weeks, 1))
        return topPadding + headerHeight + sectionSpacing + weekdayRowHeight + sectionSpacing
            + rows * rowHeight + (rows - 1) * rowSpacing + NotchPage.bottomPadding
    }
}
