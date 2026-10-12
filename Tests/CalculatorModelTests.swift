import Foundation
import Testing

struct CalculatorModelTests {
    /// Delayed work and copies the test runs and reads by hand.
    private final class Harness {
        var copies: [String] = []
        var pending: [() -> Void] = []
        lazy var model = CalculatorModel(
            locale: Locale(identifier: "en_US"),
            copyToPasteboard: { [unowned self] in self.copies.append($0) },
            schedule: { [unowned self] _, work in self.pending.append(work) })
    }

    @Test(arguments: [
        ("", "("),
        ("2+", "2+("),
        ("(5%", "(5%("),
        ("(2", "(2)"),
        ("((2)", "((2))"),
        ("(2 ", "(2 )"),
        ("2", "2("),
        ("(2)", "(2)("),
    ])
    func oneKeyForBothBrackets(_ expression: String, expected: String) {
        let model = Harness().model
        model.expression = expression
        model.insertBracket()
        #expect(model.expression == expected)
    }

    @Test func evaluatePutsTheAnswerBackInTheField() {
        let model = Harness().model
        model.expression = "1/4"
        #expect(model.preview?.formatted == "0.25")
        model.evaluate()
        #expect(model.expression == "0.25")
        #expect(model.history.map(\.expression) == ["1/4"])
        #expect(model.history.map(\.result) == ["0.25"])
    }

    @Test func historyKeepsTheLastTwenty() {
        let model = Harness().model
        for i in 1...25 {
            model.expression = "\(i)+1"
            model.evaluate()
        }
        #expect(model.history.count == CalculatorModel.historyLimit)
        #expect(model.history.first?.expression == "6+1")
        #expect(model.history.last?.result == "26")
    }

    @Test(arguments: ["", "  ", "hello", "2+*"])
    func evaluatingSomethingThatIsNotASumDoesNothing(_ expression: String) {
        let model = Harness().model
        model.expression = expression
        #expect(model.preview == nil)
        model.evaluate()
        #expect(model.expression == expression)
        #expect(model.history.isEmpty)
    }

    @Test func previewFollowsEveryEdit() {
        let model = Harness().model
        model.append("7")
        model.append("×")
        model.append("6")
        #expect(model.preview?.value == 42)
        model.backspace()
        #expect(model.preview == nil)
        model.clear()
        #expect(model.expression.isEmpty)
        #expect(model.preview == nil)
    }

    @Test func copyShowsCopiedUntilTheLatestCopyExpires() {
        let harness = Harness()
        let model = harness.model
        model.expression = "2+3"
        model.copyResult()
        #expect(harness.copies == ["5"])
        #expect(model.copied)
        model.copyResult()
        #expect(harness.pending.count == 2)
        // The first copy's reset must not cut the second one short.
        harness.pending[0]()
        #expect(model.copied)
        harness.pending[1]()
        #expect(!model.copied)
    }

    @Test func editingClearsCopied() {
        let harness = Harness()
        let model = harness.model
        model.expression = "2+3"
        model.copyResult()
        model.append("0")
        #expect(!model.copied)
    }

    @Test func nothingToCopyWithoutAResult() {
        let harness = Harness()
        harness.model.expression = "2+"
        harness.model.copyResult()
        #expect(harness.copies.isEmpty)
        #expect(!harness.model.copied)
        #expect(harness.pending.isEmpty)
    }
}
