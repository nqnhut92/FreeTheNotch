import SwiftUI

/// Player row copied from the Atoll home layout: artwork with a source badge,
/// title, blue artist, a slider with a thumb, and the transport row.
struct MediaTabView: View {
    @EnvironmentObject var media: MediaRemoteAdapter
    @EnvironmentObject var settings: SettingsStore

    private let accent = Color(red: 0.20, green: 0.55, blue: 1.0)
    private static let artworkSide: CGFloat = 112
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
        Group {
            if media.showsVinyl {
                VinylRecordView(artwork: media.artwork, isSpinning: media.isPlaying)
                    .frame(width: Self.artworkSide, height: Self.artworkSide)
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
            } else {
                coverArtwork
            }
        }
    }

    private var coverArtwork: some View {
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
            .frame(width: Self.artworkSide, height: Self.artworkSide)
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

    /// Atoll's control slots plus its media-output picker, in the order of the
    /// Music app: shuffle, previous, play/pause, next, repeat. The output button uses the AirPlay glyph instead of Atoll's
    /// current-device icon (a laptop for the built-in speakers).
    private var transportButtons: some View {
        HStack(spacing: 0) {
            transportButton("shuffle", size: 13, color: media.isShuffled ? accent : .white) {
                media.toggleShuffle()
            }
            transportButton("backward.fill", size: 15) { media.previousTrack() }
            transportButton(media.isPlaying ? "pause.fill" : "play.fill", size: 22) {
                media.togglePlayPause()
            }
            transportButton("forward.fill", size: 15) { media.nextTrack() }
            transportButton(
                media.repeatMode == .one ? "repeat.1" : "repeat", size: 13,
                color: media.repeatMode == .off ? .white : accent
            ) {
                media.toggleRepeat()
            }
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
