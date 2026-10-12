// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// managers/IdleAnimationManager.swift and components/IdleAnimationView.swift.
// Bundled animations (LottieAnimations/*.json) are not Atoll's: they are free
// LottieFiles animations under the Lottie Simple License, credited in
// THIRD_PARTY_NOTICES.md.
//
// Simplified: no per-animation transform editor or remote URLs. An animation
// is a Lottie .json file, bundled or imported into Application Support, and
// is picked by its file name. The pets show in notch skins (SkinPets.swift)
// instead of Atoll's 30×20 in-notch pet, which is too small to read.

import AppKit
import Lottie
import SwiftUI
import UniformTypeIdentifiers

/// A Lottie pet, bundled or imported, known by its file name.
struct IdleAnimation: Identifiable, Hashable {
    let name: String
    let url: URL
    let isBuiltIn: Bool
    var id: String { name }
}

/// Why an imported file was turned down.
enum IdleAnimationImportError: LocalizedError {
    case notJSON
    case notLottie
    /// A bundled pet already has the name; the import would be hidden behind it.
    case nameTaken(String)

    var errorDescription: String? {
        switch self {
        case .notJSON: return "Choose a Lottie .json file."
        case .notLottie: return "That file is not a valid Lottie animation."
        case .nameTaken(let name):
            return "A built-in pet is already called “\(name)”. Rename the file and import it again."
        }
    }
}

/// The pets: bundled Lottie files plus the ones imported into Application Support.
final class IdleAnimationManager: ObservableObject {
    static let shared = IdleAnimationManager()

    /// Bundled pets (Atoll's IdleAnimationManager.loadBundledAnimations idea).
    /// The files come straight from the LottieFiles originals, not from
    /// Atoll. Tiger Happy rides the Jungle swing; Moody Dog walks in place
    /// under Sakura.
    static let bundledNames = ["Orange Cat Peeping", "Moody Dog", "Reindeer", "Tiger Happy"]

    @Published private(set) var animations: [IdleAnimation] = []

    /// ~/Library/Application Support/FreeTheNotch/IdleAnimations
    let storageDirectory: URL = {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("FreeTheNotch/IdleAnimations", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() { reload() }

    func reload() {
        let bundled = Self.bundledNames.compactMap { name -> IdleAnimation? in
            guard
                let url = Bundle.main.url(
                    forResource: name, withExtension: "json",
                    subdirectory: "LottieAnimations")
            else { return nil }
            return IdleAnimation(name: name, url: url, isBuiltIn: true)
        }
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: storageDirectory,
                includingPropertiesForKeys: nil)) ?? []
        // A file named like a bundled pet (left from before imports checked
        // the name) stays hidden behind it.
        let imported =
            files
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { IdleAnimation(name: $0.deletingPathExtension().lastPathComponent, url: $0, isBuiltIn: false) }
            .filter { anim in !bundled.contains { $0.name == anim.name } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        animations = bundled + imported
    }

    private var aspectCache: [String: CGFloat] = [:]

    /// Height / width of an animation's canvas (Lottie `h` / `w`), cached.
    func canvasAspect(named name: String) -> CGFloat {
        if let cached = aspectCache[name] { return cached }
        var aspect: CGFloat = 1
        if let anim = animations.first(where: { $0.name == name }),
            let data = try? Data(contentsOf: anim.url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let w = json["w"] as? Double, let h = json["h"] as? Double, w > 0
        {
            aspect = CGFloat(h / w)
        }
        aspectCache[name] = aspect
        return aspect
    }

    private var boundsCache: [String: CGRect] = [:]

    /// Part of the canvas the drawing actually uses (unit rect, top-left
    /// origin), found by rendering 10 frames at 200px and scanning alpha.
    /// Lets the Custom skin crop an imported pet like the built-in ones.
    func contentBounds(named name: String) -> CGRect {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let cached = boundsCache[name] { return cached }
        guard let anim = animations.first(where: { $0.name == name }),
            let animation = LottieAnimation.filepath(anim.url.path)
        else { return unit }
        let layer = LottieAnimationLayer(
            animation: animation,
            configuration: LottieConfiguration(renderingEngine: .mainThread))
        let full = animation.bounds.size
        guard full.width > 0, full.height > 0 else { return unit }
        let scale = 200 / max(full.width, full.height)
        let w = max(1, Int(full.width * scale))
        let h = max(1, Int(full.height * scale))
        var minX = w
        var minY = h
        var maxX = -1
        var maxY = -1
        for i in 0..<10 {
            layer.currentProgress = CGFloat(i) / 10
            layer.forceDisplayUpdate()
            guard
                let ctx = CGContext(
                    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                let data = ctx.data
            else { continue }
            // Top-left origin, scaled down. Without a LottieAnimationView to
            // lay it out, the inner animation layer sits centered on the origin.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: scale, y: -scale)
            ctx.translateBy(x: full.width / 2, y: full.height / 2)
            layer.render(in: ctx)
            let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
            for y in 0..<h {
                for x in 0..<w where px[(y * w + x) * 4 + 3] > 20 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        var result = unit
        if maxX >= minX, maxY >= minY {
            // One pixel of slack so antialiased edges are not shaved off.
            let x0 = max(0, minX - 1)
            let y0 = max(0, minY - 1)
            let x1 = min(w, maxX + 2)
            let y1 = min(h, maxY + 2)
            result = CGRect(
                x: CGFloat(x0) / CGFloat(w), y: CGFloat(y0) / CGFloat(h),
                width: CGFloat(x1 - x0) / CGFloat(w), height: CGFloat(y1 - y0) / CGFloat(h))
        }
        boundsCache[name] = result
        return result
    }

    func animation(named name: String) -> IdleAnimation? {
        animations.first { $0.name == name } ?? animations.first
    }

    /// Atoll's importLocalFile: copies a Lottie .json into storage.
    /// Returns the imported animation's name.
    @discardableResult
    func importFile(_ source: URL) throws -> String {
        guard source.pathExtension.lowercased() == "json" else { throw IdleAnimationImportError.notJSON }
        let name = source.deletingPathExtension().lastPathComponent
        if Self.bundledNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            throw IdleAnimationImportError.nameTaken(name)
        }
        // Reject files Lottie cannot read before copying them in.
        let data = try Data(contentsOf: source)
        guard (try? LottieAnimation.from(data: data)) != nil else { throw IdleAnimationImportError.notLottie }
        let destination = storageDirectory.appendingPathComponent(name + ".json")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try data.write(to: destination)
        boundsCache[name] = nil
        aspectCache[name] = nil
        reload()
        return name
    }

    func delete(_ animation: IdleAnimation) {
        guard !animation.isBuiltIn else { return }
        try? FileManager.default.removeItem(at: animation.url)
        reload()
    }

    /// NSOpenPanel for .json files (Atoll's fileImporter).
    func presentImportPanel(completion: @escaping (Result<String, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Lottie animation (.json)"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { completion(.success(try self.importFile(url))) } catch { completion(.failure(error)) }
        }
    }
}
