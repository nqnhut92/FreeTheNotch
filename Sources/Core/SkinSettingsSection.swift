// Grew out of Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// components/Settings/IdleAnimationsSettingsSection.swift.

import SwiftUI

/// Settings → Skins: pick a skin from live previews, pet size and speed, hide while open, and
/// the Custom skin's animation (pick, import a .json, delete imports).
struct SkinSettingsSection: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var manager = IdleAnimationManager.shared
    @State private var importError: String?
    /// Animated previews: stop their canvases while Settings is in
    /// the background (AGENTS.md, render cost).
    @Environment(\.controlActiveState) private var activeState

    private var selected: IdleAnimation? { manager.animation(named: settings.idleAnimationName) }

    /// The size of the selected skin's pet (per animation for Custom).
    private var petScale: Binding<Double> {
        Binding(
            get: { settings.petScale(for: settings.notchSkin) },
            set: { settings.setPetScale($0, for: settings.notchSkin) })
    }

    /// Imported files vary more in how much of their canvas the drawing
    /// fills, so Custom goes larger.
    private var petScaleRange: ClosedRange<Double> {
        settings.notchSkin == .custom ? 0.6...2.5 : 0.6...1.8
    }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No group header: the page title already says Skins.
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(NotchSkin.allCases) { skin in
                    skinCard(skin)
                }
            }
            .padding(.top, 8)
            if settings.notchSkin != .none {
                SettingsCard {
                    if settings.notchSkin.pet != nil || settings.notchSkin == .custom {
                        SettingsRow(
                            "Pet size",
                            description: settings.notchSkin == .custom ? "Saved for each animation" : nil
                        ) {
                            HStack(spacing: 10) {
                                Slider(value: petScale, in: petScaleRange, step: 0.1)
                                    .frame(width: 150)
                                Text(petScale.wrappedValue.formatted(.number.precision(.fractionLength(1))) + "×")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        SettingsRow("Pet speed") {
                            HStack(spacing: 10) {
                                Slider(value: $settings.idleAnimationSpeed, in: 0.25...2, step: 0.25)
                                    .frame(width: 150)
                                Text(
                                    settings.idleAnimationSpeed.formatted(.number.precision(.fractionLength(0...2)))
                                        + "×"
                                )
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary)
                                .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                    if settings.notchSkin == .custom {
                        SettingsRow("Animation") {
                            Picker("", selection: $settings.idleAnimationName) {
                                ForEach(manager.animations) { anim in
                                    Text(anim.isBuiltIn ? anim.name : "\(anim.name) (imported)").tag(anim.name)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }
                        SettingsRow(
                            "Custom animations",
                            description: importError ?? "Import a Lottie .json file, e.g. from lottiefiles.com"
                        ) {
                            HStack(spacing: 8) {
                                if let selected, !selected.isBuiltIn {
                                    Button("Delete", role: .destructive) {
                                        manager.delete(selected)
                                        settings.customPetScales[selected.name] = nil
                                        settings.idleAnimationName = manager.animations.first?.name ?? ""
                                    }
                                }
                                Button("Import…") {
                                    manager.presentImportPanel { result in
                                        switch result {
                                        case .success(let name):
                                            importError = nil
                                            settings.idleAnimationName = name
                                        case .failure(let error):
                                            importError =
                                                (error as? LocalizedError)?.errorDescription
                                                ?? "That file could not be imported."
                                        }
                                    }
                                }
                            }
                        }
                    }
                    SettingsRow(
                        "Hide while the notch is open",
                        description: "Show the skin only on the closed island", showDivider: false
                    ) {
                        Toggle("", isOn: $settings.skinHideWhenExpanded).toggleStyle(.switch).labelsHidden()
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    /// Live preview: a small island on a wallpaper-like gradient with the
    /// skin's decoration and pet at 70% size.
    private func skinCard(_ skin: NotchSkin) -> some View {
        let isSelected = settings.notchSkin == skin
        let island = CGSize(width: 104, height: 22)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { settings.notchSkin = skin }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.36, green: 0.52, blue: 0.86),
                            Color(red: 0.62, green: 0.46, blue: 0.82),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    ZStack(alignment: .top) {
                        if let pet = previewPet(skin) {
                            SkinPetView(
                                pet: pet, shapeSize: island, scale: 0.7 * settings.petScale(for: skin),
                                speed: settings.idleAnimationSpeed
                            )
                            .frame(width: island.width, height: island.height, alignment: .top)
                        }
                        NotchShape(topRadius: 0, bottomRadius: 10)
                            .fill(Color.black)
                            .frame(width: island.width, height: island.height)
                        if let decoration = skin.decoration {
                            SkinDecorationView(
                                decoration: decoration, shapeSize: island,
                                isPaused: activeState == .inactive)
                        }
                    }
                }
                .frame(height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                            lineWidth: isSelected ? 2.5 : 1)
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(skin.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(skin.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func previewPet(_ skin: NotchSkin) -> SkinPet? {
        if skin == .custom {
            return manager.animation(named: settings.idleAnimationName).map { .custom(named: $0.name) }
        }
        return skin.pet
    }
}
