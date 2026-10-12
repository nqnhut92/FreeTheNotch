import SwiftUI

/// What the lock-screen player shows: the live session, or the preview's sample.
struct LockMediaInfo {
    let title: String
    let artist: String
    let artwork: NSImage?
    let appIcon: NSImage?
    let tint: Color
    let clock: PlaybackClock
    let isPlaying: Bool
    let isShuffled: Bool
    let repeatMode: MediaRemoteAdapter.RepeatMode
    /// Buttons do nothing and the bar loops.
    let isSample: Bool

    /// Elapsed seconds and the seek bar's fraction at `date`.
    func progress(at date: Date) -> (elapsed: Double, fraction: Double) {
        LockScreenFormat.progress(of: clock, loops: isSample, at: date)
    }
}

/// Lock-screen player in the notch player's style (MediaTabView, itself
/// Atoll's home player): artwork with the app badge, bold title with the
/// waveform, blue artist, seek bar with times, then shuffle · repeat ·
/// previous · play/pause · next. Smaller artwork than the notch (no room
/// under the clock), a dark card tinted with the artwork colour. The seek
/// bar follows `PlaybackClock` and never snaps to bridge samples.
struct LockScreenMediaCard: View {
    let info: LockMediaInfo
    let media: MediaRemoteAdapter
    var onArtworkTap: (() -> Void)?
    @Environment(\.lockAnimationsPaused) private var animationsPaused
    @Environment(\.lockFrameInterval) private var frameInterval

    private static let accent = Color(red: 0.20, green: 0.55, blue: 1.0)
    /// Row heights for the scrolling title and artist (point size × 1.3).
    private static let titleHeight: CGFloat = 21
    private static let artistHeight: CGFloat = 17
    private static let artworkSide: CGFloat = 76
    private static let cornerRadius: CGFloat = 26

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        // Long names scroll like the notch player's. The
                        // GeometryReader hands MarqueeText its width without
                        // feeding it back into layout (see MediaTabView).
                        GeometryReader { geo in
                            MarqueeText(
                                .constant(info.title),
                                font: .system(size: 16, weight: .bold), nsFont: .preferredFont(forTextStyle: .title3),
                                textColor: .white, minDuration: 1.0,
                                frameWidth: geo.size.width, paused: animationsPaused)
                        }
                        .frame(height: Self.titleHeight)
                        if info.isPlaying {
                            WaveformView(color: info.tint)
                        }
                    }
                    GeometryReader { geo in
                        MarqueeText(
                            .constant(info.artist),
                            font: .system(size: 13, weight: .medium), nsFont: .preferredFont(forTextStyle: .body),
                            textColor: Self.accent, minDuration: 1.0,
                            frameWidth: geo.size.width, paused: animationsPaused)
                    }
                    .frame(height: Self.artistHeight)
                    seekBar
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            transport
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(
            ZStack {
                Color.black.opacity(0.5)
                LinearGradient(
                    colors: [info.tint.opacity(0.32), info.tint.opacity(0.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let art = info.artwork {
                    Image(nsImage: art).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: Self.artworkSide, height: Self.artworkSide)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: info.tint.opacity(0.45), radius: 10, y: 3)
            if let icon = info.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .offset(x: 6, y: 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if info.artwork != nil { onArtworkTap?() }
        }
        .help(onArtworkTap == nil ? "" : "Click to use the artwork as the wallpaper, or to go back")
    }

    private var seekBar: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: animationsPaused)) { context in
            let (elapsed, fraction) = info.progress(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { geo in
                    let x = geo.size.width * CGFloat(fraction)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22)).frame(height: 4)
                        Capsule().fill(Color.white).frame(width: max(4, x), height: 4)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                            .offset(x: min(max(0, x - 5), geo.size.width - 10))
                    }
                }
                .frame(height: 10)
                HStack {
                    Text(LockScreenFormat.clock(elapsed))
                    Spacer()
                    Text(LockScreenFormat.clock(info.clock.duration))
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.accent)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            button("shuffle", size: 13, color: info.isShuffled ? Self.accent : .white.opacity(0.85)) {
                media.toggleShuffle()
            }
            button(
                info.repeatMode == .one ? "repeat.1" : "repeat", size: 13,
                color: info.repeatMode == .off ? .white.opacity(0.85) : Self.accent
            ) { media.toggleRepeat() }
            button("backward.fill", size: 16) { media.previousTrack() }
            button(info.isPlaying ? "pause.fill" : "play.fill", size: 24) { media.togglePlayPause() }
            button("forward.fill", size: 16) { media.nextTrack() }
        }
        .buttonStyle(.plain)
    }

    private func button(
        _ symbol: String, size: CGFloat, color: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            // The preview's sample must not drive the real player.
            if !info.isSample { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
        }
    }
}

/// The player in artwork mode: no panel and no thumbnail (the artwork is
/// the wallpaper above it). Title and artist centred, a thin seek bar with
/// the times beside it, then shuffle · previous · play/pause · next · repeat.
/// White with a soft shadow, like the clock. A click on the artwork above
/// turns the artwork wallpaper off (LockArtworkClickWindow). Our own design;
/// Atoll keeps its music panel.
struct LockScreenArtworkControls: View {
    let info: LockMediaInfo
    let media: MediaRemoteAdapter
    @Environment(\.lockAnimationsPaused) private var animationsPaused
    @Environment(\.lockFrameInterval) private var frameInterval

    /// Width of each time label: fits "62:05".
    private static let timeLabelWidth: CGFloat = 36

    var body: some View {
        VStack(spacing: 10) {
            // Centred; long names scroll (MarqueeText, as in the notch).
            VStack(spacing: 2) {
                GeometryReader { geo in
                    MarqueeText(
                        .constant(info.title),
                        font: .system(size: 18, weight: .semibold, design: .rounded),
                        nsFont: .preferredFont(forTextStyle: .title2),
                        textColor: .white, minDuration: 1.0, frameWidth: geo.size.width,
                        alignment: .center, paused: animationsPaused)
                }
                .frame(height: 24)
                GeometryReader { geo in
                    MarqueeText(
                        .constant(info.artist),
                        font: .system(size: 13, weight: .medium, design: .rounded),
                        nsFont: .preferredFont(forTextStyle: .body),
                        textColor: .white.opacity(0.7), minDuration: 1.0, frameWidth: geo.size.width,
                        alignment: .center, paused: animationsPaused)
                }
                .frame(height: 17)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity)
            seekBar
            HStack(spacing: 0) {
                button("shuffle", size: 14, isActive: info.isShuffled) { media.toggleShuffle() }
                button("backward.fill", size: 18) { media.previousTrack() }
                button(info.isPlaying ? "pause.fill" : "play.fill", size: 28) { media.togglePlayPause() }
                button("forward.fill", size: 18) { media.nextTrack() }
                button(
                    info.repeatMode == .one ? "repeat.1" : "repeat", size: 14,
                    isActive: info.repeatMode != .off
                ) { media.toggleRepeat() }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
        .frame(width: 400)
    }

    private var seekBar: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: animationsPaused)) { context in
            let (elapsed, fraction) = info.progress(at: context.date)
            HStack(spacing: 10) {
                Text(LockScreenFormat.clock(elapsed)).frame(width: Self.timeLabelWidth, alignment: .trailing)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white).frame(width: max(3, geo.size.width * CGFloat(fraction)))
                    }
                }
                .frame(height: 3)
                Text(LockScreenFormat.clock(info.clock.duration))
                    .frame(width: Self.timeLabelWidth, alignment: .leading)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.75))
            .monospacedDigit()
        }
    }

    private func button(
        _ symbol: String, size: CGFloat, isActive: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if !info.isSample { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.55))
                .frame(maxWidth: .infinity, minHeight: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Stand-ins for the Settings preview.
@MainActor
enum LockScreenSamples {
    /// Anchor for the sample song's looping seek bar.
    static let start = Date()

    /// A made-up 600 × 600 cover (sunset over stripes), drawn, not bundled.
    static let artwork: NSImage? = {
        let cover = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.10, blue: 0.36),
                    Color(red: 0.78, green: 0.25, blue: 0.47),
                    Color(red: 1.0, green: 0.62, blue: 0.35),
                ],
                startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.88, blue: 0.45),
                            Color(red: 1.0, green: 0.42, blue: 0.42),
                        ],
                        startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 300, height: 300)
                .offset(y: 40)
            VStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { i in
                    Rectangle()
                        .fill(Color(red: 0.16, green: 0.10, blue: 0.36))
                        .frame(height: CGFloat(4 + i * 3))
                }
            }
            .offset(y: 190)
        }
        .frame(width: 600, height: 600)
        .clipped()
        let renderer = ImageRenderer(content: cover)
        renderer.scale = 1
        return renderer.nsImage
    }()

    /// The sample song: 3:34 long, 1:02 in when the preview opened.
    static var song: LockMediaInfo {
        LockMediaInfo(
            title: "Sunset Drive", artist: "Sample Artist", artwork: artwork,
            appIcon: nil, tint: Color(red: 1.0, green: 0.55, blue: 0.45),
            clock: PlaybackClock(anchorElapsed: 62, anchorDate: start, duration: 214, playing: true),
            isPlaying: true, isShuffled: false, repeatMode: .off, isSample: true)
    }
}
