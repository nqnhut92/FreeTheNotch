import SwiftUI

/// Drawn with system symbols and text; no third-party logo assets are bundled.
struct AIProviderGlyph: View {
    let provider: AIUsageProvider

    var body: some View {
        Text(provider == .codex ? "C›" : "✳")
            .font(.system(size: provider == .codex ? 16 : 23, weight: .bold, design: .monospaced))
            .frame(width: 26, height: 26)
    }
}
