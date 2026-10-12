import SwiftUI

/// Atoll's reminder checkbox: a circle that fills when completed.
struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

/// Atoll-style reminder card: toggle + title + time, on a subtle rounded background.
struct ReminderCard: View {
    let reminder: AgendaReminder
    let onToggle: (Bool) -> Void
    var accent: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            ReminderToggle(
                isOn: Binding(
                    get: { reminder.isCompleted },
                    set: { onToggle($0) }
                ),
                color: accent
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if !reminder.hasTime {
                    Text("All-day")
                        .font(.caption)
                        .foregroundStyle(.notchSecondary)
                }
            }

            Spacer(minLength: 8)

            if reminder.hasTime, let due = reminder.dueDate {
                Text(due, style: .time)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.75))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .opacity(reminder.isCompleted ? 0.55 : 1)
    }
}
