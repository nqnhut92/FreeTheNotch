import Foundation
import Testing

struct CommandBarMathTests {
    private static let english = Locale(identifier: "en_US")

    private func evaluate(_ input: String) -> CommandBarMath.Result? {
        CommandBarMath.evaluate(input, decimalSeparator: ".", groupingSeparator: ",", locale: Self.english)
    }

    @Test(arguments: [
        ("2+3*4", 14.0),
        ("(2+3)*4", 20),
        ("10 - 4 - 3", 3),
        ("2^3^2", 512),  // right-associative: 2^(3^2)
        ("-2^2", -4),  // the sign applies to the whole power
        ("8 / 4 / 2", 1),
        ("0.1+0.2", 0.3),
        ("50% of 200", 100),
        ("200+10%", 220),  // relative percent, calculator style
        ("200-10%", 180),
        ("2(3+4)", 14),  // implicit product
        ("sqrt(16)", 4),
        ("3x4", 12),
        ("6 \u{00F7} 3 \u{00D7} 2", 4),
        ("3*4 =", 12),
    ])
    func evaluates(_ input: String, expected: Double) throws {
        let result = try #require(evaluate(input))
        #expect(abs(result.value - expected) < 1e-9)
        #expect(result.closingBrackets.isEmpty)
    }

    @Test func formatsWithoutBinaryNoise() throws {
        #expect(try #require(evaluate("0.1+0.2")).formatted == "0.3")
        #expect(try #require(evaluate("1000*1000")).formatted == "1,000,000")
    }

    @Test(arguments: [
        ("(1+2", 3.0, ")"),
        ("[2*(3+4", 14, ")]"),
        ("sqrt(9", 3, ")"),
    ])
    func suppliesMissingClosingBrackets(_ input: String, expected: Double, closers: String) throws {
        let result = try #require(evaluate(input))
        #expect(result.value == expected)
        #expect(result.closingBrackets == closers)
    }

    @Test(arguments: [
        "1/0",
        "sqrt(-1)",
        "hello",
        "42",  // a lone number is not a calculation
        "2+",
        "(1+2]",
        "1+2)",
        "x = 2+3",
        "2026-07-27",
        "8/4/2",  // reads as a date, not as a sum
        "",
    ])
    func rejects(_ input: String) {
        #expect(evaluate(input) == nil)
    }

    @Test func readsVietnameseSeparators() throws {
        let result = try #require(
            CommandBarMath.evaluate(
                "1.000,5+1", decimalSeparator: ",", groupingSeparator: ".",
                locale: Locale(identifier: "vi_VN")))
        #expect(result.value == 1001.5)
        #expect(result.formatted == "1.001,5")
    }

    @Test(arguments: [
        ("2026-07-27", true),
        ("27/07/2026", true),
        ("10:30", true),
        ("10 : 30", true),
        ("100 - 20 - 30", false),
        ("10-3", false),
        ("1/2", false),
        ("2+2", false),
    ])
    func recognizesDatesAndTimes(_ input: String, expected: Bool) {
        #expect(CommandBarMath.looksLikeDateOrTime(input) == expected)
    }

    @Test func reusableExpressionBracketsNegativeValues() throws {
        let result = try #require(evaluate("2-5"))
        #expect(CommandBarMath.reusableExpression(for: result, decimalSeparator: ",") == "(-3)")
        let decimal = try #require(evaluate("1/4"))
        #expect(CommandBarMath.reusableExpression(for: decimal, decimalSeparator: ",") == "0,25")
    }
}
