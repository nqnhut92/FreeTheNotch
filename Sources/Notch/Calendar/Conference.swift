// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// components/Calendar/DynamicIslandCalendar.swift — ConferenceProvider.

import Foundation
import SwiftUI

/// The video-call service behind an event's meeting link.
enum ConferenceProvider: CaseIterable {
    case zoom, teams, meet, webex, facetime, gotomeeting, bluejeans, whereby, jitsi, discord, generic

    var name: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .meet: return "Meet"
        case .webex: return "Webex"
        case .facetime: return "FaceTime"
        case .gotomeeting: return "GoToMeeting"
        case .bluejeans: return "BlueJeans"
        case .whereby: return "Whereby"
        case .jitsi: return "Jitsi"
        case .discord: return "Discord"
        case .generic: return ""
        }
    }

    var color: Color {
        switch self {
        case .zoom: return Color(red: 0.16, green: 0.52, blue: 0.95)
        case .teams: return Color(red: 0.36, green: 0.42, blue: 0.89)
        case .meet: return Color(red: 0.0, green: 0.65, blue: 0.42)
        case .webex: return Color(red: 0.0, green: 0.71, blue: 0.84)
        case .facetime: return Color(red: 0.2, green: 0.78, blue: 0.35)
        case .gotomeeting: return Color(red: 0.95, green: 0.5, blue: 0.13)
        case .bluejeans: return Color(red: 0.0, green: 0.48, blue: 0.87)
        case .whereby: return Color(red: 0.27, green: 0.51, blue: 0.96)
        case .jitsi: return Color(red: 0.16, green: 0.68, blue: 0.95)
        case .discord: return Color(red: 0.35, green: 0.39, blue: 0.98)
        case .generic: return Color.accentColor
        }
    }

    /// Domains the service's links live on; a host matches a domain or any
    /// of its subdomains.
    private var domains: [String] {
        switch self {
        case .zoom: return ["zoom.us"]
        case .teams: return ["teams.microsoft.com"]
        case .meet: return ["meet.google.com"]
        case .webex: return ["webex.com"]
        case .facetime: return ["facetime.apple.com"]
        case .gotomeeting: return ["gotomeeting.com"]
        case .bluejeans: return ["bluejeans.com"]
        case .whereby: return ["whereby.com"]
        case .jitsi: return ["meet.jit.si"]
        case .discord: return ["discord.gg", "discord.com"]
        case .generic: return []
        }
    }

    var nativeURLScheme: String? {
        switch self {
        case .zoom: return "zoommtg"
        case .teams: return "msteams"
        case .facetime: return "facetime"
        case .discord: return "discord"
        default: return nil
        }
    }

    private func matches(host: String) -> Bool {
        if domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        // Self-hosted Jitsi servers have no common domain; Atoll matches
        // "jitsi" anywhere in the host. Only a whole label counts here.
        return self == .jitsi && host.split(separator: ".").contains("jitsi")
    }

    static func detect(from url: URL) -> ConferenceProvider {
        let host = url.host?.lowercased() ?? ""
        return allCases.first { $0.matches(host: host) } ?? .generic
    }

    /// The link the Join button opens: the service's app scheme when it has
    /// one. Zoom keeps its web link, as in Atoll.
    static func joinURL(for url: URL) -> URL {
        let provider = detect(from: url)
        guard provider != .zoom, let scheme = provider.nativeURLScheme,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = scheme
        return components.url ?? url
    }
}
