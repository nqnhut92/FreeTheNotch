import SwiftUI

/// Provider and activity state flank the camera, leaving the physical cutout empty.
struct AIActivityCompactView: View {
    let activity: AIActivity
    let count: Int

    private var tint: Color { activity.provider == .claude ? .orange : .green }
    private var label: String {
        switch activity.state {
        case .working: return count > 1 ? "\(count.formatted()) AI" : "Working"
        case .waiting: return "Waiting"
        case .completed: return "Done"
        case .idle: return "Idle"
        case .stopped: return "Stopped"
        }
    }

    var body: some View {
        HStack {
            AIProviderGlyph(provider: activity.provider)
                .foregroundStyle(tint)
                .help(activity.provider.title)
            Spacer()
            HStack(spacing: 3) {
                Image(
                    systemName: activity.state == .completed
                        ? "checkmark.circle.fill" : activity.state == .waiting ? "pause.circle" : "sparkle")
                Text(label)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(activity.state == .completed ? .green : .white)
            .fixedSize()
        }
        .accessibilityLabel("\(activity.provider.title) \(label)")
    }
}
