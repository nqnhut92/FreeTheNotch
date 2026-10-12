import Foundation

/// What the About page says about the app.
enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/nqnhut92/FreeTheNotch")!
    static let author = "Nicholas Nguyen"
    /// The year the copyright line starts.
    static let firstYear = 2026

    /// "2026 Nicholas Nguyen", then "2026-2027 Nicholas Nguyen" from the
    /// next year on.
    static func authorLine(year: Int) -> String {
        let year = max(year, firstYear)
        let years = year == firstYear ? "\(firstYear)" : "\(firstYear)-\(year)"
        return "\(years) \(author)"
    }

    static var authorLine: String {
        authorLine(year: Calendar(identifier: .gregorian).component(.year, from: Date()))
    }

    /// "Version 0.1.0 (build-20261012.161857)". The "Bundle media bridge"
    /// build phase stamps CFBundleVersion with the build time
    /// (YYYYMMDD.HHMMSS).
    static func versionLine(info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(version) (build-\($0))" } ?? "Version \(version)"
    }

    static var versionLine: String { versionLine(info: Bundle.main.infoDictionary) }
}
