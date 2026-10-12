import SwiftUI

/// Player row copied from the Atoll home layout: artwork with a source badge,
/// title, blue artist, a slider with a thumb, and the transport row.
struct MediaTabView: View {
    @EnvironmentObject var media: MediaRemoteAdapter
    @EnvironmentObject var settings: SettingsStore

    private let accent = Color(red: 0.20, green: 0.55, blue: 1.0)
    private static let titleFont = NSFont.systemFont(ofSize: 18, weight: .bold)
    private static let artistFont = NSFont.preferredFont(forTextStyle: .footnote)
    /// The rows MarqueeText gives itself.
    private static let titleHeight = MarqueeText.rowHeight(pointSize: titleFont.pointSize)
    private static let artistHeight = MarqueeText.rowHeight(pointSize: artistFont.pointSize)

    var body: some View {
        Group {
            if settings.mediaEnabled {
                HStack(alignment: .center, spacing: 14) {
                    artwork
                    VStack(alignment: .leading, spacing: 7) {
                        // iOS expanded Dynamic Island: waveform at the end of the title row.
                        HStack(alignment: .center, spacing: 8) {
                            // GeometryReader hands MarqueeText the width it is
                            // given without feeding it back into layout;
                            // measuring the column instead loops (AGENTS.md).
                            GeometryReader { geo in
                                MarqueeText(
                                    .constant(media.title ?? "Nothing playing"),
                                    font: Font(Self.titleFont),
                                    nsFont: Self.titleFont,
                                    textColor: .white,
                                    minDuration: 1.0,
                                    frameWidth: geo.size.width
                                )
                            }
                            .frame(height: Self.titleHeight)
                            if media.isPlaying {
                                WaveformView(color: media.artworkColor)
                                    .transition(.opacity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: media.isPlaying)
                        GeometryReader { geo in
                            MarqueeText(
                                .constant(media.artist ?? " "),
                                font: .system(size: 13, weight: .medium),
                                nsFont: Self.artistFont,
                                textColor: accent,
                                minDuration: 1.0,
                                frameWidth: geo.size.width
                            )
                        }
                        .frame(height: Self.artistHeight)
                        scrubber
                        transportButtons
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                }
            } else {
                Text("Media disabled")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let art = media.artwork {
                    Image(nsImage: art).resizable().scaledToFill()
                } else {
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 112, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Atoll-style: now-playing app icon badge (Music, Spotify, browser...).
            if let bundleID = media.bundleIdentifier,
                let appIcon = Self.appIcon(for: bundleID)
            {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .offset(x: 7, y: 7)
            }
        }
        .padding(.trailing, 4)
        .padding(.bottom, 4)
    }

    /// Atoll's AppIconAsNSImage: icon for a bundle ID via NSWorkspace.
    static func appIcon(for bundleID: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private var scrubber: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = media.clock.elapsed(at: context.date)
            let fraction = media.clock.fraction(at: context.date)
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let x = geo.size.width * CGFloat(fraction)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22)).frame(height: 4)
                        Capsule().fill(Color.white).frame(width: max(4, x), height: 4)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                            .offset(x: min(max(0, x - 6), geo.size.width - 12))
                    }
                }
                .frame(height: 12)
                HStack {
                    Text(DurationFormat.playback(elapsed))
                    Spacer()
                    Text(DurationFormat.playback(media.clock.duration))
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
            }
        }
    }

    /// Atoll's control slots (shuffle, previous, play/pause, next, repeat)
    /// plus its media-output picker. Repeat sits next to shuffle;
    /// the output button uses the AirPlay glyph instead of Atoll's
    /// current-device icon (a laptop for the built-in speakers).
    private var transportButtons: some View {
        HStack(spacing: 0) {
            transportButton("shuffle", size: 13, color: media.isShuffled ? accent : .white) {
                media.toggleShuffle()
            }
            transportButton(
                media.repeatMode == .one ? "repeat.1" : "repeat", size: 13,
                color: media.repeatMode == .off ? .white : accent
            ) {
                media.toggleRepeat()
            }
            transportButton("backward.fill", size: 15) { media.previousTrack() }
            transportButton(media.isPlaying ? "pause.fill" : "play.fill", size: 22) {
                media.togglePlayPause()
            }
            transportButton("forward.fill", size: 15) { media.nextTrack() }
            // Music: Atoll's AirPlayPickerButton (Music's own AirPlay list).
            // Other sources: Atoll's media-output picker (CoreAudio outputs).
            MediaOutputPickerButton(useMusicAirPlay: media.bundleIdentifier == MediaRemoteAdapter.musicBundleID)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func transportButton(
        _ symbol: String, size: CGFloat,
        weight: Font.Weight = .regular,
        color: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
    }
}

// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// NotchHomeView.swift — MediaOutputPickerButton + MediaOutputSelectorPopover.

/// Output picker: popover with the output volume and the device list.
private struct MediaOutputPickerButton: View {
    var useMusicAirPlay = false
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @ObservedObject private var airPlayManager = AppleMusicAirPlayManager.shared
    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
            if isPopoverPresented {
                if useMusicAirPlay {
                    Task { await airPlayManager.refreshDevices() }
                } else {
                    routeManager.refreshDevices()
                }
            }
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 14))
                .foregroundStyle(isPopoverPresented ? Color.accentColor : .white)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(useMusicAirPlay ? "AirPlay" : "Audio output")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            if useMusicAirPlay {
                AirPlaySelectorPopover(airPlayManager: airPlayManager)
            } else {
                MediaOutputSelectorPopover(routeManager: routeManager) {
                    isPopoverPresented = false
                }
            }
        }
        // The popover is its own window: hovering it must not close the notch.
        .onChange(of: isPopoverPresented) { _, open in
            NotchPopoverTracker.shared.isOpen = open
        }
        .onDisappear { NotchPopoverTracker.shared.isOpen = false }
        // Atoll's AirPlayPickerButton: load the list before the first tap, so
        // the popover opens with it already there.
        .onAppear {
            if useMusicAirPlay { Task { await airPlayManager.refreshDevices() } }
        }
        .onChange(of: useMusicAirPlay) { _, music in
            if music { Task { await airPlayManager.refreshDevices() } }
        }
    }
}

private struct MediaOutputSelectorPopover: View {
    @ObservedObject var routeManager: AudioRouteManager
    var dismiss: () -> Void

    /// Read from CoreAudio when the popover shows (the publisher below
    /// delivers its current value on subscribe), not in the view's init.
    @State private var level: Float = 0
    @State private var isMuted = false

    var body: some View {
        VStack(spacing: 16) {
            volumeSection
            Divider()
            devicesSection
        }
        .frame(width: 240)
        .padding(16)
        .onReceive(routeManager.$activeDeviceID) { _ in
            let (newLevel, muted) = HUDController.outputVolume()
            level = newLevel
            isMuted = muted
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    isMuted.toggle()
                    HUDController.setMuted(isMuted)
                } label: {
                    Image(systemName: volumeIconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.secondary.opacity(0.18)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { Double(level) },
                        set: { newValue in
                            level = Float(newValue)
                            HUDController.setVolume(level)
                            if isMuted && level > 0 {
                                isMuted = false
                                HUDController.setMuted(false)
                            }
                        }
                    ), in: 0...1
                )
                .tint(.accentColor)
            }
            HStack {
                Text("Output volume")
                Spacer()
                Text("\(Int(round(level * 100)))%")
            }
            .font(.caption)
            .foregroundStyle(Color.secondary)
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output devices")
                .font(.caption)
                .foregroundStyle(Color.secondary)
            if routeManager.devices.isEmpty {
                Text("No audio outputs available")
                    .font(.callout)
                    .foregroundStyle(Color.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FittingScrollView(scrolls: routeManager.devices.count > 6, maxHeight: 240) {
                    VStack(spacing: 6) {
                        ForEach(routeManager.devices) { device in
                            Button {
                                routeManager.select(device: device)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: device.iconName)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(device.name)
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if device.id == routeManager.activeDeviceID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            device.id == routeManager.activeDeviceID
                                                ? Color.primary.opacity(0.12) : .clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var volumeIconName: String {
        if isMuted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.33 { return "speaker.wave.1.fill" }
        if level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// Ported from Atoll (GPL-3.0-or-later): NotchHomeView.swift —
// AirPlaySelectorPopover + AirPlayVolumeSlider.

private struct AirPlaySelectorPopover: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AirPlay")
                .font(.caption)
                .foregroundStyle(Color.secondary)

            if airPlayManager.devices.isEmpty {
                Text(airPlayManager.isLoading ? "Searching…" : "No AirPlay devices found")
                    .font(.callout)
                    .foregroundStyle(Color.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // A ScrollView has no ideal height: the popover kept the size
                // it opened with ("Searching…") and the loaded list scrolled
                // inside it. Short lists are laid out plainly so the popover
                // grows to fit; only long ones scroll.
                FittingScrollView(scrolls: airPlayManager.devices.count > 6, maxHeight: 300) {
                    VStack(spacing: 6) {
                        ForEach(airPlayManager.devices) { device in
                            VStack(spacing: 4) {
                                Button {
                                    Task { await airPlayManager.toggleDevice(device) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: device.iconName)
                                            .font(.system(size: 14, weight: .medium))
                                        Text(device.name)
                                            .foregroundStyle(Color.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        if device.isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(device.isSelected ? Color.primary.opacity(0.12) : .clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if device.isSelected {
                                    AirPlayVolumeSlider(airPlayManager: airPlayManager, deviceID: device.id)
                                        .padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: 240)
        .padding(16)
    }
}

/// Plain content for short lists (so a popover sizes to it), a fixed-height
/// ScrollView for long ones.
private struct FittingScrollView<Content: View>: View {
    let scrolls: Bool
    let maxHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if scrolls {
            ScrollView { content }.frame(height: maxHeight)
        } else {
            content
        }
    }
}

/// Local @State slider, decoupled from the manager's published state so a
/// refresh mid-drag does not reset it (Atoll).
private struct AirPlayVolumeSlider: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager
    let deviceID: String

    @State private var sliderValue: Double = 0
    @State private var isSyncing = false

    var body: some View {
        Slider(value: $sliderValue, in: 0...100)
            .tint(.accentColor)
            .onAppear {
                isSyncing = true
                sliderValue = Double(airPlayManager.currentVolume(for: deviceID))
                isSyncing = false
            }
            .onChange(of: sliderValue) { _, newValue in
                guard !isSyncing else { return }
                airPlayManager.setVolume(Int(newValue), for: deviceID)
            }
    }
}

/// Up next (Music only), a full-width bar under the player + calendar row.
/// Empty queue uses the iOS Music app's wording.
struct UpNextBar: View {
    @EnvironmentObject var media: MediaRemoteAdapter

    var body: some View {
        switch media.upNext {
        case .hidden:
            EmptyView()
        case .endOfList:
            HStack(spacing: 6) {
                Text("UP NEXT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                Text("There's no music in the queue.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(height: 22)
        case .track(_, let title, let artist):
            HStack(spacing: 6) {
                Text("UP NEXT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                Group {
                    if let art = media.upNextArtwork {
                        Image(nsImage: art).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.12)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5)))
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                // Long names scroll like the player title (Atoll's MarqueeText).
                GeometryReader { geo in
                    MarqueeText(
                        .constant(artist.isEmpty ? title : "\(title) · \(artist)"),
                        font: .system(size: 11, weight: .medium),
                        nsFont: .preferredFont(forTextStyle: .caption1),
                        textColor: .white.opacity(0.9),
                        minDuration: 1.0,
                        frameWidth: geo.size.width
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(height: 22)
            .help(artist.isEmpty ? title : "\(title) — \(artist)")
        }
    }
}
