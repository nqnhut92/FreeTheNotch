import SwiftUI

/// Calculator page. Parsing is Vorssaint's CommandBarMath (ported verbatim);
/// the keypad follows the iOS Calculator. Click the display to type with the
/// keyboard: Return evaluates, Esc clears. Click the result to copy it.
/// The field is not focused on appear: that would make the notch panel key
/// as soon as the page opens.
struct CalculatorTabView: View {
    @ObservedObject private var model = CalculatorModel.shared
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            displayPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            keypad
                .frame(width: 262)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .foregroundStyle(.white)
    }

    // MARK: Display

    private var displayPane: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // History, oldest at the top; click a line to reuse its answer.
            VStack(alignment: .trailing, spacing: 3) {
                ForEach(model.history.suffix(3)) { entry in
                    Button {
                        model.expression = entry.reusable
                    } label: {
                        HStack(spacing: 6) {
                            Text(entry.expression)
                                .foregroundStyle(Color(white: 0.45))
                                .lineLimit(1)
                                .truncationMode(.head)
                            Text("= " + entry.result)
                                .foregroundStyle(Color(white: 0.7))
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, design: .rounded))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Use this answer")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            TextField("0", text: $model.expression)
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .light, design: .rounded))
                .multilineTextAlignment(.trailing)
                .focused($fieldFocused)
                .onSubmit { model.evaluate() }
                .onExitCommand { model.clear() }

            Button(action: model.copyResult) {
                HStack(spacing: 5) {
                    if model.copied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text("Copied")
                    } else if let preview = model.preview {
                        Text("= " + preview.formatted)
                    } else {
                        Text(model.expression.isEmpty ? " " : "…")
                    }
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(model.copied ? Color.green : Color(white: 0.6))
                .lineLimit(1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.preview == nil)
            .help("Copy result")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NotchCardBackground())
    }

    // MARK: Keypad

    private static let rows: [[CalculatorKey]] = [
        [.clear, .backspace, .percent, .divide],
        [.digit("7"), .digit("8"), .digit("9"), .multiply],
        [.digit("4"), .digit("5"), .digit("6"), .subtract],
        [.digit("1"), .digit("2"), .digit("3"), .add],
        [.brackets, .digit("0"), .decimalSeparator, .equals],
    ]

    private var keypad: some View {
        VStack(spacing: 6) {
            ForEach(Self.rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(Self.rows[r], id: \.label) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    private func keyButton(_ key: CalculatorKey) -> some View {
        let style = key.style
        return Button {
            press(key)
        } label: {
            Text(key.label)
                .font(
                    .system(
                        size: style == .op || style == .equals ? 18 : 15,
                        weight: style == .digit ? .medium : .semibold,
                        design: .rounded)
                )
                .foregroundStyle(style == .function ? Color.black : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().fill(fill(for: style)))
                .contentShape(Capsule())
        }
        .buttonStyle(CalculatorKeyStyle())
    }

    private func fill(for style: CalculatorKey.Style) -> Color {
        switch style {
        case .digit: return Color.white.opacity(0.14)
        case .function: return Color(white: 0.72)
        case .op, .equals: return Color.orange
        }
    }

    private func press(_ key: CalculatorKey) {
        switch key {
        case .clear: model.clear()
        case .backspace: model.backspace()
        case .equals: model.evaluate()
        case .brackets: model.insertBracket()
        default: model.append(key.label)
        }
    }
}

/// A keypad key. Digits, operators, % and the decimal separator type their
/// label; the others act on the model.
private enum CalculatorKey {
    case digit(String)
    case decimalSeparator
    case brackets
    case percent
    case add, subtract, multiply, divide
    case equals
    case clear
    case backspace

    enum Style { case digit, function, op, equals }

    var label: String {
        switch self {
        case .digit(let digit): return digit
        case .decimalSeparator: return Locale.current.decimalSeparator ?? "."
        case .brackets: return "( )"
        case .percent: return "%"
        case .add: return "+"
        case .subtract: return "−"
        case .multiply: return "×"
        case .divide: return "÷"
        case .equals: return "="
        case .clear: return "AC"
        case .backspace: return "⌫"
        }
    }

    var style: Style {
        switch self {
        case .digit, .decimalSeparator, .brackets: return .digit
        case .percent, .clear, .backspace: return .function
        case .add, .subtract, .multiply, .divide: return .op
        case .equals: return .equals
        }
    }
}

/// Dims a key while it is held, like the iOS Calculator.
private struct CalculatorKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.15 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
