import SwiftUI

extension SettingsView {
    var generalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageTitle("General")
            SettingsGroupHeader("Startup")
            SettingsCard {
                SettingsRow("Launch at login", showDivider: false) {
                    LaunchAtLogin.Toggle()
                }
            }
            SettingsGroupHeader("Displays")
            DisplayScopeCards(selection: $settings.displayScope)
            SettingsFootnote("The notch and Side Notch show on these displays.")
            SettingsGroupHeader("Interaction")
            SettingsCard {
                SettingsRow("Hover delay") {
                    SettingsSlider(
                        value: $settings.hoverDelay, range: 0...1, step: 0.05,
                        label: String(format: "%.0f ms", settings.hoverDelay * 1000))
                }
                SettingsToggleRow(
                    "Remember last tab",
                    description: "Off: the notch and the menu-bar panel reopen on their first tab",
                    isOn: $settings.rememberLastTab, showDivider: false)
            }
            SettingsGroupHeader("Privacy")
            SettingsCard {
                SettingsToggleRow(
                    "Hide from screen sharing",
                    description:
                        "Keep the notch, menu-bar panel and lock-screen widgets out of screenshots, recordings and screen sharing",
                    isOn: $settings.hideFromScreenCapture, showDivider: false)
            }
        }
    }
}
