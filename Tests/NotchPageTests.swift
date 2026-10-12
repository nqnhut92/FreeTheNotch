import CoreGraphics
import Testing

struct NotchPageTests {
    private func height(
        _ page: NotchPage = .home, player: Bool = true, upNext: Bool = false,
        quote: Bool = false, strip: Bool = false, weeks: Int = 5
    ) -> CGFloat {
        NotchPage.bodyHeight(
            for: page, showsPlayer: player, showsUpNext: upNext,
            homeQuote: quote, homeBatteryStrip: strip, calendarWeeks: weeks)
    }

    @Test(arguments: [
        (NotchPage.clipboard, CGFloat(230)),
        (.aiUsage, 290),
        (.timer, 200),
        (.calculator, 212),
        (.qr, 300),
    ])
    func otherPagesKeepTheirBody(_ page: NotchPage, expected: CGFloat) {
        // Home's rows, Up next and the month never change another page.
        #expect(height(page) == expected)
        #expect(height(page, upNext: true, quote: true, strip: true, weeks: 6) == expected)
        #expect(height(page, player: false, weeks: 4) == expected)
    }

    @Test func homeWithThePlayer() {
        #expect(height() == 176)
        // Up next adds its line; the player keeps its size.
        #expect(height(upNext: true) == 206)
    }

    @Test func homeExtrasStackUnderAndAboveThePlayer() {
        // Strip 92 + 10 spacing; quote 8 gap + 22 + 10 spacing.
        #expect(height(strip: true) == 278)
        #expect(height(quote: true) == 216)
        #expect(height(quote: true, strip: true) == 318)
        #expect(height(upNext: true, quote: true, strip: true) == 348)
    }

    /// 4 + 24 + 8 + 14 + 8 above the grid, rows of 30 with 6 between, 12 below.
    @Test(arguments: [(4, CGFloat(208)), (5, 244), (6, 280)])
    func withoutThePlayerHomeFollowsTheMonth(_ weeks: Int, expected: CGFloat) {
        #expect(height(player: false, weeks: weeks) == expected)
        #expect(height(player: false, quote: true, strip: true, weeks: weeks) == expected + 142)
    }

    @Test func aMonthWithoutWeeksStillTakesOneRow() {
        #expect(height(player: false, weeks: 0) == 100)
        #expect(height(player: false, weeks: -1) == height(player: false, weeks: 1))
    }

    @Test func upNextNeedsThePlayer() {
        #expect(height(player: false, upNext: true) == height(player: false))
    }

    /// The fixed window is sized to `tallest`; no state may outgrow it.
    @Test func tallestFitsEveryState() {
        var largest: CGFloat = 0
        for page in NotchPage.allCases {
            for player in [false, true] {
                for upNext in [false, true] {
                    for quote in [false, true] {
                        for strip in [false, true] {
                            for weeks in 0...6 {
                                let h = height(
                                    page, player: player, upNext: upNext, quote: quote, strip: strip, weeks: weeks)
                                #expect(h <= NotchPage.tallest)
                                largest = max(largest, h)
                            }
                        }
                    }
                }
            }
        }
        // A 6-week month with the strip and the quote: 280 + 102 + 40.
        #expect(largest == NotchPage.tallest)
        #expect(NotchPage.tallest == 422)
    }

    @Test func pageIdentityIsItsRawValue() {
        #expect(NotchPage.allCases.map(\.id) == ["home", "clipboard", "aiUsage", "timer", "calculator", "qr"])
    }
}
