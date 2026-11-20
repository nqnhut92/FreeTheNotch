import Foundation

/// The players whose songs are shown on a spinning record instead of a square cover.
enum VinylSource {
    private static let bundleIdentifiers: Set<String> = ["com.apple.Music"]

    static func isRecordPlayer(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return bundleIdentifiers.contains(bundleIdentifier)
    }
}
