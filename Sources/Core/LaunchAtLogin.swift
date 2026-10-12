import ServiceManagement
import SwiftUI
import os

// Ported from sindresorhus/LaunchAtLogin-Modern (MIT),
// Sources/LaunchAtLogin/LaunchAtLogin.swift — the package Atoll uses for its
// "Launch at login" toggle (Atoll: components/Settings/SettingsView.swift).
// The state lives in macOS (SMAppService), not in UserDefaults, so it stays in
// sync when the user removes the app from System Settings → Login Items.
enum LaunchAtLogin {
    fileprivate static let observable = Observable()

    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            observable.objectWillChange.send()
            do {
                if newValue {
                    if SMAppService.mainApp.status == .enabled {
                        try? SMAppService.mainApp.unregister()
                    }
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger.settings.error(
                    "[FreeTheNotch] failed to \(newValue ? "enable" : "disable", privacy: .public) launch at login: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    final class Observable: ObservableObject {
        var isEnabled: Bool {
            get { LaunchAtLogin.isEnabled }
            set { LaunchAtLogin.isEnabled = newValue }
        }
    }

    /// Switch bound to the login-item status. Re-reads it on appear, in case
    /// it changed in System Settings while the window was closed.
    struct Toggle: View {
        @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

        var body: some View {
            SettingsSwitch(isOn: $launchAtLogin.isEnabled)
                .onAppear { launchAtLogin.objectWillChange.send() }
        }
    }
}
