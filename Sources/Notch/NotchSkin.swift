// Notch skins: decorations drawn around the island plus an optional pet that
// hangs from it, like the iOS Dynamic Island skin apps. Our own feature (not
// in Atoll). The skins are fixed combinations of a decoration and a pet.

/// A skin's identity. The raw values are persisted (`ftn.notchSkin`).
enum NotchSkin: String, CaseIterable, Identifiable {
    case none, jungle, cozyCat, christmas, sakura, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .jungle: return "Jungle"
        case .cozyCat: return "Cozy Cat"
        case .christmas: return "Christmas"
        case .sakura: return "Sakura"
        case .custom: return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .none: return "Plain notch"
        case .jungle: return "Vines and a tiger cub on a swing"
        case .cozyCat: return "A cat hanging off the edge"
        case .christmas: return "Twinkling lights and a reindeer"
        case .sakura: return "Cherry blossoms and a walking dog"
        case .custom: return "Your own Lottie pet"
        }
    }

    var decoration: SkinDecoration? {
        switch self {
        case .jungle: return .vines
        case .christmas: return .lights
        case .sakura: return .blossoms
        case .none, .cozyCat, .custom: return nil
        }
    }
}

/// The drawing a skin puts around the island (SkinDecorationView).
enum SkinDecoration { case vines, lights, blossoms }
