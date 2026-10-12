import Foundation
import Testing

/// A plist value with every nested binary plist (the `Configuration`
/// blobs) decoded, so two encodings of the same content compare equal:
/// dictionary key order, and so the bytes, differs between encodings.
func normalizedPlist(_ value: Any) -> Any {
    if let data = value as? Data,
        let decoded = try? PropertyListSerialization.propertyList(from: data, format: nil)
    {
        return normalizedPlist(decoded)
    }
    if let dictionary = value as? [String: Any] { return dictionary.mapValues(normalizedPlist) }
    if let array = value as? [Any] { return array.map(normalizedPlist) }
    return value
}

func plistsMatch(_ a: Any, _ b: Any) -> Bool {
    NSArray(array: [normalizedPlist(a)]).isEqual(to: [normalizedPlist(b)])
}

struct WallpaperIndexTests {
    private static let imageURL = URL(fileURLWithPath: "/tmp/FreeTheNotch/ArtworkWallpaper/artwork-1.png")
    private static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let block = WallpaperIndex.imageBlock(imageURL: imageURL, date: date)

    private static func isBlock(_ value: Any?) -> Bool {
        guard let value = value as? [String: Any] else { return false }
        return NSDictionary(dictionary: value).isEqual(to: block)
    }

    private static func dictionary(_ value: Any?) throws -> [String: Any] {
        try #require(value as? [String: Any])
    }

    @Test func imageBlockHoldsOneImageFile() throws {
        let block = Self.block
        #expect(block["LastSet"] as? Date == Self.date)
        #expect(block["LastUse"] as? Date == Self.date)
        let content = try Self.dictionary(block["Content"])
        #expect(content["Shuffle"] as? String == "$null")
        let choices = try #require(content["Choices"] as? [[String: Any]])
        #expect(choices.count == 1)
        #expect(choices[0]["Provider"] as? String == "com.apple.wallpaper.choice.image")
        #expect((choices[0]["Files"] as? [Any])?.isEmpty == true)
        let data = try #require(choices[0]["Configuration"] as? Data)
        let configuration = try Self.dictionary(try PropertyListSerialization.propertyList(from: data, format: nil))
        #expect(configuration["type"] as? String == "imageFile")
        #expect(try Self.dictionary(configuration["url"])["relative"] as? String == Self.imageURL.absoluteString)
    }

    @Test func topLevelEntriesAreAlwaysWritten() throws {
        let patched = WallpaperIndex.patchedIndex(["Other": "kept"], block: Self.block)
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            let entry = try Self.dictionary(patched[key])
            #expect(Self.isBlock(entry["Desktop"]))
            #expect(Self.isBlock(entry["Idle"]))
            #expect(entry["Type"] as? String == "individual")
        }
        #expect(patched["Other"] as? String == "kept")
        #expect(patched["Displays"] == nil)
        #expect(patched["Spaces"] == nil)
    }

    @Test func topLevelEntriesKeepTheirOtherKeys() throws {
        let index: [String: Any] = ["SystemDefault": ["Type": "linked", "Extra": 1]]
        let entry = try Self.dictionary(WallpaperIndex.patchedIndex(index, block: Self.block)["SystemDefault"])
        #expect(entry["Type"] as? String == "individual")
        #expect(entry["Extra"] as? Int == 1)
    }

    @Test func displaysGetTheBlockAndKeepTypeOnlyWhereSet() throws {
        let index: [String: Any] = [
            "Displays": [
                "typed": ["Type": "linked"],
                "untyped": ["Extra": true],
                "odd": "not a dictionary",
            ]
        ]
        let displays = try Self.dictionary(WallpaperIndex.patchedIndex(index, block: Self.block)["Displays"])
        let typed = try Self.dictionary(displays["typed"])
        #expect(Self.isBlock(typed["Desktop"]) && Self.isBlock(typed["Idle"]))
        #expect(typed["Type"] as? String == "individual")
        let untyped = try Self.dictionary(displays["untyped"])
        #expect(Self.isBlock(untyped["Desktop"]) && Self.isBlock(untyped["Idle"]))
        #expect(untyped["Type"] == nil)
        #expect(untyped["Extra"] as? Bool == true)
        #expect(displays["odd"] as? String == "not a dictionary")
    }

    @Test func spacesPatchTheirDefaultAndNestedDisplays() throws {
        let index: [String: Any] = [
            "Spaces": [
                "space-1": [
                    "Default": ["Type": "linked"],
                    "Displays": ["display-1": ["Extra": 2], "odd": 3],
                ],
                "space-2": ["Other": "kept"],
                "odd": 4,
            ]
        ]
        let spaces = try Self.dictionary(WallpaperIndex.patchedIndex(index, block: Self.block)["Spaces"])
        let first = try Self.dictionary(spaces["space-1"])
        let spaceDefault = try Self.dictionary(first["Default"])
        #expect(Self.isBlock(spaceDefault["Desktop"]) && Self.isBlock(spaceDefault["Idle"]))
        #expect(spaceDefault["Type"] as? String == "individual")
        let nested = try Self.dictionary(first["Displays"])
        let display = try Self.dictionary(nested["display-1"])
        #expect(Self.isBlock(display["Desktop"]) && Self.isBlock(display["Idle"]))
        #expect(display["Type"] == nil)
        #expect(display["Extra"] as? Int == 2)
        #expect(nested["odd"] as? Int == 3)
        let second = try Self.dictionary(spaces["space-2"])
        #expect(second.count == 1)
        #expect(second["Other"] as? String == "kept")
        #expect(spaces["odd"] as? Int == 4)
    }

    @Test func patchedDataIsABinaryPlist() throws {
        let original: [String: Any] = ["Displays": ["d": ["Type": "linked"]]]
        let xml = try PropertyListSerialization.data(fromPropertyList: original, format: .xml, options: 0)
        let data = try #require(WallpaperIndex.patched(xml, imageURL: Self.imageURL, date: Self.date))
        #expect(data.starts(with: Data("bplist00".utf8)))
        let decoded = try Self.dictionary(try PropertyListSerialization.propertyList(from: data, format: nil))
        let expected = WallpaperIndex.patchedIndex(original, block: Self.block)
        #expect(plistsMatch(decoded, expected))
    }

    @Test func unreadableDataIsNotPatched() {
        #expect(WallpaperIndex.patched(Data("not a plist".utf8), imageURL: Self.imageURL, date: Self.date) == nil)
        let array = try? PropertyListSerialization.data(fromPropertyList: [1, 2], format: .binary, options: 0)
        #expect(WallpaperIndex.patched(array ?? Data(), imageURL: Self.imageURL, date: Self.date) == nil)
    }
}
