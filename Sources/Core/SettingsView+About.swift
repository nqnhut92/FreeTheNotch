import SwiftUI

extension SettingsView {
    var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageTitle("About")
            SettingsCard {
                VStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                        .padding(.top, 24)
                    VStack(spacing: 4) {
                        Text("FreeTheNotch")
                            .font(.system(size: 22, weight: .bold))
                        Text(AppInfo.versionLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                        Text("Notch, menu-bar and lock-screen utilities for your Mac")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    HStack(spacing: 10) {
                        Link(destination: AppInfo.repositoryURL) {
                            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.accentColor))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .help(AppInfo.repositoryURL.absoluteString)
                        Button {
                            NSApplication.shared.terminate(nil)
                        } label: {
                            Label("Quit", systemImage: "power")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.red.opacity(0.12)))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
            SettingsGroupHeader("Acknowledgements")
            SettingsCard {
                creditRow(
                    "Atoll", detail: "Notch, HUD, lock screen and pet playback",
                    url: "https://github.com/Ebullioscopic/Atoll")
                creditRow(
                    "Vorssaint", detail: "Menu-bar panel and calculator",
                    url: "https://github.com/vorssaint/vorssaint-utils")
                creditRow(
                    "DuoBar", detail: "DuoGlyph layout and Wi-Fi monitoring",
                    url: "https://github.com/Mikeli7666/DuoBar")
                creditRow(
                    "CodeNotch", detail: "Side Notch, AI usage and session monitoring",
                    url: "https://github.com/vinzdg/codenotch")
                creditRow(
                    "Zstandard", detail: "Claude Desktop usage cache decoder",
                    url: "https://github.com/facebook/zstd")
                creditRow(
                    "LaunchAtLogin", detail: "Launch at login switch",
                    url: "https://github.com/sindresorhus/LaunchAtLogin-Modern")
                creditRow(
                    "LottieFiles", detail: "Pets by Kanika, Bashir and Ludovic",
                    url: "https://lottiefiles.com")
                creditRow(
                    "ZenQuotes", detail: "Inspirational quotes provided by ZenQuotes API",
                    url: "https://zenquotes.io/")
                creditRow(
                    "Lottie", detail: "Animation playback", url: "https://github.com/airbnb/lottie-ios",
                    showDivider: false)
            }
            Text(AppInfo.authorLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
    }

    private func creditRow(_ name: String, detail: String, url: String, showDivider: Bool = true) -> some View {
        SettingsRow(name, description: detail, showDivider: showDivider) {
            if let link = URL(string: url) {
                Link(destination: link) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(url)
            }
        }
    }
}
