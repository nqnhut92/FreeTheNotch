import Foundation
import ImageIO
import Testing

/// The artwork wallpaper's file rules (AGENTS.md, Do not regress): the
/// backup is never overwritten, a restore puts it back and deletes it, a
/// failed restore keeps it. Every path is inside a fresh temp folder.
struct ArtworkWallpaperFilesTests {
    /// Counts WallpaperAgent restarts instead of killing anything.
    private final class RestartCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func increment() { lock.withLock { value += 1 } }
    }

    private struct Sandbox {
        let root: URL
        let files: ArtworkWallpaperFiles
        let restarts: RestartCounter
        var exportDirectory: URL { root.appendingPathComponent("Export", isDirectory: true) }

        init(plistDirectoryExists: Bool = true) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("FreeTheNotchTests-\(UUID().uuidString)", isDirectory: true)
            let store = root.appendingPathComponent(plistDirectoryExists ? "Store" : "Missing", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Store"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Export"), withIntermediateDirectories: true)
            let restarts = RestartCounter()
            self.restarts = restarts
            files = ArtworkWallpaperFiles(
                directory: root.appendingPathComponent("FreeTheNotch/ArtworkWallpaper", isDirectory: true),
                wallpaperPlistURL: store.appendingPathComponent("Index.plist"),
                exportDirectory: root.appendingPathComponent("Export", isDirectory: true),
                restartWallpaperAgent: { restarts.increment() })
            // Never the real ~/Library.
            let temp = FileManager.default.temporaryDirectory.standardizedFileURL.path
            #expect(files.directory.standardizedFileURL.path.hasPrefix(temp))
            #expect(files.wallpaperPlistURL.standardizedFileURL.path.hasPrefix(temp))
        }

        func write(_ text: String, to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func read(_ url: URL) -> String? {
            (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
        }

        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func backupIsWrittenOnceAndNeverOverwritten() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.write("user's own", to: box.files.wallpaperPlistURL)
        #expect(box.files.backUpIfNeeded())
        #expect(box.read(box.files.backupURL) == "user's own")
        // The artwork plist is in place now; a second song backs up nothing.
        try box.write("artwork", to: box.files.wallpaperPlistURL)
        #expect(box.files.backUpIfNeeded())
        #expect(box.read(box.files.backupURL) == "user's own")
    }

    @Test func noBackupWithoutAWallpaperStore() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        #expect(!box.files.backUpIfNeeded())
        #expect(!box.files.hasBackup)
    }

    @Test func restorePutsTheBackupBackAndDeletesIt() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.write("user's own", to: box.files.wallpaperPlistURL)
        #expect(box.files.backUpIfNeeded())
        try box.write("artwork", to: box.files.wallpaperPlistURL)
        let artwork = box.files.directory.appendingPathComponent("artwork-1.png")
        try box.write("png", to: artwork)
        try box.write("still", to: box.files.userStillURL)

        #expect(box.files.restore())
        #expect(box.read(box.files.wallpaperPlistURL) == "user's own")
        #expect(!box.files.hasBackup)
        #expect(!box.exists(box.files.userStillURL))
        #expect(!box.exists(artwork))
        #expect(box.restarts.count == 1)
    }

    /// Also what the launch-time recovery does when nothing is left over.
    @Test func restoreWithoutABackupChangesNothing() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.write("user's own", to: box.files.wallpaperPlistURL)
        #expect(!box.files.restore())
        #expect(box.read(box.files.wallpaperPlistURL) == "user's own")
        #expect(box.restarts.count == 0)
    }

    @Test func failedRestoreKeepsTheBackupForTheNextLaunch() throws {
        let box = try Sandbox(plistDirectoryExists: false)
        defer { box.cleanUp() }
        try box.write("user's own", to: box.files.backupURL)
        #expect(!box.files.restore())
        #expect(box.read(box.files.backupURL) == "user's own")
        #expect(box.restarts.count == 0)
    }

    @Test func removeImagesKeepsTheCurrentArtworkAndOtherFiles() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        let keep = box.files.directory.appendingPathComponent("artwork-keep.png")
        let old = box.files.directory.appendingPathComponent("artwork-old.png")
        let other = box.files.directory.appendingPathComponent("Index.backup.plist")
        for url in [keep, old, other] { try box.write("x", to: url) }
        box.files.removeImages(except: keep)
        #expect(box.exists(keep))
        #expect(!box.exists(old))
        #expect(box.exists(other))
        box.files.removeImages(except: nil)
        #expect(!box.exists(keep))
        #expect(box.exists(other))
    }

    @Test func aerialBackupIsDetected() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        #expect(!box.files.backupIsAerial())
        try box.write("Provider com.apple.wallpaper.choice.image", to: box.files.backupURL)
        #expect(!box.files.backupIsAerial())
        try box.write("Provider com.apple.wallpaper.choice.aerials", to: box.files.backupURL)
        #expect(box.files.backupIsAerial())
    }

    @Test func exportOfOurArtworkIsRecognised() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        let metadata = box.exportDirectory.appendingPathComponent("Metadata.plist")
        #expect(!box.files.exportIsArtwork())
        #expect(box.files.exportStamp() == nil)
        try box.write("file:///Users/me/Pictures/beach.heic", to: metadata)
        #expect(!box.files.exportIsArtwork())
        #expect(box.files.exportStamp() != nil)
        try box.write(
            "file:///Users/me/Library/Application%20Support/FreeTheNotch/ArtworkWallpaper/artwork-1.png", to: metadata)
        #expect(box.files.exportIsArtwork())
    }

    @Test func noExportFolderMeansNoExport() {
        let files = ArtworkWallpaperFiles(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            wallpaperPlistURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            exportDirectory: nil, restartWallpaperAgent: {})
        #expect(!files.exportIsArtwork())
        #expect(files.exportStamp() == nil)
    }

    @Test func backupSavesAStillOfTheUsersWallpaper() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.write("user's own", to: box.files.wallpaperPlistURL)
        try box.write("user's picture", to: box.exportDirectory.appendingPathComponent("Wallpaper.png"))
        try box.write(
            "file:///Users/me/Pictures/beach.heic", to: box.exportDirectory.appendingPathComponent("Metadata.plist"))
        #expect(box.files.backUpIfNeeded())
        #expect(box.read(box.files.userStillURL) == "user's picture")
    }

    /// A crash can leave our artwork as macOS's export: no still of it.
    @Test func noStillWhenTheExportIsOurArtwork() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.write("old still", to: box.files.userStillURL)
        try box.write("artwork picture", to: box.exportDirectory.appendingPathComponent("Wallpaper.png"))
        try box.write(
            "FreeTheNotch/ArtworkWallpaper/artwork-1.png",
            to: box.exportDirectory.appendingPathComponent("Metadata.plist"))
        box.files.saveUserStill()
        #expect(!box.exists(box.files.userStillURL))
    }

    @Test func patchPlistRewritesTheStore() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        let image = box.files.directory.appendingPathComponent("artwork-1.png")
        #expect(!box.files.patchPlist(imageURL: image))
        let original = try PropertyListSerialization.data(
            fromPropertyList: ["SystemDefault": ["Type": "linked"]], format: .binary, options: 0)
        try original.write(to: box.files.wallpaperPlistURL)
        let date = Date(timeIntervalSinceReferenceDate: 1)
        #expect(box.files.patchPlist(imageURL: image, date: date))
        let written = try Data(contentsOf: box.files.wallpaperPlistURL)
        let decoded = try PropertyListSerialization.propertyList(from: written, format: nil)
        let expected = WallpaperIndex.patchedIndex(
            ["SystemDefault": ["Type": "linked"]], block: WallpaperIndex.imageBlock(imageURL: image, date: date))
        #expect(plistsMatch(decoded, expected))
    }

    @Test func writtenArtworkLoadsBackAsTheStill() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        let context = try #require(
            CGContext(
                data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let url = try #require(box.files.writePNG(image))
        #expect(url.lastPathComponent.hasPrefix(ArtworkWallpaperFiles.artworkPrefix))
        #expect(box.files.loadUserStill(canvas: CGSize(width: 10, height: 10)) == nil)
        try FileManager.default.copyItem(at: url, to: box.files.userStillURL)
        let still = try #require(box.files.loadUserStill(canvas: CGSize(width: 10, height: 10)))
        #expect(max(still.width, still.height) == 10)
    }

    @Test func onlyTheLatestApplyIsCurrent() {
        let generation = ArtworkApplyGeneration()
        let first = generation.next()
        #expect(generation.isCurrent(first))
        let second = generation.next()
        #expect(!generation.isCurrent(first))
        #expect(generation.isCurrent(second))
        // A restore makes a pending apply stale.
        generation.invalidate()
        #expect(!generation.isCurrent(second))
    }
}
