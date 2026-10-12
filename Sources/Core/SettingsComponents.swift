import AppKit
import SwiftUI

// MARK: - Cards and rows (iOS Settings style)

/// A white rounded card containing settings rows, iOS Settings style.
struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }
}

/// One row inside a card: title + optional description on the left,
/// control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    let control: Control
    let showDivider: Bool

    init(_ title: String, description: String? = nil, showDivider: Bool = true, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
        self.showDivider = showDivider
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14))
                    if let description {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                control
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if showDivider {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}

/// A row whose control is an on/off switch.
struct SettingsToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool
    let showDivider: Bool

    init(_ title: String, description: String? = nil, isOn: Binding<Bool>, showDivider: Bool = true) {
        self.title = title
        self.description = description
        self._isOn = isOn
        self.showDivider = showDivider
    }

    var body: some View {
        SettingsRow(title, description: description, showDivider: showDivider) {
            SettingsSwitch(isOn: $isOn)
        }
    }
}

/// The switch every settings row uses: no label (the row has the title).
struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
    }
}

/// Section header above a card, iOS style.
struct SettingsGroupHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
            .padding(.bottom, 6)
            .padding(.top, 16)
    }
}

/// A short note under a card.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }
}

/// A slider with its value beside it.
struct SettingsSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range, step: step)
                .frame(width: 150)
                .tint(.blue)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

/// A picker card: one of a row of options, outlined and ticked when
/// selected (Settings → General → Displays, Side Notch → Edge).
struct SelectableCard<Label: View>: View {
    let isSelected: Bool
    var minHeight: CGFloat?
    let action: () -> Void
    @ViewBuilder let label: Label

    private static var cornerRadius: CGFloat { 12 }

    var body: some View {
        Button(action: action) {
            label
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 2 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reordering

/// A row that can be dragged by its ≡ handle (Appearance → Notch Tabs,
/// Side Notch → Cells). Drop on another row with `ReorderDropDelegate`.
struct ReorderRow<Label: View, Trailing: View, DragPreview: View>: View {
    /// The drag's text payload.
    let payload: String
    @ViewBuilder let label: Label
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let dragPreview: DragPreview
    /// Called as the drag starts, to record the dragged item.
    let onDragStart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 26)
                .contentShape(Rectangle())
                .openHandCursor()
                .onDrag {
                    onDragStart()
                    return NSItemProvider(object: payload as NSString)
                } preview: {
                    dragPreview
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }
                .help("Drag to reorder")
            label
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Live reordering: the dragged row takes the hovered row's place as soon
/// as the pointer enters it.
struct ReorderDropDelegate<Item: Equatable>: DropDelegate {
    let target: Item
    @Binding var dragging: Item?
    @Binding var order: [Item]

    func dropEntered(info: DropInfo) {
        guard let dragging else { return }
        let reordered = order.moving(dragging, onto: target)
        guard reordered != order else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            order = reordered
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

extension Array where Element: Equatable {
    /// `item` moved into `target`'s place: after it when moving down, before
    /// it when moving up. Unchanged when either is missing or they are the
    /// same.
    func moving(_ item: Element, onto target: Element) -> [Element] {
        guard item != target, let from = firstIndex(of: item), let to = firstIndex(of: target) else { return self }
        var result = self
        result.remove(at: from)
        result.insert(item, at: to)
        return result
    }
}

// MARK: - Cursor

extension View {
    /// The open hand over a draggable area, while `isActive`.
    func openHandCursor(isActive: Bool = true) -> some View {
        modifier(OpenHandCursor(isActive: isActive))
    }
}

/// `pointerStyle` on macOS 15; before that, one NSCursor push per hover,
/// always popped again (on exit, when deactivated, or when the view goes),
/// so the cursor stack stays balanced.
private struct OpenHandCursor: ViewModifier {
    let isActive: Bool
    @State private var hasPushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(isActive ? .grabIdle : nil)
        } else {
            content
                .onHover { inside in setPushed(inside && isActive) }
                .onChange(of: isActive) { _, active in
                    if !active { setPushed(false) }
                }
                .onDisappear { setPushed(false) }
        }
    }

    private func setPushed(_ push: Bool) {
        guard push != hasPushed else { return }
        hasPushed = push
        if push { NSCursor.openHand.push() } else { NSCursor.pop() }
    }
}
