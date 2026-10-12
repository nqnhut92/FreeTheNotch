import SwiftUI
import Testing

struct MarqueeTextTests {
    @Test(arguments: [(CGFloat(220), CGFloat(100)), (20, 0), (10, 0), (0, 0)])
    func singleCopyWidthFromTheLoop(loopWidth: CGFloat, expected: CGFloat) {
        // The loop is two copies with a 20 pt gap.
        #expect(MarqueeText.textWidth(fromLoopWidth: loopWidth) == expected)
    }

    @Test func aPassMovesOneCopyAndTheGapAtThirtyPointsASecond() {
        #expect(MarqueeText.scrollDuration(textWidth: 90) == 3)
        #expect(MarqueeText.scrollDistance(textWidth: 100) == 120)
    }

    @Test func onlyAFittingCentredTextRestsOffTheLeadingEdge() {
        #expect(MarqueeText.restingOffset(textWidth: 100, frameWidth: 200, alignment: .center) == 50)
        #expect(MarqueeText.restingOffset(textWidth: 200, frameWidth: 200, alignment: .center) == 0)
        #expect(MarqueeText.restingOffset(textWidth: 100, frameWidth: 200, alignment: .leading) == 0)
        // Overflowing text scrolls from the leading edge.
        #expect(MarqueeText.restingOffset(textWidth: 300, frameWidth: 200, alignment: .center) == 0)
    }

    @Test func rowHeightFollowsTheFont() {
        #expect(abs(MarqueeText.rowHeight(pointSize: 18) - 23.4) < 1e-9)
        #expect(MarqueeText.rowHeight(pointSize: 0) == 1)
    }
}
