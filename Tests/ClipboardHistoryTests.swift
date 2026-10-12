import Foundation
import Testing

struct ClipboardHistoryTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static func item(_ text: String, hoursAgo: Double = 0, pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), text: text, date: now.addingTimeInterval(-hoursAgo * 3600), isPinned: pinned)
    }

    @Test func limitKeepsPinnedAndTheNewestUnpinned() {
        let pinned = Self.item("pinned", hoursAgo: 50, pinned: true)
        let a = Self.item("a", hoursAgo: 1)
        let b = Self.item("b", hoursAgo: 2)
        let c = Self.item("c", hoursAgo: 3)
        let (kept, dropped) = ClipboardHistory.applyingLimit([a, pinned, b, c], limit: 2)
        #expect(kept.map(\.text) == ["pinned", "a", "b"])
        #expect(dropped.map(\.text) == ["c"])
    }

    @Test func zeroLimitKeepsOnlyPinned() {
        let pinned = Self.item("pinned", pinned: true)
        let (kept, dropped) = ClipboardHistory.applyingLimit([Self.item("a"), pinned], limit: 0)
        #expect(kept.map(\.text) == ["pinned"])
        #expect(dropped.map(\.text) == ["a"])
    }

    @Test(arguments: [
        (ClipboardRetention.keep, [String]()),
        (.onQuit, []),
        (.oneDay, ["two days", "four days"]),
        (.threeDays, ["four days"]),
    ])
    func retentionExpiresOnlyOldUnpinnedItems(_ retention: ClipboardRetention, expected: [String]) {
        let items = [
            Self.item("fresh", hoursAgo: 12),
            Self.item("two days", hoursAgo: 48),
            Self.item("four days", hoursAgo: 96),
            Self.item("pinned", hoursAgo: 240, pinned: true),
        ]
        let expired = ClipboardHistory.expired(items, retention: retention, now: Self.now)
        #expect(expired.map(\.text) == expected)
    }

    @Test func maximumAges() {
        #expect(ClipboardRetention.keep.maximumAge == nil)
        #expect(ClipboardRetention.onQuit.maximumAge == nil)
        #expect(ClipboardRetention.oneDay.maximumAge == 86_400)
        #expect(ClipboardRetention.threeDays.maximumAge == 259_200)
    }

    @Test func latestIgnoresListOrder() {
        // Pinned items are listed first, so the newest copy can be second.
        let pinned = Self.item("old pinned", hoursAgo: 30, pinned: true)
        let newest = Self.item("newest", hoursAgo: 0)
        #expect(ClipboardHistory.latest(in: [pinned, newest])?.text == "newest")
        #expect(ClipboardHistory.latest(in: []) == nil)
    }

    @Test func previewFlattensAndTruncatesText() {
        #expect(Self.item("one\ntwo").preview == "one two")
        let long = String(repeating: "x", count: 200)
        #expect(Self.item(long).preview == String(repeating: "x", count: 140) + "…")
    }

    @Test func decodesTextOnlyHistory() throws {
        // Older history entries have no image fields.
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"hi","date":0,"isPinned":true}]"#
        let items = try JSONDecoder().decode([ClipboardItem].self, from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items[0].isPinned)
        #expect(!items[0].isImage)
    }
}
