import AppKit
import Foundation
import SwiftUI
import os

/// Now Playing for any app.
///
/// From macOS 15.4, `mediaremoted` ignores this app and returns an empty
/// dictionary. Atoll works around that by asking `/usr/bin/perl` (which is
/// allowed) to stream the info. `MediaBridge.dylib` is loaded into that
/// perl process and prints one JSON object per line.
final class MediaRemoteAdapter: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var artwork: NSImage?
    /// Average color of the artwork (Atoll-style `avgColor`); the live-activity
    /// waveform tints to this like iOS Dynamic Island.
    @Published private(set) var artworkColor: Color = .white
    /// Bundle ID of the now-playing app (Music, Spotify, browser...). Atoll-style.
    @Published private(set) var bundleIdentifier: String?
    @Published private(set) var playbackFraction: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var elapsed: Double = 0
    /// Wall-clock anchor for the scrubber. The bridge reports position once
    /// a second; snapping to every sample would make the bar jump.
    @Published private(set) var clock = PlaybackClock()
    /// Atoll's `isShuffled` / `repeatMode` (MediaRemote shuffle 1 = off;
    /// repeat 1 off, 2 one, 3 all).
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off

    enum RepeatMode: Int {
        case off = 1
        case one = 2
        case all = 3
    }

    /// "Up next" under the player. Music only: the next track of Music's
    /// current playlist (AppleScript cannot see the real queue, so it is
    /// hidden while shuffle is on). Not in Atoll; our own addition.
    enum UpNext: Equatable {
        case hidden
        case track(id: String, title: String, artist: String)
        case endOfList
    }
    @Published private(set) var upNext: UpNext = .hidden
    @Published private(set) var upNextArtwork: NSImage?
    /// Music's `bpm` of the current track when it is set (most tracks leave
    /// it 0). Drives the skin pet's dance tempo; nil = use a default tempo.
    @Published private(set) var trackBPM: Int?
    private var lastBPMTitle: String?

    /// After a tap, the app takes a moment to republish its mode. Keep the
    /// optimistic value until then so the button does not flicker back.
    private var modeOverrideUntil = Date.distantPast
    static let musicBundleID = "com.apple.Music"
    // Music's modes come over AppleScript (see the extension below).
    private let scriptQueue = DispatchQueue(label: "FreeTheNotch.music-script", qos: .utility)
    private var lastMusicModeRead = Date.distantPast
    private var musicReadInFlight = false
    private var lastUpNextKey = ""
    private var lastUpNextRead = Date.distantPast
    private var upNextReadInFlight = false

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutBuffer = ""
    /// Last elapsed value from the bridge. A seek makes the app republish
    /// with a jumped value; staleness alone must not move the clock.
    private var lastRemoteElapsed: Double = -1

    private struct Snapshot: Decodable {
        let playing: Bool?
        let title: String?
        let artist: String?
        let duration: Double?
        let elapsed: Double?
        let artwork: String?
        let bundleIdentifier: String?
        let pid: Int32?
        let shuffleMode: Int?
        let repeatMode: Int?
    }

    func startMonitoring() {
        guard process == nil else { return }
        guard launchBridge() else { return }
    }

    @discardableResult
    private func launchBridge() -> Bool {
        guard let script = Bundle.main.url(forResource: "media-bridge", withExtension: "pl"),
            let dylib = Bundle.main.url(forResource: "MediaBridge", withExtension: "dylib")
        else {
            Logger.media.error("[FreeTheNotch] media bridge resources missing from the app bundle")
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, dylib.path]
        let output = Pipe()
        let errors = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self?.consume(chunk)
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { Logger.media.notice("[FreeTheNotch] media bridge: \(line, privacy: .public)") }
        }
        process.terminationHandler = { [weak self] proc in
            Logger.media.notice("[FreeTheNotch] media bridge exited \(proc.terminationStatus, privacy: .public)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self, self.process === proc else { return }
                self.process = nil
                self.launchBridge()
            }
        }
        do {
            try process.run()
            self.process = process
            self.stdinPipe = input
            Logger.media.notice("[FreeTheNotch] media bridge started")
            return true
        } catch {
            Logger.media.error("[FreeTheNotch] media bridge failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func consume(_ chunk: String) {
        stdoutBuffer.append(chunk)
        while let range = stdoutBuffer.range(of: "\n") {
            let line = String(stdoutBuffer[..<range.lowerBound])
            stdoutBuffer = String(stdoutBuffer[range.upperBound...])
            guard let data = line.data(using: .utf8),
                let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
            else { continue }
            DispatchQueue.main.async { [weak self] in
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: Snapshot) {
        let title = snapshot.title?.isEmpty == false ? snapshot.title : nil
        guard let title else {
            clear()
            return
        }
        let playing = snapshot.playing ?? false
        if playing != isPlaying || title != self.title {
            Logger.media.notice(
                "[FreeTheNotch] now playing: \(title, privacy: .public) playing=\(playing ? 1 : 0, privacy: .public)")
        }
        let duration = snapshot.duration ?? 0
        let remoteElapsed = snapshot.elapsed ?? 0
        let trackChanged = title != self.title
        // A changed elapsed value is the app republishing after a seek; an
        // unchanged one is just stale and must not move the clock.
        let remoteElapsedChanged = abs(remoteElapsed - lastRemoteElapsed) > 0.5
        lastRemoteElapsed = remoteElapsed
        let reconciled = clock.reconciled(
            remoteElapsed: remoteElapsed, remoteElapsedChanged: remoteElapsedChanged,
            duration: duration, playing: playing, trackChanged: trackChanged, now: Date())
        if reconciled != clock { clock = reconciled }
        isPlaying = playing
        self.title = title
        artist = snapshot.artist
        // Atoll's approach: resolve bundle ID from PID via NSRunningApplication.
        // Falls back to the bundleIdentifier field if PID resolution fails.
        var resolvedBundleID: String?
        if let pid = snapshot.pid, pid > 0 {
            resolvedBundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        if resolvedBundleID == nil {
            resolvedBundleID = snapshot.bundleIdentifier?.isEmpty == false ? snapshot.bundleIdentifier : nil
        }
        bundleIdentifier = resolvedBundleID
        if resolvedBundleID == Self.musicBundleID {
            // Music does not publish its modes to MediaRemote; Atoll's
            // AppleMusicController asks it over AppleScript instead.
            // A new track changes Up next: read now instead of waiting 2s.
            if trackChanged { lastMusicModeRead = .distantPast }
            refreshMusicModesIfNeeded()
        } else if Date() >= modeOverrideUntil {
            upNext = .hidden
            lastUpNextKey = ""
            // 0 = the app did not publish the key (Atoll: treat as off).
            let shuffle = snapshot.shuffleMode ?? 0
            isShuffled = shuffle != 0 && shuffle != 1
            repeatMode = RepeatMode(rawValue: snapshot.repeatMode ?? 1) ?? .off
        }
        self.duration = duration
        elapsed = clock.elapsed(at: Date())
        playbackFraction = clock.fraction(at: Date())
        if let encoded = snapshot.artwork, let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
            artwork = image
            // Atoll-style: tint the waveform to the artwork's average color.
            artworkColor = Color(nsColor: image.quickAverageColor())
        } else if trackChanged {
            // Atoll (NowPlayingController, non-diff payload): a new track
            // without art drops the old cover instead of keeping it on screen.
            artwork = nil
            artworkColor = .white
        }
    }

    private func clear() {
        guard isPlaying || title != nil else { return }
        isPlaying = false
        title = nil
        artist = nil
        artwork = nil
        artworkColor = .white
        bundleIdentifier = nil
        upNext = .hidden
        upNextArtwork = nil
        lastUpNextKey = ""
        lastRemoteElapsed = -1
        playbackFraction = 0
        duration = 0
        elapsed = 0
        clock = PlaybackClock()
    }

    func togglePlayPause() { send("toggle\n") }
    func nextTrack() { send("next\n") }
    func previousTrack() { send("prev\n") }

    /// Atoll's NowPlayingController.toggleShuffle: set off (1) or tracks (3).
    /// Music goes through AppleScript (Atoll's AppleMusicController).
    func toggleShuffle() {
        if bundleIdentifier == Self.musicBundleID {
            runMusicScript("set shuffle enabled to not shuffle enabled")
        } else {
            send("shuffle \(isShuffled ? 1 : 3)\n")
        }
        isShuffled.toggle()
        modeOverrideUntil = Date().addingTimeInterval(2)
        // Up next depends only on our (optimistic) modes, not on Music
        // catching up: update it right away instead of after the 2s hold.
        if bundleIdentifier == Self.musicBundleID { refreshUpNextIfNeeded() }
    }

    /// Atoll's toggleRepeat, same cycle as the Music app: off → all → one → off.
    func toggleRepeat() {
        let next: RepeatMode
        switch repeatMode {
        case .off: next = .all
        case .all: next = .one
        case .one: next = .off
        }
        if bundleIdentifier == Self.musicBundleID {
            let value: String
            switch next {
            case .off: value = "off"
            case .one: value = "one"
            case .all: value = "all"
            }
            runMusicScript("set song repeat to \(value)")
        } else {
            send("repeat \(next.rawValue)\n")
        }
        repeatMode = next
        modeOverrideUntil = Date().addingTimeInterval(2)
        if bundleIdentifier == Self.musicBundleID { refreshUpNextIfNeeded() }
    }

}

// MARK: - Atoll's quick average color (NSImage+Extensions.swift)

extension NSImage {
    /// Synchronous cheap average, used to tint the waveform to the artwork.
    /// Ensures a minimum brightness so the color stays visible on the black notch.
    func quickAverageColor() -> NSColor {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .systemGray
        }
        let side: CGFloat = 32
        let scale = min(side / CGFloat(cgImage.width), side / CGFloat(cgImage.height))
        let drawWidth = max(1, Int(CGFloat(cgImage.width) * scale))
        let drawHeight = max(1, Int(CGFloat(cgImage.height) * scale))
        guard
            let context = CGContext(
                data: nil,
                width: drawWidth,
                height: drawHeight,
                bitsPerComponent: 8,
                bytesPerRow: drawWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return .systemGray
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: drawWidth, height: drawHeight))
        guard let data = context.data else { return .systemGray }
        let pointer = data.bindMemory(to: UInt32.self, capacity: drawWidth * drawHeight)
        var totalRed: UInt64 = 0
        var totalGreen: UInt64 = 0
        var totalBlue: UInt64 = 0
        for i in 0..<(drawWidth * drawHeight) {
            let color = pointer[i]
            totalRed += UInt64(color & 0xFF)
            totalGreen += UInt64((color >> 8) & 0xFF)
            totalBlue += UInt64((color >> 16) & 0xFF)
        }
        let count = CGFloat(drawWidth * drawHeight)
        let minBrightness: CGFloat = 0.5
        let averageRed = CGFloat(totalRed) / count / 255.0
        let averageGreen = CGFloat(totalGreen) / count / 255.0
        let averageBlue = CGFloat(totalBlue) / count / 255.0
        if averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03 {
            return NSColor(white: minBrightness, alpha: 1.0)
        }
        var color = NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if brightness < minBrightness {
            let saturationScale = brightness / minBrightness
            color = NSColor(
                hue: hue, saturation: saturation * saturationScale,
                brightness: minBrightness, alpha: alpha)
        }
        return color
    }
}

extension MediaRemoteAdapter {
    // MARK: Music (AppleScript, Atoll's AppleMusicController)

    private func runMusicScript(_ command: String) {
        scriptQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"Music\" to \(command)")?.executeAndReturnError(&error)
            if let error { Logger.media.error("[FreeTheNotch] Music script failed: \(error, privacy: .public)") }
        }
    }

    /// Reads `shuffle enabled` / `song repeat` at most every 1s.
    private func refreshMusicModesIfNeeded() {
        guard !musicReadInFlight, Date() >= modeOverrideUntil,
            Date().timeIntervalSince(lastMusicModeRead) >= 1
        else { return }
        musicReadInFlight = true
        lastMusicModeRead = Date()
        scriptQueue.async { [weak self] in
            let source = """
                tell application "Music"
                    set repeatState to song repeat
                    if repeatState is one then
                        set repeatValue to 2
                    else if repeatState is all then
                        set repeatValue to 3
                    else
                        set repeatValue to 1
                    end if
                    return {shuffle enabled, repeatValue}
                end tell
                """
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let shuffled = result?.atIndex(1)?.booleanValue
            let repeatValue = result?.atIndex(2)?.int32Value
            DispatchQueue.main.async {
                guard let self else { return }
                self.musicReadInFlight = false
                if Date() >= self.modeOverrideUntil, let shuffled, let repeatValue {
                    self.isShuffled = shuffled
                    self.repeatMode = RepeatMode(rawValue: Int(repeatValue)) ?? .off
                }
                self.refreshUpNextIfNeeded()
            }
        }
    }

    /// Up next is recomputed when the track, shuffle or repeat changes, and
    /// re-checked every 15s. A failed read is not remembered: right after
    /// playback starts Music often errors once, and caching that would hide
    /// Up next for the whole track.
    private func refreshUpNextIfNeeded() {
        refreshTrackBPMIfNeeded()
        let key = "\(title ?? "")|\(isShuffled)|\(repeatMode.rawValue)"
        guard key != lastUpNextKey || Date().timeIntervalSince(lastUpNextRead) >= 15 else { return }
        guard !upNextReadInFlight else { return }
        lastUpNextKey = key
        lastUpNextRead = Date()
        // Repeat one plays the same song again, shuffle or not.
        let repeatOne = repeatMode == .one
        guard !isShuffled || repeatOne else {
            setUpNext(.hidden)
            return
        }
        let repeatAll = repeatMode == .all
        let requestKey = key
        upNextReadInFlight = true
        scriptQueue.async { [weak self] in
            // Playing an album (or Songs) makes `current playlist` the whole
            // Library, so "index + 1" is a random library track. For the
            // library, use the current track's album in disc/track order.
            let source = """
                tell application "Music"
                    try
                        set pl to current playlist
                        set ct to current track
                        set curID to persistent ID of ct
                        if \(repeatOne ? "true" : "false") then
                            return {"next", curID, name of ct, artist of ct}
                        end if
                        if class of pl is library playlist then
                            set alb to album of ct
                            if alb is "" then return {"none"}
                            set aa to album artist of ct
                            set out to {}
                            repeat with t in (every track of pl whose album is alb)
                                if album artist of t is aa then
                                    set end of out to {persistent ID of t, disc number of t, track number of t, name of t, artist of t}
                                end if
                            end repeat
                            return {"album", curID, out}
                        else
                            set idx to index of ct
                            set n to count of tracks of pl
                            if idx < n then
                                set t to track (idx + 1) of pl
                            else if \(repeatAll ? "true" : "false") and n > 0 then
                                set t to track 1 of pl
                            else
                                return {"end"}
                            end if
                            return {"next", persistent ID of t, name of t, artist of t}
                        end if
                    on error
                        return {"error"}
                    end try
                end tell
                """
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if result == nil || result?.atIndex(1)?.stringValue == "error" {
                Logger.media.notice(
                    "[FreeTheNotch] Up next read failed, will retry: \(String(describing: error ?? [:]), privacy: .public)"
                )
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.upNextReadInFlight = false
                    self.lastUpNextKey = ""  // retry on the next 1s poll
                }
                return
            }
            let next: UpNext
            switch result?.atIndex(1)?.stringValue {
            case "next":
                next = .track(
                    id: result?.atIndex(2)?.stringValue ?? "",
                    title: result?.atIndex(3)?.stringValue ?? "",
                    artist: result?.atIndex(4)?.stringValue ?? "")
            case "end":
                next = .endOfList
            case "album":
                next = Self.albumUpNext(
                    currentID: result?.atIndex(2)?.stringValue,
                    list: result?.atIndex(3), repeatAll: repeatAll)
            default:
                next = .hidden
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.upNextReadInFlight = false
                // Shuffle/repeat/track changed while this read ran (e.g. a
                // tap): drop the stale answer and read again now.
                let currentKey = "\(self.title ?? "")|\(self.isShuffled)|\(self.repeatMode.rawValue)"
                guard currentKey == requestKey else {
                    self.refreshUpNextIfNeeded()
                    return
                }
                self.setUpNext(next)
            }
        }
    }

    /// Reads `bpm of current track` once per track (Music only).
    private func refreshTrackBPMIfNeeded() {
        guard title != lastBPMTitle else { return }
        lastBPMTitle = title
        trackBPM = nil
        let requestTitle = title
        scriptQueue.async { [weak self] in
            var error: NSDictionary?
            let result = NSAppleScript(source: "tell application \"Music\" to get bpm of current track")?
                .executeAndReturnError(&error)
            let bpm = Int(result?.int32Value ?? 0)
            DispatchQueue.main.async {
                guard let self, self.title == requestTitle else { return }
                self.trackBPM = (60...220).contains(bpm) ? bpm : nil
            }
        }
    }

    private static func albumUpNext(currentID: String?, list: NSAppleEventDescriptor?, repeatAll: Bool) -> UpNext {
        guard let currentID, let list, list.numberOfItems > 0 else { return .hidden }
        struct Item {
            let id: String
            let disc: Int
            let track: Int
            let title: String
            let artist: String
        }
        var items: [Item] = []
        for i in 1...list.numberOfItems {
            guard let d = list.atIndex(i) else { continue }
            items.append(
                Item(
                    id: d.atIndex(1)?.stringValue ?? "",
                    disc: Int(d.atIndex(2)?.int32Value ?? 0),
                    track: Int(d.atIndex(3)?.int32Value ?? 0),
                    title: d.atIndex(4)?.stringValue ?? "",
                    artist: d.atIndex(5)?.stringValue ?? ""))
        }
        items.sort { (max($0.disc, 1), $0.track) < (max($1.disc, 1), $1.track) }
        guard let index = items.firstIndex(where: { $0.id == currentID }) else { return .hidden }
        let nextItem: Item?
        if index + 1 < items.count {
            nextItem = items[index + 1]
        } else if repeatAll {
            nextItem = items.first
        } else {
            nextItem = nil
        }
        guard let nextItem else { return .endOfList }
        return .track(id: nextItem.id, title: nextItem.title, artist: nextItem.artist)
    }

    private func setUpNext(_ next: UpNext) {
        guard next != upNext else { return }
        if case .track(let id, _, _) = next { loadUpNextArtwork(persistentID: id) } else { upNextArtwork = nil }
        upNext = next
    }

    /// Artwork of the Up next track, fetched once per track.
    private func loadUpNextArtwork(persistentID: String) {
        upNextArtwork = nil
        guard !persistentID.isEmpty else { return }
        scriptQueue.async { [weak self] in
            let source = """
                tell application "Music"
                    try
                        set t to first track of current playlist whose persistent ID is "\(persistentID)"
                        return raw data of artwork 1 of t
                    end try
                    return ""
                end tell
                """
            var error: NSDictionary?
            let data = NSAppleScript(source: source)?.executeAndReturnError(&error).data
            let image = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                guard let self, case .track(let id, _, _) = self.upNext, id == persistentID else { return }
                self.upNextArtwork = image
            }
        }
    }

    private func send(_ command: String) {
        guard let data = command.data(using: .utf8) else { return }
        stdinPipe?.fileHandleForWriting.write(data)
    }
}
