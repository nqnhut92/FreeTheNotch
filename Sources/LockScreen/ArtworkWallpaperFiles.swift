// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// DynamicIsland/managers/FullScreenArtworkWindowManager.swift
// (backupWallpaperConfig, applyArtworkToPlist, makeImageWallpaperBlock,
// patchWallpaperEntries, restartWallpaperAgent, restoreWallpaper). Changes:
// - The backup lives in Application Support, not the temp folder (cleared
//   on restart), and a backup left behind by a crash or force quit is
//   restored at the next launch, so the user's wallpaper never stays
//   replaced.
// - A still of the user's wallpaper (macOS's export) is saved with the
//   backup for the way back; Atoll restores with no transition.

import Foundation
import ImageIO
import os

/// The Index.plist patch as plain values: Atoll's makeImageWallpaperBlock
/// and patchWallpaperEntries.
enum WallpaperIndex {
    /// The choice that marks an aerial wallpaper. Binary plists keep strings
    /// as ASCII, so a byte search finds it.
    static let aerialProvider = "com.apple.wallpaper.choice.aerials"

    /// Atoll's makeImageWallpaperBlock: one image file, set now.
    static func imageBlock(imageURL: URL, date: Date) -> [String: Any] {
        let config: [String: Any] = ["type": "imageFile", "url": ["relative": imageURL.absoluteString]]
        let configData =
            (try? PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)) ?? Data()
        let choice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.image",
            "Files": [] as [Any],
            "Configuration": configData,
        ]
        return [
            "Content": ["Choices": [choice], "Shuffle": "$null"] as [String: Any],
            "LastSet": date,
            "LastUse": date,
        ]
    }

    /// Atoll's applyArtworkToPlist + patchWallpaperEntries: the same block
    /// for Desktop and Idle (lock screen) everywhere a wallpaper is set.
    /// The two top-level entries are always written; per-display and
    /// per-space entries only where they exist, and only those that
    /// already have a `Type` get it set to "individual".
    static func patchedIndex(_ index: [String: Any], block: [String: Any]) -> [String: Any] {
        func patched(_ entry: [String: Any], forcingType: Bool) -> [String: Any] {
            var entry = entry
            entry["Desktop"] = block
            entry["Idle"] = block
            if forcingType || entry["Type"] != nil { entry["Type"] = "individual" }
            return entry
        }
        func patchedDisplays(_ displays: [String: Any]) -> [String: Any] {
            displays.mapValues { value in
                (value as? [String: Any]).map { patched($0, forcingType: false) } ?? value
            }
        }

        var index = index
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            index[key] = patched((index[key] as? [String: Any]) ?? [:], forcingType: true)
        }
        if let displays = index["Displays"] as? [String: Any] {
            index["Displays"] = patchedDisplays(displays)
        }
        if let spaces = index["Spaces"] as? [String: Any] {
            index["Spaces"] = spaces.mapValues { value -> Any in
                guard var space = value as? [String: Any] else { return value }
                if let entry = space["Default"] as? [String: Any] {
                    space["Default"] = patched(entry, forcingType: false)
                }
                if let displays = space["Displays"] as? [String: Any] {
                    space["Displays"] = patchedDisplays(displays)
                }
                return space
            }
        }
        return index
    }

    /// `data` (an Index.plist) with the image patched in, as a binary plist.
    static func patched(_ data: Data, imageURL: URL, date: Date) -> Data? {
        guard
            let index = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return nil }
        let patched = patchedIndex(index, block: imageBlock(imageURL: imageURL, date: date))
        return try? PropertyListSerialization.data(fromPropertyList: patched, format: .binary, options: 0)
    }
}

/// A counter the main thread bumps on every apply and restore, and the
/// file queue reads: a step that finds its number stale was superseded
/// (switched off, paused, next song, unlock) and must not touch the
/// wallpaper.
final class ArtworkApplyGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// Starts a new apply and returns its number.
    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
    /// Makes every pending apply stale.
    func invalidate() { lock.withLock { value += 1 } }
    func isCurrent(_ generation: Int) -> Bool { lock.withLock { value == generation } }
}

/// The artwork wallpaper's files: the user's Index.plist and its backup,
/// the artwork PNGs, and the still of the user's wallpaper. Blocking file
/// work: call it on LockArtworkWallpaper's queue only. Every location and
/// the WallpaperAgent restart are injected, so tests run in a temp folder.
///
/// **Do not regress (AGENTS.md):** the backup is written once and never
/// over an existing one, its existence means "restore me", and a failed
/// restore keeps it for the next launch.
struct ArtworkWallpaperFiles: Sendable {
    /// Our folder: the backup, the still and the artwork PNGs.
    let directory: URL
    /// macOS's wallpaper store, rewritten while the artwork is up.
    let wallpaperPlistURL: URL
    /// macOS's export of the current wallpaper (`Wallpaper.png`,
    /// `Metadata.plist`), or nil when unknown.
    let exportDirectory: URL?
    /// Makes macOS reread `wallpaperPlistURL`.
    let restartWallpaperAgent: @Sendable () -> Void

    private var fileManager: FileManager { .default }

    /// The user's own Index.plist while the artwork is up.
    var backupURL: URL { directory.appendingPathComponent("Index.backup.plist") }
    /// A still of the user's wallpaper, saved with the backup: the cover on
    /// the way back. For an aerial nothing else has one (NSWorkspace reports
    /// the default aerial's file).
    var userStillURL: URL { directory.appendingPathComponent("user-wallpaper.png") }
    var hasBackup: Bool { fileManager.fileExists(atPath: backupURL.path) }

    private var exportImageURL: URL? { exportDirectory?.appendingPathComponent("Wallpaper.png") }
    private var exportMetadataURL: URL? { exportDirectory?.appendingPathComponent("Metadata.plist") }

    /// Copies the backup over the user's Index.plist and restarts
    /// WallpaperAgent. Returns false with nothing to restore, or when the
    /// copy failed (the backup stays for the next try).
    @discardableResult
    func restore() -> Bool {
        guard hasBackup else { return false }
        do {
            let data = try Data(contentsOf: backupURL)
            try data.write(to: wallpaperPlistURL, options: .atomic)
            try fileManager.removeItem(at: backupURL)
            try? fileManager.removeItem(at: userStillURL)
        } catch {
            Logger.artworkWallpaper.error(
                "[FreeTheNotch] artwork wallpaper: restore failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        restartWallpaperAgent()
        removeImages(except: nil)
        Logger.artworkWallpaper.notice("[FreeTheNotch] artwork wallpaper: user's wallpaper restored")
        return true
    }

    /// Atoll's backupWallpaperConfig, but only once, so a second song never
    /// backs up the artwork plist over the user's. Also saves the still.
    func backUpIfNeeded() -> Bool {
        if hasBackup { return true }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Data(contentsOf: wallpaperPlistURL)
            try data.write(to: backupURL, options: .atomic)
        } catch {
            return false
        }
        saveUserStill()
        return true
    }

    /// Whether the user's own wallpaper (the backup) is an aerial.
    func backupIsAerial() -> Bool {
        guard let data = try? Data(contentsOf: backupURL) else { return false }
        return data.range(of: Data(WallpaperIndex.aerialProvider.utf8)) != nil
    }

    /// Writes the artwork into the user's Index.plist.
    func patchPlist(imageURL: URL, date: Date = Date()) -> Bool {
        guard let data = try? Data(contentsOf: wallpaperPlistURL),
            let patched = WallpaperIndex.patched(data, imageURL: imageURL, date: date)
        else { return false }
        return (try? patched.write(to: wallpaperPlistURL, options: .atomic)) != nil
    }

    /// Copies macOS's export of the wallpaper, which is still the user's
    /// own here (the artwork is not in yet), unless it is one of ours (left
    /// by a crash).
    func saveUserStill() {
        try? fileManager.removeItem(at: userStillURL)
        guard let exportImageURL, !exportIsArtwork() else { return }
        do {
            try fileManager.copyItem(at: exportImageURL, to: userStillURL)
        } catch {
            Logger.artworkWallpaper.notice(
                "[FreeTheNotch] artwork wallpaper: no still of the user's wallpaper: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// The saved still, scaled to `canvas` (macOS exports it at 4K). Nil if none.
    func loadUserStill(canvas: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(userStillURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(canvas.width, canvas.height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// When macOS last exported the wallpaper.
    func exportStamp() -> Date? {
        guard let exportMetadataURL else { return nil }
        let attributes = try? fileManager.attributesOfItem(atPath: exportMetadataURL.path)
        return attributes?[.modificationDate] as? Date
    }

    /// Whether macOS's export is our artwork: its image URL is in our folder.
    func exportIsArtwork() -> Bool {
        guard let exportMetadataURL, let data = try? Data(contentsOf: exportMetadataURL) else { return false }
        return data.range(of: Data(Self.ourFolderMarker.utf8)) != nil
    }

    /// The tail of `directory`'s path, which the export's image URL contains
    /// when it is our artwork.
    static let ourFolderMarker = "FreeTheNotch/ArtworkWallpaper"

    /// A new file per song: WallpaperAgent caches by URL.
    func writePNG(_ image: CGImage) -> URL? {
        let url = directory.appendingPathComponent("\(Self.artworkPrefix)\(UUID().uuidString).png")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }

    static let artworkPrefix = "artwork-"

    /// Deletes our artwork PNGs, but `keep`.
    func removeImages(except keep: URL?) {
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files
        where file.lastPathComponent.hasPrefix(Self.artworkPrefix)
            && file.lastPathComponent != keep?.lastPathComponent
        {
            try? fileManager.removeItem(at: file)
        }
    }
}

extension ArtworkWallpaperFiles {
    /// The real locations: ~/Library/Application Support/FreeTheNotch/ArtworkWallpaper,
    /// macOS's wallpaper store, and its export for the current user.
    static var live: ArtworkWallpaperFiles {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ArtworkWallpaperFiles(
            directory: home.appendingPathComponent(
                "Library/Application Support/FreeTheNotch/ArtworkWallpaper", isDirectory: true),
            wallpaperPlistURL: home.appendingPathComponent(
                "Library/Application Support/com.apple.wallpaper/Store/Index.plist"),
            exportDirectory: currentUserExportDirectory,
            restartWallpaperAgent: { killWallpaperAgent() })
    }

    /// `dlsym`'s RTLD_DEFAULT handle: search every loaded image.
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    /// macOS's export of the current wallpaper, readable by every user:
    /// /private/var/db/Wallpapers/<GeneratedUID>/ (written by
    /// wallpaperexportd after each WallpaperAgent start or wallpaper
    /// change; the FileVault login screen uses it).
    private static let currentUserExportDirectory: URL? = {
        // mbr_uid_to_uuid (membership.h) is not imported into Swift.
        typealias UIDToUUID = @convention(c) (uid_t, UnsafeMutablePointer<UInt8>) -> Int32
        guard let symbol = dlsym(rtldDefault, "mbr_uid_to_uuid") else { return nil }
        let uidToUUID = unsafeBitCast(symbol, to: UIDToUUID.self)
        var raw = UUID().uuid
        let status = withUnsafeMutableBytes(of: &raw) { bytes -> Int32 in
            guard let base = bytes.baseAddress else { return -1 }
            return uidToUUID(getuid(), base.assumingMemoryBound(to: UInt8.self))
        }
        guard status == 0 else { return nil }
        return URL(fileURLWithPath: "/private/var/db/Wallpapers", isDirectory: true)
            .appendingPathComponent(UUID(uuid: raw).uuidString, isDirectory: true)
    }()

    /// Atoll's restartWallpaperAgent: it relaunches and rereads Index.plist.
    /// Not waited on, and its output is discarded.
    private static func killWallpaperAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
