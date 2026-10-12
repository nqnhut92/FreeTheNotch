import SwiftUI

extension SettingsView {
    var lockScreenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title and preview are pinned above the scroll view.
            SettingsGroupHeader("Cards")
            SettingsCard {
                SettingsToggleRow("Media", description: "Only while something is playing", isOn: $settings.lockMedia)
                SettingsToggleRow(
                    "Artwork wallpaper",
                    description:
                        "While music plays, the lock screen wallpaper becomes the artwork. Click the artwork to switch. Your wallpaper comes back when you unlock.",
                    isOn: $settings.lockArtworkWallpaper
                )
                .disabled(!settings.lockMedia)
                .opacity(settings.lockMedia ? 1 : 0.5)
                SettingsToggleRow("Timer", isOn: $settings.lockTimer)
                SettingsToggleRow("Upcoming event", isOn: $settings.lockEventRow, showDivider: false)
            }
            SettingsGroupHeader("Rings")
            SettingsCard {
                SettingsToggleRow("MacBook battery", isOn: $settings.lockBattery)
                SettingsToggleRow("AirPods", isOn: $settings.lockAirPods)
                SettingsToggleRow(
                    "Bluetooth devices", description: "Mouse, keyboard, trackpad with battery",
                    isOn: $settings.lockBluetooth)
                SettingsToggleRow("Weather", isOn: $settings.lockWeather)
                SettingsToggleRow("AQI", isOn: $settings.lockAQI, showDivider: false)
            }
        }
    }
}
