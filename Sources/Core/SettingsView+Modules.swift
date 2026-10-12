import SwiftUI

extension SettingsView {
    var liveActivitiesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageTitle("Live Activities")
            SettingsGroupHeader("Notch Widgets")
            SettingsCard {
                SettingsToggleRow(
                    "Media", description: "Now playing with artwork and waveform", isOn: $settings.mediaEnabled)
                SettingsToggleRow(
                    "Caps Lock indicator", description: "Shows \u{21EA} while Caps Lock is on",
                    isOn: $settings.capsLockEnabled)
                SettingsToggleRow(
                    "Bluetooth popup", description: "Connection notification below the notch",
                    isOn: $settings.bluetoothPopupEnabled)
                SettingsToggleRow(
                    "AI sessions", description: "Working, waiting and recently completed Codex / Claude Code turns",
                    isOn: $settings.aiLiveActivitiesEnabled, showDivider: false)
            }
            SettingsFootnote(
                "Session state comes from local agent logs. Regular Claude Desktop chats do not expose this state.")
            SettingsGroupHeader("AI Session Tests")
            SettingsCard {
                ForEach(settings.enabledAIUsageProviders) { provider in
                    HUDTestRow(
                        title: "Test " + provider.title + " session", icon: "sparkles",
                        showDivider: provider != settings.enabledAIUsageProviders.last
                    ) {
                        aiActivities.triggerTest(provider: provider)
                    }
                    .disabled(!settings.aiLiveActivitiesEnabled)
                }
            }
        }
    }

    var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageTitle("Clipboard")
            SettingsGroupHeader("History")
            SettingsCard {
                SettingsToggleRow("Enable clipboard history", isOn: $settings.clipboardEnabled, showDivider: false)
            }
            SettingsGroupHeader("Limits")
            SettingsCard {
                SettingsRow("Maximum items", showDivider: false) {
                    Picker("", selection: $settings.clipboardLimit) {
                        ForEach(SettingsStore.clipboardLimits, id: \.self) { Text("\($0) items").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
            SettingsGroupHeader("Retention")
            SettingsCard {
                SettingsRow("Keep items", description: "How long to keep copied items", showDivider: false) {
                    Picker("", selection: $settings.clipboardRetention) {
                        ForEach(ClipboardRetention.allCases, id: \.self) { retention in
                            Text(retention.displayName).tag(retention)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
        }
    }

    var hudSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageTitle("HUD")
            SettingsGroupHeader("On-Screen Indicators")
            SettingsCard {
                SettingsToggleRow("Volume", description: "Circular progress with percentage", isOn: $settings.hudVolume)
                SettingsToggleRow("Keyboard backlight", isOn: $settings.hudBacklight, showDivider: false)
            }
            // Atoll's Battery → power status notifications.
            SettingsGroupHeader("Battery")
            SettingsCard {
                SettingsToggleRow(
                    "Power status notifications", description: "Short notch HUD when the battery state changes",
                    isOn: $settings.batteryHUDEnabled)
                Group {
                    SettingsToggleRow(
                        "Charging", description: "When the charger is plugged in", isOn: $settings.batteryHUDCharging)
                    SettingsToggleRow(
                        "Low battery", description: "When the level drops to the threshold, or Low Power Mode turns on",
                        isOn: $settings.batteryHUDLow)
                    SettingsRow("Low battery threshold") {
                        Stepper(
                            "\(settings.lowBatteryThreshold)%",
                            value: $settings.lowBatteryThreshold, in: 5...50, step: 5
                        )
                        .disabled(!settings.batteryHUDLow)
                    }
                    SettingsRow("Low battery sound") {
                        SettingsSwitch(isOn: $settings.lowBatterySound)
                            .disabled(!settings.batteryHUDLow)
                    }
                    SettingsToggleRow(
                        "Fully charged", description: "When the battery reaches 100%", isOn: $settings.batteryHUDFull,
                        showDivider: false)
                }
                .disabled(!settings.batteryHUDEnabled)
                .opacity(settings.batteryHUDEnabled ? 1 : 0.5)
            }
            SettingsGroupHeader("AI Usage")
            SettingsCard {
                SettingsToggleRow(
                    "Quota warning at 80%",
                    description: "One warning per Session / Week quota window; old data stays silent",
                    isOn: $settings.aiQuotaHUDEnabled, showDivider: false)
            }
            // Atoll's "HUD Tests" section: one tappable row per HUD.
            SettingsGroupHeader("HUD Tests")
            SettingsCard {
                HUDTestRow(title: "Test charging HUD", icon: "bolt.fill") {
                    AppDelegate.shared?.batteryHUD.triggerTest(.charging)
                }
                .disabled(!settings.batteryHUDEnabled || !settings.batteryHUDCharging)
                HUDTestRow(title: "Test low battery HUD", icon: "battery.25") {
                    AppDelegate.shared?.batteryHUD.triggerTest(.lowBattery)
                }
                .disabled(!settings.batteryHUDEnabled || !settings.batteryHUDLow)
                HUDTestRow(title: "Test full battery HUD", icon: "battery.100") {
                    AppDelegate.shared?.batteryHUD.triggerTest(.fullBattery)
                }
                .disabled(!settings.batteryHUDEnabled || !settings.batteryHUDFull)
                ForEach(settings.enabledAIUsageProviders) { provider in
                    HUDTestRow(
                        title: "Test " + provider.title + " quota HUD", icon: "chart.bar.xaxis",
                        showDivider: provider != settings.enabledAIUsageProviders.last
                    ) {
                        aiUsage.triggerQuotaHUDTest(provider)
                    }
                    .disabled(!settings.aiQuotaHUDEnabled)
                }
            }
            Text("Runs the real notch animation, so you can check each HUD without plugging or unplugging the charger.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
    }

    var utilitiesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageTitle("Utilities")
            SettingsGroupHeader("Keep Awake")
            SettingsCard {
                SettingsToggleRow("Pause while locked", isOn: $settings.awakePauseWhileLocked)
                SettingsToggleRow(
                    "Stop when battery at \(KeepAwakeController.batteryProtectionThreshold)% or less",
                    isOn: $settings.awakeBatteryProtection)
                SettingsToggleRow(
                    "Move mouse slightly", description: "Nudges the cursor so apps keep reporting Available",
                    isOn: $settings.awakeMouseJiggle)
                SettingsRow("Movement interval", showDivider: false) {
                    Picker("", selection: $settings.awakeMouseJiggleIntervalMinutes) {
                        ForEach(SettingsStore.allowedJiggleIntervals, id: \.self) { minutes in
                            Text("\(minutes)m").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                    .disabled(!settings.awakeMouseJiggle)
                }
            }
            SettingsGroupHeader("Cleaning Mode")
            SettingsCard {
                SettingsToggleRow(
                    "Lock trackpad as well", description: "Exit anytime with Esc \u{00D7} 5",
                    isOn: $settings.cleaningLockTrackpad, showDivider: false)
            }
            MouseScrollingSettings()
        }
    }
}

/// Atoll-style test row: full-width button with an icon and title.
private struct HUDTestRow: View {
    let title: String
    let icon: String
    var showDivider = true
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .frame(width: 20)
                    Text(title)
                        .font(.system(size: 14))
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .background(hovering && isEnabled ? Color.primary.opacity(0.05) : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            if showDivider {
                Divider().padding(.leading, 46)
            }
        }
    }
}
