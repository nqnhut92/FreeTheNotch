import AppKit

/// The Calculator page's state. Shared, so the sum is still there when you
/// come back to the page. Parsing is Vorssaint's CommandBarMath.
final class CalculatorModel: ObservableObject {
    static let shared = CalculatorModel()

    struct Entry: Identifiable {
        let id = UUID()
        let expression: String
        let result: String
        /// The answer as input, to put back in the field.
        let reusable: String
    }

    static let historyLimit = 20
    /// How long the result reads "Copied".
    static let copiedDuration: TimeInterval = 1.2

    @Published var expression = "" {
        didSet {
            guard expression != oldValue else { return }
            preview = evaluateExpression()
            copied = false
        }
    }
    @Published private(set) var history: [Entry] = []
    @Published private(set) var copied = false

    /// The current expression's value, or nil while it is empty or not a
    /// sum. Worked out once per edit rather than on every read.
    private(set) var preview: CommandBarMath.Result?

    private let locale: Locale
    private let copyToPasteboard: (String) -> Void
    private let schedule: MainScheduler
    /// Bumped by every copy, so an earlier copy's reset leaves a later
    /// "Copied" on screen for its full time.
    private var copyGeneration = 0

    init(
        locale: Locale = .current,
        copyToPasteboard: @escaping (String) -> Void = CalculatorModel.writeToGeneralPasteboard,
        schedule: @escaping MainScheduler = MainQueue.after
    ) {
        self.locale = locale
        self.copyToPasteboard = copyToPasteboard
        self.schedule = schedule
    }

    private var decimalSeparator: String { locale.decimalSeparator ?? "." }

    func append(_ text: String) { expression += text }

    func backspace() {
        if !expression.isEmpty { expression.removeLast() }
    }

    func clear() { expression = "" }

    /// One key for both brackets: opens after an operator or "(", closes
    /// when a bracket is still open.
    func insertBracket() {
        let open = expression.filter { $0 == "(" }.count
        let close = expression.filter { $0 == ")" }.count
        let opensHere = expression.trimmingCharacters(in: .whitespaces).last.map { "+−-×*÷/^(%".contains($0) } ?? true
        expression += (open > close && !opensHere) ? ")" : "("
    }

    /// Moves a valid sum into the history and puts its answer in the field.
    /// Does nothing while the expression is not a sum.
    func evaluate() {
        guard let result = preview else { return }
        let entry = Entry(
            expression: expression, result: result.formatted,
            reusable: CommandBarMath.reusableExpression(for: result, decimalSeparator: decimalSeparator))
        history.append(entry)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        expression = entry.reusable
    }

    func copyResult() {
        guard let result = preview else { return }
        copyToPasteboard(result.formatted)
        copied = true
        copyGeneration &+= 1
        let generation = copyGeneration
        schedule(Self.copiedDuration) { [weak self] in
            guard let self, self.copyGeneration == generation else { return }
            self.copied = false
        }
    }

    private func evaluateExpression() -> CommandBarMath.Result? {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return CommandBarMath.evaluate(
            trimmed, decimalSeparator: decimalSeparator,
            groupingSeparator: locale.groupingSeparator ?? ",", locale: locale)
    }

    static func writeToGeneralPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
