// UI structure adapted from Vorssaint: UI/Settings/MouseSettings.swift.
// Copyright (C) 2026 Vorssaint. SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Compact mouse-wheel controls within Utilities, with optional advanced tuning.
struct MouseScrollingSettings: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var smoothScroll: SmoothScrollService
    @State private var showsMoreOptions = false
    @State private var appNames: [String: String] = [:]
    @State private var pickerError: String?

    var body: some View {
        SettingsGroupHeader("Mouse Scrolling")
        SettingsCard {
            SettingsToggleRow(
                "Smooth scrolling", description: "Smooth mouse-wheel scrolling across apps",
                isOn: $settings.smoothScrollEnabled, showDivider: settings.smoothScrollEnabled)
            if settings.smoothScrollEnabled {
                if !smoothScroll.hasAccessibility {
                    SettingsRow(
                        "Accessibility required", description: "Allow FreeTheNotch to adjust mouse-wheel events"
                    ) {
                        Button("Grant Accessibility") { smoothScroll.requestAccessibility() }
                            .controlSize(.small)
                    }
                } else if !smoothScroll.isRunning {
                    SettingsRow("Smooth scrolling is paused", showDivider: true) {
                        Image(systemName: "pause.circle").foregroundStyle(.secondary)
                    }
                }
                slider(
                    "Scroll speed", value: $settings.smoothScrollStep,
                    range: SmoothScrollSupport.stepRange, step: 10, percentage: false)
                DisclosureGroup("More options", isExpanded: $showsMoreOptions) {
                    VStack(spacing: 0) {
                        slider(
                            "Response", value: $settings.smoothScrollResponse,
                            range: SmoothScrollSupport.responseRange, step: 5, percentage: true)
                        slider(
                            "Coast", value: $settings.smoothScrollCoast,
                            range: SmoothScrollSupport.coastRange, step: 5, percentage: true)
                        Text("Higher response follows the wheel sooner. Higher coast extends the glide.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        excludedApps
                    }
                }
                .font(.system(size: 13))
                .padding(16)
            }
        }
        SettingsFootnote("Mouse wheels only. Trackpad and Magic Mouse gestures keep their native scrolling.")
            .onAppear { refreshAppNames() }
            .onChange(of: settings.smoothScrollExcludedApps) { _, _ in refreshAppNames() }
    }

    private func slider(
        _ title: String, value: Binding<Int>, range: ClosedRange<Int>,
        step: Double, percentage: Bool
    ) -> some View {
        SettingsRow(title) {
            SettingsSlider(
                value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                range: Double(range.lowerBound)...Double(range.upperBound), step: step,
                label: percentage
                    ? (Double(value.wrappedValue) / 100).formatted(.percent.precision(.fractionLength(0)))
                    : value.wrappedValue.formatted())
        }
    }

    private var excludedApps: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Excluded apps").fontWeight(.medium)
                Spacer()
                Button("Add app…", action: chooseApps).controlSize(.small)
            }
            if settings.smoothScrollExcludedApps.isEmpty {
                Text("These apps keep their native mouse-wheel scrolling.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.smoothScrollExcludedApps, id: \.self) { identifier in
                HStack {
                    Text(appNames[identifier] ?? identifier).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button {
                        settings.smoothScrollExcludedApps.removeAll { $0 == identifier }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove exclusion")
                    .accessibilityLabel("Remove \(appNames[identifier] ?? identifier)")
                }
            }
            if let pickerError {
                Text(pickerError).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Exclude apps from smooth scrolling"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            var identifiers: [String] = []
            for url in panel.urls {
                guard let identifier = Bundle(url: url)?.bundleIdentifier else {
                    pickerError = "An app without a bundle identifier could not be added."
                    continue
                }
                identifiers.append(identifier)
            }
            if identifiers.count == panel.urls.count { pickerError = nil }
            settings.smoothScrollExcludedApps = SmoothScrollSupport.sanitizedExclusions(
                settings.smoothScrollExcludedApps + identifiers)
        }
    }

    private func refreshAppNames() {
        appNames = Dictionary(
            uniqueKeysWithValues: settings.smoothScrollExcludedApps.map { identifier in
                let name =
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)?
                    .deletingPathExtension().lastPathComponent ?? identifier
                return (identifier, name)
            })
    }
}
