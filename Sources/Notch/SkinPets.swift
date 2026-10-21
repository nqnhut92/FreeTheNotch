// Pets for the notch skins (NotchSkin.swift): the bundled LottieFiles
// animations (IdleAnimationManager), cropped to the drawing so they are not
// lost in the files' empty canvas. Our own feature (not in Atoll).

import Lottie
import SwiftUI

extension NotchSkin {
    /// Built-in pet. `.custom` reads the selected animation from settings.
    var pet: SkinPet? {
        switch self {
        case .jungle: return .swingingTiger
        case .cozyCat: return .peekingCat
        case .christmas: return .hangingReindeer
        case .sakura: return .walkingDog
        case .none, .custom: return nil
        }
    }
}

/// A Lottie pet and how it hangs from the island.
struct SkinPet {
    enum Placement {
        /// Turned upside down with its flat cut edge tucked behind the island.
        case peekUpsideDown
        /// Sitting on a plank hung from two ropes, swaying.
        case swing
        /// Upright, top edge just under the island.
        case dangle
    }

    let animationName: String
    /// Part of the Lottie canvas that holds the drawing (unit coordinates).
    let crop: CGRect
    let placement: Placement
    /// Width in points at size 1×.
    let width: CGFloat
    /// Horizontal position along the island (0 = left edge, 1 = right edge).
    let xFraction: CGFloat
    /// Share of the pet's height hidden behind the island.
    var tuck: CGFloat = 0
    /// Extra room between the island and an upright pet, in points.
    var gap: CGFloat = 0

    /// Crops measured from the files' bounding boxes. The peeking cat keeps
    /// only its head and paws, the reindeer its body under the cut edge.
    static let peekingCat = SkinPet(
        animationName: "Orange Cat Peeping",
        crop: CGRect(x: 0.16, y: 0.715, width: 0.68, height: 0.285),
        placement: .peekUpsideDown, width: 52, xFraction: 0.72, tuck: 0.02)
    static let hangingReindeer = SkinPet(
        animationName: "Reindeer",
        crop: CGRect(x: 0.03, y: 0.29, width: 0.94, height: 0.71),
        placement: .peekUpsideDown, width: 66, xFraction: 0.7, tuck: 0.06)
    /// Moody Dog walks in place on its floor line, a little below the island
    /// so its ears do not touch it. Measured once, on first use: measuring
    /// renders frames of the animation on the main thread.
    static let walkingDog: SkinPet = {
        var pet = SkinPet.bundled("Moody Dog", width: 50, xFraction: 0.22)
        pet.gap = 3
        return pet
    }()
    /// Tiger Happy sits on a small shadow; the swing plank covers it.
    /// Measured once, like `walkingDog`.
    static let swingingTiger = SkinPet.bundled("Tiger Happy", placement: .swing, width: 46)

    /// A bundled or imported animation, cropped to its drawing (found by
    /// rendering it: IdleAnimationManager.contentBounds, cached per name).
    static func bundled(
        _ name: String, placement: Placement = .dangle,
        width: CGFloat, xFraction: CGFloat = 0.7
    ) -> SkinPet {
        SkinPet(
            animationName: name, crop: IdleAnimationManager.shared.contentBounds(named: name),
            placement: placement, width: width, xFraction: xFraction)
    }

    /// The Custom skin's pet.
    static func custom(named name: String) -> SkinPet {
        bundled(name, width: 56)
    }
}

// MARK: - Layers

/// Everything a skin draws for one island. Sized to the island shape; draws
/// outside it. Never takes clicks: the island's own hit area is unchanged.
struct NotchSkinLayer: View {
    enum Part { case behindIsland, aboveIsland }

    let part: Part
    let shapeSize: CGSize
    /// The island is hovered or open.
    var isEngaged = false
    /// False while the screen is locked or asleep.
    var isOnScreen = true
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var media: MediaRemoteAdapter
    @EnvironmentObject var power: BatteryHUDController
    /// Set `SkinMotion.idleDelay` after the island was last active.
    @State private var hasIdled = false

    private var isActive: Bool { isEngaged || danceBPM != nil }

    private var motion: SkinMotion {
        SkinMotion.resolve(
            isNotchVisible: isOnScreen, isOnBattery: power.isOnBattery,
            isLowPowerMode: power.isInLowPowerMode, isActive: isActive, hasIdled: hasIdled)
    }

    /// Tempo the pet dances to while music plays: the track's BPM from Music
    /// when it has one, else a typical pop tempo. There is no audio tap, so
    /// it is in tempo, not locked to the actual beat.
    private var danceBPM: Double? {
        guard settings.mediaEnabled, media.isPlaying else { return nil }
        return Double(media.trackBPM ?? 112)
    }

    var body: some View {
        Group {
            switch part {
            case .behindIsland:
                if let pet = resolvedPet {
                    SkinPetView(
                        pet: pet, shapeSize: shapeSize,
                        scale: settings.petScale(for: settings.notchSkin), speed: settings.idleAnimationSpeed,
                        danceBPM: danceBPM, motion: motion)
                }
            case .aboveIsland:
                if let decoration = settings.notchSkin.decoration {
                    SkinDecorationView(decoration: decoration, shapeSize: shapeSize, motion: motion)
                }
            }
        }
        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
        .allowsHitTesting(false)
        .transition(.opacity)
        .task(id: isActive) { await trackIdle() }
    }

    /// Counts the idle delay down from the moment the island stops being
    /// active; any activity restarts it.
    private func trackIdle() async {
        hasIdled = false
        guard !isActive else { return }
        do {
            try await Task.sleep(for: .seconds(SkinMotion.idleDelay))
            hasIdled = true
        } catch {
            // Cancelled: the island became active again.
        }
    }

    private var resolvedPet: SkinPet? {
        let skin = settings.notchSkin
        if skin == .custom {
            guard let anim = IdleAnimationManager.shared.animation(named: settings.idleAnimationName) else {
                return nil
            }
            return .custom(named: anim.name)
        }
        return skin.pet
    }
}

/// A pet hanging under the island. Drawn behind the island so the tucked
/// part disappears behind it.
struct SkinPetView: View {
    let pet: SkinPet
    let shapeSize: CGSize
    var scale: Double = 1
    var speed: Double = 1
    /// Set while music plays: the pet bobs and nods on every beat.
    var danceBPM: Double?
    var motion: SkinMotion = .smooth

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var petWidth: CGFloat { pet.width * scale }

    /// Idle: a lazy sway. Music: one swing per beat, wider.
    private var swingCurve: SkinMotionCurve? {
        guard !reduceMotion else { return nil }
        return danceBPM.map { .beatSwing(bpm: $0) } ?? .sway
    }

    /// Bob and nod on every beat while music plays.
    private var danceCurve: SkinMotionCurve? {
        guard !reduceMotion, let danceBPM else { return nil }
        return .beatDance(bpm: danceBPM, amount: scale)
    }

    var body: some View {
        let x = shapeSize.width * pet.xFraction - shapeSize.width / 2
        let isPlaying = !motion.isStill
        Group {
            switch pet.placement {
            case .peekUpsideDown:
                let h = CroppedLottie.height(for: pet, width: petWidth)
                CoreAnimationMotion(curve: danceCurve, frameRate: motion.danceFrameRate, isPaused: motion.isStill) {
                    CroppedLottie(pet: pet, width: petWidth, speed: speed, isPlaying: isPlaying)
                        .rotationEffect(.degrees(180))
                }
                .offset(x: x, y: shapeSize.height - h * pet.tuck)
            case .dangle:
                CoreAnimationMotion(curve: danceCurve, frameRate: motion.danceFrameRate, isPaused: motion.isStill) {
                    CroppedLottie(pet: pet, width: petWidth, speed: speed, isPlaying: isPlaying)
                }
                .offset(x: x, y: shapeSize.height - 2 + pet.gap * scale)
            case .swing:
                CoreAnimationMotion(curve: swingCurve, frameRate: motion.frameRate, isPaused: motion.isStill) {
                    swing(isPlaying: isPlaying)
                }
                .offset(x: x, y: shapeSize.height - 4)
            }
        }
        .frame(width: shapeSize.width, alignment: .top)
    }

    /// Two ropes from under the island, a plank, and the pet sitting on it.
    private func swing(isPlaying: Bool) -> some View {
        let ropeLength = 18 * scale
        let petHeight = CroppedLottie.height(for: pet, width: petWidth)
        let plankWidth = petWidth * 1.05
        return VStack(spacing: 0) {
            HStack {
                rope(length: ropeLength + petHeight * 0.9)
                Spacer()
                rope(length: ropeLength + petHeight * 0.9)
            }
            .frame(width: plankWidth - 6)
            .overlay(alignment: .bottom) {
                CroppedLottie(pet: pet, width: petWidth, speed: speed, isPlaying: isPlaying)
                    .padding(.bottom, -petHeight * 0.07)
            }
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.62, green: 0.42, blue: 0.24),
                            Color(red: 0.45, green: 0.29, blue: 0.15),
                        ],
                        startPoint: .top, endPoint: .bottom)
                )
                .frame(width: plankWidth, height: 6 * scale)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        }
    }

    private func rope(length: CGFloat) -> some View {
        Capsule()
            .fill(Color(red: 0.36, green: 0.5, blue: 0.22))
            .frame(width: 2, height: length)
    }
}

/// Lottie view that shows only the drawing's part of the canvas, so the pet
/// fills its frame instead of floating in empty space.
struct CroppedLottie: View {
    let pet: SkinPet
    let width: CGFloat
    var speed: Double = 1
    var isPlaying = true

    @ObservedObject private var manager = IdleAnimationManager.shared

    /// Loops while playing; paused, it holds the current frame.
    private var playbackMode: LottiePlaybackMode {
        isPlaying ? .playing(.fromProgress(nil, toProgress: 1, loopMode: .loop)) : .paused(at: .currentFrame)
    }

    static func canvasAspect(_ name: String) -> CGFloat {
        IdleAnimationManager.shared.canvasAspect(named: name)
    }

    /// Height of the cropped pet at `width`.
    static func height(for pet: SkinPet, width: CGFloat) -> CGFloat {
        let fullWidth = width / pet.crop.width
        return fullWidth * canvasAspect(pet.animationName) * pet.crop.height
    }

    var body: some View {
        let fullWidth = width / pet.crop.width
        let fullHeight = fullWidth * Self.canvasAspect(pet.animationName)
        let height = fullHeight * pet.crop.height
        if let anim = manager.animations.first(where: { $0.name == pet.animationName }) {
            LottieView(animation: .filepath(anim.url.path))
                .playbackMode(playbackMode)
                .animationSpeed(speed)
                .resizable()
                .frame(width: fullWidth, height: fullHeight)
                .offset(x: -pet.crop.minX * fullWidth, y: -pet.crop.minY * fullHeight)
                .frame(width: width, height: height, alignment: .topLeading)
                .clipped()
        }
    }
}
