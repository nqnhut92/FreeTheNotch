// Settings → Lock Screen preview. Idea from Atoll (github.com/Ebullioscopic/Atoll),
// GPL-3.0-or-later: DynamicIsland/managers/LockScreenWidgetPreviewManager.swift
// (`LockScreenPreviewScene`: the wallpaper, the real widgets at their real
// lock-screen positions scaled into the view, mock data for the widgets that
// have none). Not from Atoll: it is drawn inline in Settings instead of a
// separate full-screen window, it uses live data and only fills the gaps,
// it zooms to the widgets, and its play button runs the lock notch's
// lock/unlock animation (LockScreenManager). The artwork wallpaper uses the
// same image as the lock screen (LockArtworkImage); on the real lock screen
// macOS does the switch.

import AppKit
import ImageIO
import SwiftUI

struct LockScreenPreview: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var media: MediaRemoteAdapter
    /// .key while Settings is the front window.
    @Environment(\.controlActiveState) private var controlActiveState

    private enum Framing: String, CaseIterable {
        case screen = "Screen"
        case widgets = "Widgets"
    }

    @StateObject private var wallpaper = LockPreviewWallpaper()
    @StateObject private var notch = LockNotchModel()
    @State private var framing: Framing = .screen
    @State private var fillsWithSamples = true
    /// Lock-screen state of the scene: widgets up, desktop dimmed.
    @State private var showsLockScreen = false
    @State private var isPlaying = false
    @State private var playback: Task<Void, Never>?
    /// Widgets framing, panned by hand: how far the crop has moved from the
    /// widgets, in screen points. `dragShift` is the drag in progress.
    @State private var pan: CGSize = .zero
    @GestureState private var dragShift: CGSize = .zero
    /// The preview's own artwork-wallpaper switch: follows the setting, and
    /// a click on the artwork flips it, as on the lock screen.
    @StateObject private var artworkSwitch = LockArtworkSwitch(isOn: false)
    /// The artwork wallpaper image (LockArtworkImage) and which artwork it is.
    @State private var artworkImage: NSImage?
    @State private var artworkKey: ObjectIdentifier?

    /// Display picked in the preview's screen menu (shown with 2+ displays).
    /// On the real lock screen only the main display gets the widgets.
    @State private var screenID: CGDirectDisplayID?
    /// Bumped when displays are plugged in, removed or rearranged.
    @State private var screensVersion = 0

    /// Screen size when there is no screen to ask: a 14" MacBook Pro.
    private static let fallbackScreenSize = CGSize(width: 1512, height: 982)
    /// Lock notch size with no screen to ask.
    private static let fallbackNotchSize = CGSize(width: 200, height: 32)

    /// The previewed screen: the picked one, else the lock notch's.
    private var screen: NSScreen? {
        _ = screensVersion
        return NSScreen.screens.first { $0.displayID == screenID } ?? NSScreen.lockNotchScreen
    }

    /// macOS's main display (`CGMainDisplayID`), where it draws the clock and login.
    private var isMainDisplay: Bool {
        screen?.displayID == CGMainDisplayID()
    }

    var body: some View {
        let screenSize = screen?.frame.size ?? Self.fallbackScreenSize
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let focus = focusRect(in: screenSize)
                // Screen points per view point, to turn a drag into a pan.
                let pointsPerPixel = focus.width / max(proxy.size.width, 1)
                scene(size: screenSize)
                    .frame(width: screenSize.width, height: screenSize.height)
                    // No drawingGroup: it would re-rasterise the whole
                    // screen-sized scene on every seek-bar frame and stall
                    // the Mac (AGENTS.md, render cost). The single
                    // GeometryEffect below keeps the zoom smooth.
                    // Paused unless Settings is the front window; slow bar.
                    .environment(\.lockAnimationsPaused, controlActiveState != .key)
                    .environment(\.lockFrameInterval, 0.25)
                    .modifier(LockPreviewFocus(focus: focus, viewWidth: proxy.size.width))
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    // Widgets: drag to look around (more widgets than fit).
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .updating($dragShift) { value, state, _ in
                                state = CGSize(
                                    width: -value.translation.width * pointsPerPixel,
                                    height: -value.translation.height * pointsPerPixel)
                            }
                            .onEnded { value in
                                pan.width -= value.translation.width * pointsPerPixel
                                pan.height -= value.translation.height * pointsPerPixel
                                pan = LockPreviewGeometry.clampedPan(pan, in: screenSize)
                            },
                        including: framing == .widgets ? .all : .none
                    )
                    .openHandCursor(isActive: framing == .widgets)
            }
            .aspectRatio(screenSize.width / screenSize.height, contentMode: .fit)
            .overlay(alignment: .topTrailing) { screenMenu }
            .overlay(alignment: .topLeading) {
                if !isMainDisplay {
                    Label("Main display only: this display shows just the wallpaper", systemImage: "info.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Lock screen preview")
            .help(
                framing == .widgets
                    ? "Drag to look around" : "The clock and password field stand in for the ones macOS draws")

            HStack(spacing: 12) {
                framingPicker
                // Always here, so the row never changes shape between pages
                // (a hint in its place made the picker stretch and snap back).
                Toggle("Samples", isOn: $fillsWithSamples.animation(.spring(response: 0.4, dampingFraction: 0.8)))
                    .toggleStyle(.checkbox)
                    .help(
                        "Live data from this Mac. Samples fills widgets that have nothing to show (no AirPods, no music…)"
                    )
                Spacer()
                Button {
                    play()
                } label: {
                    Label(isPlaying ? "Playing…" : "Lock & unlock", systemImage: "play.fill")
                }
                .disabled(isPlaying)
                .help("Play the lock and unlock animation")
            }
            // The page switch animates the picture, not this row.
            .transaction { $0.animation = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) {
            _ in
            screensVersion += 1
            wallpaper.load(for: screen)
        }
        .onChange(of: settings.lockArtworkWallpaper) { _, isOn in artworkSwitch.isOn = isOn }
        .onChange(of: targetArtworkID) { _, _ in updateArtworkImage(screenSize: screenSize) }
        .onAppear {
            artworkSwitch.isOn = settings.lockArtworkWallpaper
            wallpaper.load(for: screen)
            lock(animated: true)
        }
        .onDisappear {
            playback?.cancel()
            playback = nil
            isPlaying = false
        }
    }

    /// Screen | Widgets. Drawn in SwiftUI at a fixed size: the AppKit
    /// segmented control stretches and snaps back whenever the preview
    /// redraws (clicking the artwork, for one).
    private var framingPicker: some View {
        HStack(spacing: 2) {
            ForEach(Framing.allCases, id: \.self) { item in
                let isSelected = framing == item
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        framing = item
                        pan = .zero
                    }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(width: 72, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
        .fixedSize()
    }

    /// Which display to preview, over the picture's top-right corner.
    /// Hidden with a single display.
    @ViewBuilder
    private var screenMenu: some View {
        let screens = NSScreen.screens
        if screens.count > 1 {
            Menu {
                ForEach(screens, id: \.self) { item in
                    Button {
                        screenID = item.displayID
                        pan = .zero
                        wallpaper.load(for: item)
                    } label: {
                        let size = item.frame.size
                        Text("\(item.localizedName) — \(Int(size.width)) × \(Int(size.height))")
                    }
                }
            } label: {
                Label(screen?.localizedName ?? "Display", systemImage: "display")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .padding(8)
            .help("Widgets, clock and password field show on the main display only")
        }
    }

    // MARK: Scene (laid out in screen points, scaled by the caller)

    private func scene(size: CGSize) -> some View {
        let notchSize = lockNotchSize
        let column = LockScreenLayout.widgetFrame(in: size)
        return ZStack(alignment: .topLeading) {
            wallpaperLayer
                .frame(width: size.width, height: size.height)
                .clipped()
            if let artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
            // The lock screen dims and softens the wallpaper.
            Color.black.opacity(showsLockScreen ? 0.18 : 0)

            if isMainDisplay {
                systemClock(size: size)
                    .opacity(showsLockScreen ? 1 : 0)
                    .offset(y: showsLockScreen ? 0 : -size.height * 0.04)
            }

            // Widgets only on the main display, as on the lock screen.
            if isMainDisplay {
                LockScreenView(
                    fillsWithSamples: fillsWithSamples, artworkMode: artworkSwitch.isOn,
                    artworkControlsOffset: LockScreenLayout.artworkControlsTop(in: size) - column.minY,
                    onArtworkTap: { artworkSwitch.isOn.toggle() }
                )
                .frame(width: column.width, height: column.height)
                // Rings and cards pop in and out as the switches below change.
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: widgetSwitches)
                .scaleEffect(showsLockScreen ? 1 : 0.94, anchor: .top)
                .opacity(showsLockScreen ? 1 : 0)
                .position(x: column.midX, y: column.midY)
            }

            // macOS draws its login (picture, name, password) on the main
            // display only, and so is the clock.
            if isMainDisplay {
                systemLogin(size: size)
                    .opacity(showsLockScreen ? 1 : 0)
            }

            // As on the lock screen: a click on the artwork turns it off.
            if artworkImage != nil, artworkSwitch.isOn,
                let art = targetArtwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            {
                let hit = LockArtworkImage.visibleRect(
                    artworkPixels: CGSize(width: art.width, height: art.height),
                    screenSize: size, scale: 1)
                RoundedRectangle(cornerRadius: hit.cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .contentShape(RoundedRectangle(cornerRadius: hit.cornerRadius, style: .continuous))
                    .frame(width: hit.rect.width, height: hit.rect.height)
                    .position(x: hit.rect.midX, y: hit.rect.midY)
                    .onTapGesture { artworkSwitch.isOn.toggle() }
            }

            // One lock notch, on the notch screen only (LockScreenManager).
            if screen == NSScreen.lockNotchScreen {
                LockNotchView(model: notch, notchSize: notchSize)
                    .position(x: size.width / 2, y: notchSize.height / 2)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    /// The artwork the wallpaper should be: the player's, while the switch
    /// is on and the player shows on this (main) display.
    private var targetArtwork: NSImage? {
        guard artworkSwitch.isOn, isMainDisplay,
            settings.lockMedia, settings.mediaEnabled
        else { return nil }
        if media.isPlaying { return media.artwork }
        return fillsWithSamples ? LockScreenSamples.artwork : nil
    }

    private var targetArtworkID: ObjectIdentifier? { targetArtwork.map(ObjectIdentifier.init) }

    /// Crossfades to the artwork wallpaper, or back to the real one.
    private func updateArtworkImage(screenSize: CGSize) {
        guard let artwork = targetArtwork,
            let cgArt = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            artworkKey = nil
            withAnimation(.easeInOut(duration: 0.8)) { artworkImage = nil }
            return
        }
        let key = ObjectIdentifier(artwork)
        artworkKey = key
        DispatchQueue.global(qos: .userInitiated).async {
            let image = LockArtworkImage.render(cgArt, canvas: screenSize)
                .map { NSImage(cgImage: $0, size: screenSize) }
            DispatchQueue.main.async {
                guard artworkKey == key, let image else { return }
                withAnimation(.easeInOut(duration: 0.8)) { artworkImage = image }
            }
        }
    }

    @ViewBuilder
    private var wallpaperLayer: some View {
        if let image = wallpaper.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.16, blue: 0.38),
                    Color(red: 0.42, green: 0.22, blue: 0.52),
                    Color(red: 0.93, green: 0.55, blue: 0.38),
                ],
                startPoint: .top, endPoint: .bottom)
        }
    }

    /// Stand-in for macOS's own lock-screen clock (date over a large time),
    /// so the widgets can be judged against it. The real lock screen gets
    /// no second clock from us.
    private func systemClock(size: CGSize) -> some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: size.height * 0.024, weight: .semibold))
                Text(context.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                    .font(.system(size: size.height * 0.125, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            .position(x: size.width / 2, y: size.height * 0.15)
        }
    }

    /// Stand-in for macOS's user picture and password field.
    private func systemLogin(size: CGSize) -> some View {
        // Fixed sizes and distances from the bottom edge, as macOS draws
        // them on a 14" MacBook Pro: picture 80 pt centred 255 pt up,
        // name 200 pt up, a 220 × 34 password field 160 pt up.
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.22))
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.85))
                )
                .frame(width: 80, height: 80)
                .position(x: size.width / 2, y: size.height - 255)
            Text(NSFullUserName())
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .position(x: size.width / 2, y: size.height - 200)
            Capsule()
                .fill(Color.white.opacity(0.2))
                .overlay(
                    Text("Enter Password")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                )
                .frame(width: 220, height: 34)
                .position(x: size.width / 2, y: size.height - 160)
        }
        .frame(width: size.width, height: size.height)
    }

    private var widgetSwitches: [Bool] {
        [
            settings.lockMedia, settings.lockTimer, settings.lockEventRow, settings.lockBattery,
            settings.lockAirPods, settings.lockBluetooth, settings.lockWeather, settings.lockAQI,
        ]
    }

    // MARK: Framing

    /// Lock notch size, as LockScreenManager snaps it.
    private var lockNotchSize: CGSize {
        NSScreen.lockNotchScreen.map(LockNotchLayout.notchSize(on:)) ?? Self.fallbackNotchSize
    }

    /// The part of the screen shown: all of it, or the widgets moved by
    /// `pan` and the drag in progress.
    private func focusRect(in size: CGSize) -> CGRect {
        guard framing == .widgets else { return CGRect(origin: .zero, size: size) }
        let shift = CGSize(width: pan.width + dragShift.width, height: pan.height + dragShift.height)
        return LockPreviewGeometry.focusRect(in: size, pan: shift)
    }

    // MARK: Animation (timings from LockScreenManager)

    /// Lock notch springs in (showLockNotch), widgets fade up.
    private func lock(animated: Bool) {
        notch.isLocked = true
        guard animated else {
            notch.scale = 1
            notch.opacity = 1
            showsLockScreen = true
            return
        }
        notch.scale = LockNotchAnimation.hiddenScale
        notch.opacity = 0
        withAnimation(LockNotchAnimation.springIn) { notch.scale = 1 }
        withAnimation(LockNotchAnimation.fadeIn) { notch.opacity = 1 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.12)) { showsLockScreen = true }
    }

    /// Unlock (hide + transitionLockNotchToUnlocked): widgets go at once,
    /// the shackle opens, holds 1.2 s, then the notch shrinks away. Then
    /// the screen locks again so the preview ends where it started.
    private func play() {
        playback?.cancel()
        isPlaying = true
        playback = Task { @MainActor in
            // Start from a locked screen.
            if !showsLockScreen || notch.opacity < 1 {
                lock(animated: true)
                try? await Task.sleep(for: .seconds(0.8))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showsLockScreen = false
                notch.isLocked = false
            }
            try? await Task.sleep(for: LockNotchAnimation.unlockedHold)
            guard !Task.isCancelled else { return }
            withAnimation(LockNotchAnimation.springOut) { notch.scale = LockNotchAnimation.hiddenScale }
            withAnimation(LockNotchAnimation.fadeOut) { notch.opacity = 0 }
            // A moment on the desktop, then lock again.
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            lock(animated: true)
            try? await Task.sleep(for: .seconds(0.5))
            isPlaying = false
        }
    }
}

/// The desktop picture of the preview's screen, downsampled off the main
/// thread. Stays nil (gradient) when macOS gives a URL ImageIO cannot read,
/// such as some dynamic wallpapers.
final class LockPreviewWallpaper: ObservableObject {
    @Published private(set) var image: NSImage?
    private var loadedURL: URL?

    func load(for screen: NSScreen?) {
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen), url != loadedURL else { return }
        loadedURL = url
        let maxPixels = max(screen.frame.width, screen.frame.height)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = Self.downsample(url, maxPixels: maxPixels)
            DispatchQueue.main.async { self?.image = image }
        }
    }

    static func downsample(_ url: URL, maxPixels: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
