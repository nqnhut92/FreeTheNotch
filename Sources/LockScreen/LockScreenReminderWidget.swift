import SwiftUI

/// Atoll's lock-screen reminder widget: non-interactive horizontal bar showing
/// icon + title + relative time ("in 15 min") + absolute time.
struct LockScreenReminderWidget: View {
    let title: String
    let dueDate: Date?
    let hasTime: Bool

    init(reminder: AgendaReminder) {
        title = reminder.title
        dueDate = reminder.dueDate
        hasTime = reminder.hasTime
    }

    /// A stand-in reminder for the Settings preview.
    init(title: String, dueDate: Date) {
        self.title = title
        self.dueDate = dueDate
        hasTime = true
    }

    private let primaryFont = Font.system(size: 19, weight: .semibold, design: .rounded)
    private let iconSize: CGFloat = 20
    private let chipWidth: CGFloat = 9

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "bell.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: chipWidth, height: iconSize)

            Text(title)
                .font(primaryFont)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
                .layoutPriority(1)
                .frame(height: iconSize, alignment: .center)

            if let due = dueDate {
                // The lock screen is built once per lock: count down by
                // the minute. Cheap enough to run while hidden.
                TimelineView(.everyMinute) { context in
                    HStack(spacing: 8) {
                        separator
                        Text(LockScreenFormat.relativeDescription(due: due, now: context.date))
                            .font(primaryFont)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .allowsTightening(true)
                            .frame(height: iconSize, alignment: .center)
                    }
                }
                .layoutPriority(0.75)
            }

            if hasTime, let due = dueDate {
                separator
                Text(due, style: .time)
                    .font(primaryFont)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .layoutPriority(0.75)
                    .frame(height: iconSize, alignment: .center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 240, idealWidth: 360, maxWidth: 520, alignment: .leading)
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
    }

    private var separator: some View {
        Text("•")
            .font(primaryFont)
            .foregroundStyle(.white.opacity(0.65))
            .frame(height: iconSize, alignment: .center)
    }
}
