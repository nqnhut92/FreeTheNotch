import SwiftUI

// MARK: - Animation budget

extension EnvironmentValues {
    /// Stops the seek bars and waveforms. The Settings preview sets it while
    /// its window is not in front: a hidden preview kept redrawing.
    @Entry var lockAnimationsPaused = false
    /// Seconds between seek-bar frames: 30 fps on the lock screen; the
    /// preview, where the bar is a few pixels wide, asks for 4.
    @Entry var lockFrameInterval: TimeInterval = 1.0 / 30.0
}

extension Color {
    init(_ rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// MARK: - Event row

/// Next calendar event, from Atoll's LockScreenCalendarEventRow: a
/// `calendar.badge` in the calendar's colour, then "9:06 AM • Title" in
/// white with Atoll's content shadow. Text size matches the reminder widget
/// under it (19 pt) rather than Atoll's 22 pt inline row.
struct LockScreenEventRow: View {
    let text: String
    let calendarColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "calendar.badge")
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(calendarColor, Color.white.opacity(0.6))
                .frame(width: 26, height: 26)
            Text(text)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
        }
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
        .allowsHitTesting(false)
    }
}

// MARK: - Ring tile

private enum RingMetrics {
    static let side: CGFloat = 72
    static let captionColor = Color.white.opacity(0.7)
}

/// One ring in the lock screen's top row: a UniformRing with its glyph,
/// then one or two caption lines.
private struct RingTile<Center: View>: View {
    let fraction: Double
    let colors: [Color]
    var value: String?
    var caption: String?
    @ViewBuilder let center: Center

    var body: some View {
        VStack(spacing: 6) {
            UniformRing(fraction: fraction, gradientColors: colors) { center }
                .frame(width: RingMetrics.side, height: RingMetrics.side)
            if let value {
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(RingMetrics.captionColor)
                    .lineLimit(1)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(RingMetrics.captionColor)
                    .lineLimit(1)
            }
        }
    }
}

/// The white glyph in a ring.
private struct RingGlyph: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
    }
}

// MARK: - Lock screen

/// Widgets drawn on top of the real macOS lock screen. No backdrop and no
/// second clock: those covered the password field and lingered after unlock.
struct LockScreenView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var system: SystemMonitor
    @EnvironmentObject var media: MediaRemoteAdapter
    @EnvironmentObject var timerStore: TimerStore
    @EnvironmentObject var bluetooth: BluetoothMonitor
    @EnvironmentObject var calendar: CalendarStore

    /// Settings → Lock Screen preview: a widget with nothing to show (no
    /// AirPods, no music, no weather yet) gets a stand-in, so every switch
    /// visibly does something. Atoll's preview does the same with mock data
    /// (LockScreenWidgetPreviewManager). Off on the real lock screen.
    var fillsWithSamples = false
    /// The artwork is the wallpaper (LockArtworkSwitch on): every other
    /// widget hides and the player becomes bare controls under the artwork.
    var artworkMode = false
    /// Nothing at all (the wallpaper is switching; LockArtworkPresentation).
    var hidesAll = false
    /// Where the artwork-mode controls start, from this view's top
    /// (LockScreenLayout.artworkControlsTop): just under the artwork.
    var artworkControlsOffset: CGFloat = 0
    /// A click on the card's artwork thumbnail: turns the artwork
    /// wallpaper on (the way back is a click on the wallpaper's artwork).
    var onArtworkTap: (() -> Void)?

    /// This view's padding, which the artwork controls' offset already includes.
    private static let padding: CGFloat = 16
    /// Rings pop in and out when a switch changes (seen in the preview; the
    /// real lock screen is built once per lock).
    private static let ringTransition = AnyTransition.scale(scale: 0.6).combined(with: .opacity)

    /// Artwork mode with something to show.
    private var showsArtworkLayout: Bool {
        artworkMode && settings.lockMedia && nowPlaying != nil
    }

    var body: some View {
        VStack(spacing: 14) {
            if hidesAll {
                Spacer(minLength: 0)
            } else if showsArtworkLayout, let song = nowPlaying {
                // Clean: the controls sit just under the artwork, clear of
                // macOS's user picture. A click on the artwork itself
                // switches back: its own window on the lock screen
                // (LockArtworkClickWindow), a tap area in the Settings preview.
                Color.clear.frame(height: max(0, artworkControlsOffset - Self.padding))
                LockScreenArtworkControls(info: song, media: media)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                Spacer(minLength: 0)
            } else {
                Group {
                    ringRow
                    eventRow
                    liveActivityCards
                }
                .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showsArtworkLayout)
        .animation(.easeInOut(duration: 0.45), value: hidesAll)
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // White on the wallpaper, like macOS's own lock-screen clock and
        // Atoll's default ("Dark") widget appearance.
        .foregroundStyle(.white)
        .onAppear { calendar.requestAccessIfNeeded() }
    }

    // MARK: Readings (real, or a stand-in when `fillsWithSamples`)

    /// A battery ring for a Bluetooth accessory.
    private struct RingDevice: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let level: Int?
    }

    private var airPods: RingDevice? {
        // By name: BTKind.airpods also covers Beats, which this ring would mislabel.
        if let pods = bluetooth.devices.first(where: {
            $0.isConnected && $0.name.localizedCaseInsensitiveContains("airpods")
        }) {
            return RingDevice(id: pods.id, name: "AirPods", symbol: "airpodspro", level: pods.batteryPercent)
        }
        return fillsWithSamples
            ? RingDevice(id: "sample.airpods", name: "AirPods", symbol: "airpodspro", level: 74) : nil
    }

    /// Mice, keyboards and trackpads that report a battery level
    /// (MX Master yes, Keychron no). AirPods are never one of these kinds.
    private var peripherals: [RingDevice] {
        let real = bluetooth.devices.filter {
            $0.isConnected && $0.batteryPercent != nil
                && ($0.kind == .mouse || $0.kind == .keyboard || $0.kind == .trackpad)
        }.map { RingDevice(id: $0.id, name: $0.name, symbol: $0.kind.symbolName, level: $0.batteryPercent) }
        if real.isEmpty && fillsWithSamples {
            return [RingDevice(id: "sample.mouse", name: "Mouse", symbol: BTKind.mouse.symbolName, level: 58)]
        }
        return real
    }

    private struct WeatherReading {
        let temperature: Double
        let low: Double
        let high: Double
        let code: Int?
    }

    private var weatherReading: WeatherReading? {
        if let temp = system.weather.temperatureC {
            return WeatherReading(
                temperature: temp, low: system.weather.lowC ?? (temp - 6),
                high: system.weather.highC ?? (temp + 6), code: system.weather.weatherCode)
        }
        // Atoll's preview: 21° between 16° and 27°, partly cloudy.
        return fillsWithSamples ? WeatherReading(temperature: 21, low: 16, high: 27, code: 2) : nil
    }

    private var aqiReading: (value: Int, label: String)? {
        if let aqi = system.weather.aqi { return (aqi, system.weather.aqiLabel) }
        return fillsWithSamples ? (42, "Good") : nil
    }

    private var eventLine: (text: String, color: Color)? {
        if let next = calendar.lockScreenEvent {
            return ("\(next.timeString) • \(next.title)", next.calendarColor)
        }
        guard fillsWithSamples else { return nil }
        // Atoll's preview event: an orange calendar.
        let start = Date().addingTimeInterval(60 * 60)
        return ("\(start.formatted(date: .omitted, time: .shortened)) • Design Review", Color(nsColor: .systemOrange))
    }

    private var nowPlaying: LockMediaInfo? {
        guard settings.mediaEnabled else { return nil }
        if media.isPlaying {
            return LockMediaInfo(
                title: media.title ?? "", artist: media.artist ?? "", artwork: media.artwork,
                appIcon: media.bundleIdentifier.flatMap(MediaTabView.appIcon(for:)),
                tint: media.artworkColor, clock: media.clock, isPlaying: true,
                isShuffled: media.isShuffled, repeatMode: media.repeatMode, isSample: false)
        }
        return fillsWithSamples ? LockScreenSamples.song : nil
    }

    private var timerText: String? {
        if timerStore.isRunning { return timerStore.formattedRemaining }
        return fillsWithSamples ? "24:13" : nil
    }

    // MARK: Rings (Atoll-style: one ring shape, a gradient for temperature)

    private var showsRingRow: Bool {
        settings.lockBattery || settings.lockAirPods || settings.lockBluetooth || settings.lockWeather
            || settings.lockAQI
    }

    @ViewBuilder
    private var ringRow: some View {
        if showsRingRow {
            HStack(alignment: .top, spacing: 18) {
                if settings.lockBattery {
                    batteryRing.transition(Self.ringTransition)
                }
                if settings.lockAirPods, let pods = airPods {
                    let level = pods.level
                    RingTile(
                        fraction: Double(level ?? 100) / 100,
                        colors: [level.map { Color(LockScreenFormat.batteryTint($0)) } ?? Color.white.opacity(0.4)],
                        value: level.map { "\($0)%" } ?? "AirPods", caption: "AirPods"
                    ) {
                        RingGlyph(symbol: pods.symbol)
                    }
                    .transition(Self.ringTransition)
                }
                if settings.lockBluetooth {
                    ForEach(peripherals) { peripheral in
                        let level = peripheral.level ?? 0
                        RingTile(
                            fraction: Double(level) / 100, colors: [Color(LockScreenFormat.batteryTint(level))],
                            value: "\(level)%", caption: peripheral.name
                        ) {
                            RingGlyph(symbol: peripheral.symbol)
                        }
                        .transition(Self.ringTransition)
                    }
                }
                if settings.lockWeather, let weather = weatherReading {
                    weatherRing(weather).transition(Self.ringTransition)
                }
                if settings.lockAQI, let aqi = aqiReading {
                    RingTile(
                        fraction: Double(min(aqi.value, LockScreenFormat.aqiScaleMaximum))
                            / Double(LockScreenFormat.aqiScaleMaximum),
                        colors: [Color(LockScreenFormat.aqiTint(aqi.value))], caption: "AQI · \(aqi.label)"
                    ) {
                        Text("\(aqi.value)")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .transition(Self.ringTransition)
                }
            }
        }
    }

    /// The Mac's ring. The percentage always shows; the second line says
    /// what the battery is doing.
    private var batteryRing: some View {
        let level = system.batteryPercent
        let symbol: String
        if system.isCharging {
            symbol = "bolt.fill"
        } else if system.isPluggedIn {
            // Charging on hold, like DuoGlyph's plug.
            symbol = "powerplug.portrait.fill"
        } else {
            symbol = LockScreenFormat.batteryIconName(for: level)
        }
        return RingTile(
            fraction: Double(level) / 100, colors: [Color(LockScreenFormat.batteryTint(level))],
            value: "\(level)%", caption: batteryDetail(level: level)
        ) {
            RingGlyph(symbol: symbol)
        }
    }

    private func weatherRing(_ weather: WeatherReading) -> some View {
        let range = weather.low...max(weather.low, weather.high)
        return VStack(spacing: 6) {
            UniformRing(
                fraction: LockScreenFormat.gaugeFraction(of: weather.temperature, in: range),
                gradientColors: LockScreenFormat.temperatureGradient(for: range).map(Color.init)
            ) {
                HStack(spacing: 4) {
                    Image(systemName: LockScreenFormat.weatherSymbol(weather.code))
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(Int(weather.temperature.rounded()))°")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
            }
            .frame(width: RingMetrics.side, height: RingMetrics.side)
            HStack {
                Text("\(Int(weather.low.rounded()))°")
                Spacer()
                Text("\(Int(weather.high.rounded()))°")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(RingMetrics.captionColor)
            .frame(width: RingMetrics.side)
        }
    }

    /// Second line under the battery ring. Wording from Atoll's
    /// LockScreenWeatherWidget (inlineChargingLabel / chargingStatusFallback).
    private func batteryDetail(level: Int) -> String {
        if system.isCharging {
            return LockScreenFormat.formattedChargingTime(system.minutesToFull) ?? "Charging"
        }
        if system.isPluggedIn {
            return level >= 100 ? "Fully charged" : "On hold"
        }
        return "MacBook"
    }

    // MARK: Event row

    @ViewBuilder
    private var eventRow: some View {
        if settings.lockEventRow {
            VStack(spacing: 6) {
                if let eventLine {
                    LockScreenEventRow(text: eventLine.text, calendarColor: eventLine.color)
                }
                // Atoll's lock-screen reminder widget (non-interactive).
                if calendar.reminders.isEmpty && fillsWithSamples {
                    LockScreenReminderWidget(title: "Pay rent", dueDate: Date().addingTimeInterval(12 * 60))
                } else {
                    ForEach(calendar.reminders.prefix(3)) { reminder in
                        LockScreenReminderWidget(reminder: reminder)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Live activities

    private var liveActivityCards: some View {
        VStack(spacing: 12) {
            if settings.lockTimer, let timerText {
                HStack(spacing: 12) {
                    // Samples do not start a real timer.
                    Button {
                        if timerStore.isRunning { timerStore.toggle() }
                    } label: {
                        Image(systemName: "pause.fill")
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Text(timerText)
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green)
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            // Under the timer: the player is the bigger card.
            if settings.lockMedia, let song = nowPlaying {
                LockScreenMediaCard(info: song, media: media, onArtworkTap: onArtworkTap)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(width: 420)
    }
}
