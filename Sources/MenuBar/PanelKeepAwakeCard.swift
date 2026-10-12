import ApplicationServices
import SwiftUI

// MARK: - Keep awake card

// Port of Vorssaint's KeepAwakeCard, KeepAwakeChipStyle and
// KeepAwakeEndTimePicker (vorssaint/vorssaint-utils, GPL-3.0-or-later),
// trimmed to the options FreeTheNotch supports.
struct PanelKeepAwakeCard: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var awake: KeepAwakeController

    /// Session durations in minutes; 0 keeps the session open until stopped.
    private static let choices = [15, 30, 60, 120, 240, 480, 0]

    /// The last started end time, which the popover opens on.
    @AppStorage("panel.keepAwakeUntilTime") private var savedUntilTime = 0.0
    /// An edit not started yet; only starting saves it.
    @State private var untilDraft: Date?

    /// Only the hour and minute matter; `resolvedUntilDate` picks the next one.
    private var untilTime: Binding<Date> {
        Binding(
            get: {
                untilDraft
                    ?? (savedUntilTime > 0
                        ? Date(timeIntervalSinceReferenceDate: savedUntilTime)
                        : Date().addingTimeInterval(3600))
            },
            set: { untilDraft = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if awake.isActive, awake.endDate != nil {
                    // Beside the extend chips a narrow panel has no room for the
                    // status; the highlighted chip already shows the countdown.
                    ViewThatFits(in: .horizontal) {
                        statusLine.fixedSize()
                        Color.clear.frame(width: 0, height: 0)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach([15, 30, 60], id: \.self) { minutes in
                            Button("+" + Self.shortTitle(for: minutes)) {
                                awake.extend(minutes: minutes)
                            }
                            .buttonStyle(KeepAwakeChipStyle())
                            .fixedSize()
                        }
                    }
                } else {
                    statusLine
                    Spacer(minLength: 4)
                }
                Toggle("Keep awake", isOn: activeBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            // One click starts (or switches) a session; clicking the
            // highlighted chip stops it. The switch reuses the last pick.
            // The row folds into two rows of four when one would truncate.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    ForEach(Self.choices, id: \.self, content: durationChip)
                    untilChip
                }
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(Self.choices.prefix(4), id: \.self, content: durationChip)
                    }
                    HStack(spacing: 4) {
                        ForEach(Self.choices.dropFirst(4), id: \.self, content: durationChip)
                        untilChip
                    }
                }
            }

            // Shown in both states so starting or stopping never changes the
            // card's height (the panel would jump). Battery protection blocks
            // a session from starting, so say why a chip seems to do nothing.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                if let percent = awake.batteryProtectionPercent() {
                    Label(
                        "Battery at \(percent)%. Plug in or turn off battery protection to start",
                        systemImage: "battery.25percent"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                } else {
                    Text("Click a chip to start. Click it again to stop")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.panelTertiary)
                }
            }

            optionsDisclosure
        }
        .panelCard()
    }

    // MARK: Status

    private var statusLine: some View {
        Group {
            if awake.isActive {
                if let end = awake.endDate {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("Ends in \(Self.remainingText(until: end))")
                    }
                } else {
                    Text("Active until you turn it off")
                }
            } else {
                Text("The Mac follows its normal energy rules")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.panelSecondary)
        .monospacedDigit()
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { awake.isActive },
            set: { on in
                if on { awake.startLastPick() } else if awake.isActive { awake.stop() }
            }
        )
    }

    // MARK: Chips

    private func durationChip(_ minutes: Int) -> some View {
        let selected = awake.isActive && awake.sessionMinutes == minutes
        return Button {
            if selected { awake.stop() } else { awake.start(minutes: minutes) }
        } label: {
            // Every timed chip reserves "0:00:00", so ViewThatFits measures the
            // countdown and neither a start nor an extend can overflow the row.
            ZStack {
                Text(Self.shortTitle(for: minutes))
                if minutes > 0 {
                    Text("0:00:00").hidden()
                }
            }
            .opacity(selected && awake.endDate != nil ? 0 : 1)
            .overlay {
                if selected, let end = awake.endDate {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Self.countdownText(until: end))
                            .fixedSize()
                    }
                }
            }
        }
        .buttonStyle(KeepAwakeChipStyle(isSelected: selected))
        .accessibilityLabel(Self.accessibilityTitle(for: minutes))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var untilChip: some View {
        KeepAwakeEndTimePicker(
            selection: untilTime,
            activeEnd: awake.isActive && awake.sessionMinutes == nil ? awake.endDate : nil,
            onStop: awake.stop,
            onStart: startUntilSession)
    }

    private func startUntilSession() {
        let picked = untilTime.wrappedValue
        awake.start(until: KeepAwakeEndTimePicker.resolvedUntilDate(picked: picked, now: Date()))
        savedUntilTime = picked.timeIntervalSinceReferenceDate
        untilDraft = nil
    }

    // MARK: Options

    /// Always expanded: no reason to hide them behind a disclosure.
    private var optionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Options")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            compactOptionToggle(
                icon: "lock.fill",
                title: "Pause while the Mac is locked",
                isOn: $settings.awakePauseWhileLocked)
            compactOptionToggle(
                icon: "battery.25percent",
                title: "Stop when battery is below \(KeepAwakeController.batteryProtectionThreshold)%",
                isOn: $settings.awakeBatteryProtection)
            // AXIsProcessTrusted() isn't observable; re-check while shown.
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                mouseJiggleOptions(needsAccessibility: settings.awakeMouseJiggle && !AXIsProcessTrusted())
            }
        }
    }

    @ViewBuilder
    private func mouseJiggleOptions(needsAccessibility: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            compactOptionToggle(
                icon: "cursorarrow.motionlines",
                title: "Move pointer slightly",
                isOn: $settings.awakeMouseJiggle,
                errorText: needsAccessibility ? "Permission required: Accessibility" : nil
            )
            .help(
                "Nudges the cursor one pixel every few minutes so apps like Teams keep reporting \u{201C}Available\u{201D}."
            )
            if settings.awakeMouseJiggle {
                HStack(spacing: 8) {
                    Text("Interval")
                        .font(.system(size: 11))
                        .foregroundStyle(.panelSecondary)
                    Spacer(minLength: 0)
                    Picker("Interval", selection: $settings.awakeMouseJiggleIntervalMinutes) {
                        ForEach(SettingsStore.allowedJiggleIntervals, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
                if needsAccessibility {
                    Button("Grant access") { SystemSettings.open(.accessibility) }
                        .buttonStyle(PanelButtonStyle())
                        .controlSize(.small)
                }
            }
        }
    }

    private func compactOptionToggle(
        icon: String,
        title: String,
        isOn: Binding<Bool>,
        errorText: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Toggle(title, isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.red)
                    .padding(.leading, 22)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Formatting

    /// Chip-sized label: "15m", "1h", "∞".
    static func shortTitle(for minutes: Int) -> String {
        guard minutes > 0 else { return "\u{221E}" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m"
    }

    static func accessibilityTitle(for minutes: Int) -> String {
        switch minutes {
        case 0: return "Until stopped"
        case 60: return "1 hour"
        case let m where m % 60 == 0: return "\(m / 60) hours"
        default: return "\(minutes) minutes"
        }
    }

    /// "58:12" or "1:05:12" for the highlighted chip.
    static func countdownText(until end: Date) -> String {
        DurationFormat.clock(Int(end.timeIntervalSinceNow))
    }

    /// "1 h 05 min" style countdown for the status line.
    static func remainingText(until end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSinceNow))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d h %02d min", hours, minutes) }
        if minutes > 0 { return String(format: "%d min %02d s", minutes, seconds) }
        return "\(seconds) s"
    }
}

/// Capsule chip used for the Keep awake presets and extensions.
struct KeepAwakeChipStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1)
                        : Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07))
            )
            .contentShape(Capsule())
    }
}

/// The "Until…" chip beside the duration chips. It opens hour and minute
/// wheels (scroll, click a neighbour, or arrow keys) plus a field to type an
/// exact time, and starts the session from the popover. While that session
/// runs the chip shows its end time, and a click stops it like any chip.
struct KeepAwakeEndTimePicker: View {
    @Binding var selection: Date
    /// The end of a running "until" session, shown on the highlighted chip.
    var activeEnd: Date?
    var onStop: () -> Void
    var onStart: () -> Void
    @State private var isPresented = false

    /// A time with the widest hour, so the reserved width fits any end time.
    private static let widestTime =
        Calendar.current.date(bySettingHour: 22, minute: 22, second: 0, of: Date()) ?? Date()

    /// The next occurrence of the picked hour and minute (today, or tomorrow
    /// once that time has passed).
    static func resolvedUntilDate(picked: Date, now: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: picked)
        return calendar.nextDate(
            after: now, matching: DateComponents(hour: parts.hour, minute: parts.minute, second: 0),
            matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
    }

    var body: some View {
        Button {
            if activeEnd != nil { onStop() } else { isPresented.toggle() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                // Both labels hold their width, so starting or stopping never
                // resizes the chip and moves the row between one and two lines.
                ZStack {
                    Text("Until\u{2026}")
                        .opacity(activeEnd == nil ? 1 : 0)
                    Text(activeEnd ?? Self.widestTime, style: .time)
                        .opacity(activeEnd == nil ? 0 : 1)
                }
            }
        }
        .buttonStyle(KeepAwakeChipStyle(isSelected: activeEnd != nil))
        .accessibilityAddTraits(activeEnd != nil ? .isSelected : [])
        .fixedSize()
        .accessibilityLabel("Until")
        .accessibilityValue(activeEnd.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            editor
        }
    }

    private var editor: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Until")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                DatePicker("Until", selection: $selection, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .controlSize(.small)
                    .labelsHidden()
                    .fixedSize()
            }

            HStack(spacing: 4) {
                TimeDigitWheel(title: "Hour (0\u{2013}23)", range: 24, value: part(.hour))
                Text(":")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.panelTertiary)
                TimeDigitWheel(title: "Minute", range: 60, value: part(.minute))
            }

            Divider()
            HStack {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(endSummary(now: context.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("Start") {
                    isPresented = false
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .frame(width: 224)
    }

    private func part(_ component: Calendar.Component) -> Binding<Int> {
        Binding(
            get: { Calendar.current.component(component, from: selection) },
            set: { value in
                // Edit on a neutral date: the session resolves the next
                // occurrence at activation, including a DST transition.
                var parts = Calendar.current.dateComponents([.hour, .minute], from: selection)
                parts.setValue(value, for: component)
                parts.year = 2001
                parts.month = 1
                parts.day = 15
                if let date = Calendar.current.date(from: parts) { selection = date }
            }
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let remainingFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    /// "Today · 1h 5m".
    private func endSummary(now: Date) -> String {
        let end = Self.resolvedUntilDate(picked: selection, now: now)
        let remaining = Self.remainingFormatter.string(from: max(60, end.timeIntervalSince(now))) ?? ""
        return "\(Self.dayFormatter.string(from: end)) \u{00B7} \(remaining)"
    }
}

/// One scrollable two-digit column: the current value with its neighbours
/// above and below. Scrolling, clicking a neighbour, or the arrow keys step
/// it, wrapping at the ends.
struct TimeDigitWheel: View {
    let title: String
    let range: Int
    @Binding var value: Int
    @State private var hovering = false
    @State private var monitor: Any?
    @State private var accumulated: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            neighbour(-1)
            Text(String(format: "%02d", value))
                .font(.system(size: 26, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(hovering ? 0.2 : 0.13)))
            neighbour(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .focusable()
        .onKeyPress(.upArrow) {
            step(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            step(1)
            return .handled
        }
        .onAppear(perform: installMonitor)
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(String(format: "%02d", value))
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }

    private func neighbour(_ offset: Int) -> some View {
        Text(String(format: "%02d", wrapped(value + offset)))
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.panelSecondary)
            .frame(width: 52, height: 20)
            .contentShape(Rectangle())
            .onTapGesture { step(offset) }
    }

    private func step(_ delta: Int) {
        value = wrapped(value + delta)
    }

    private func wrapped(_ n: Int) -> Int {
        (n % range + range) % range
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard hovering else { return event }
            // Momentum is ignored so a flick stops where the finger lifts.
            guard event.momentumPhase.isEmpty else { return nil }
            // Trackpads report fine deltas; a mouse wheel reports whole notches.
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 8 : 1
            accumulated += event.scrollingDeltaY
            while abs(accumulated) >= threshold {
                // Moving content up brings the next (larger) value into the middle.
                step(accumulated < 0 ? 1 : -1)
                accumulated += accumulated < 0 ? threshold : -threshold
            }
            return nil
        }
    }
}
