import SwiftUI

/// Open notch body. The icon row lives in the menu-bar band above this,
/// so it stays level with the menu bar instead of dropping under the camera.
struct ExpandedPanelView: View {
    @ObservedObject var panelState: NotchPanelState
    @EnvironmentObject var media: MediaRemoteAdapter
    @EnvironmentObject var settings: SettingsStore

    /// The Home body without its bottom padding.
    private static let playerHeight = NotchPage.home.baseBodyHeight - NotchPage.bottomPadding

    var body: some View {
        pageContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, NotchPage.bottomPadding)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch panelState.page {
        case .home:
            homePage
        case .clipboard:
            ClipboardTabView()
        case .aiUsage:
            AIUsageTabView()
        case .timer:
            TimerTabView()
        case .qr:
            QRTabView()
        case .calculator:
            CalculatorTabView()
        }
    }

    private var homePage: some View {
        VStack(spacing: NotchPage.batteryStripSpacing) {
            if settings.homeQuote {
                QuoteOfTheDayView()
                    .frame(height: NotchPage.quoteHeight)
                    .padding(.top, NotchPage.quoteTopGap)
            }
            Group {
                if NotchPage.showsPlayer(media: media, settings: settings) {
                    // Player and calendar have a fixed height; the Up next line
                    // below the player adds height to the island instead of
                    // squeezing (and moving) the player.
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 0) {
                            MediaTabView()
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.playerHeight)
                            if NotchPage.showsUpNext(media: media, settings: settings) {
                                Divider().overlay(Color.white.opacity(0.08))
                                UpNextBar()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 6)
                                    .transition(.opacity)
                            }
                        }
                        WeekCalendarView()
                            .frame(width: 280, height: Self.playerHeight)
                    }
                } else {
                    StandaloneCalendarView()
                }
            }
            .animation(.smooth(duration: 0.25), value: NotchPage.showsPlayer(media: media, settings: settings))
            if settings.homeBatteryStrip {
                BatteryStripView()
                    .frame(height: NotchPage.batteryStripHeight)
            }
        }
        .padding(.horizontal, 16)
    }
}

@MainActor
extension NotchPage {
    /// Atoll's `shouldShowMusicPlayer` (autoHideInactiveNotchMediaPlayer on
    /// by default): no media session, no player; the calendar takes the row.
    static func showsPlayer(media: MediaRemoteAdapter, settings: SettingsStore) -> Bool {
        settings.mediaEnabled && media.title != nil
    }

    /// Whether the home page shows the Up next line under the player.
    static func showsUpNext(media: MediaRemoteAdapter, settings: SettingsStore) -> Bool {
        showsPlayer(media: media, settings: settings) && media.upNext != .hidden
    }

    /// Body height for the live state. The one source for the island's
    /// shape (`NotchRootView`) and its hit area (`NotchWindowController`).
    static func bodyHeight(
        for page: NotchPage, media: MediaRemoteAdapter,
        settings: SettingsStore, calendar: CalendarStore
    ) -> CGFloat {
        bodyHeight(
            for: page,
            showsPlayer: showsPlayer(media: media, settings: settings),
            showsUpNext: showsUpNext(media: media, settings: settings),
            homeQuote: settings.homeQuote,
            homeBatteryStrip: settings.homeBatteryStrip,
            calendarWeeks: calendar.gridDays.count / 7)
    }
}
