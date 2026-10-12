import Foundation
import Testing

struct QuoteTests {
    @Test func parsesAZenQuotesBatch() {
        let longText = String(repeating: "a", count: Quote.maxLength + 1)
        let fitting = String(repeating: "b", count: Quote.maxLength)
        let json = """
            [
              {"q": "  Stay hungry.\\n", "a": " Someone ", "h": "<blockquote>Stay hungry.</blockquote>"},
              {"q": "", "a": "Nobody"},
              {"q": "Too many requests. Obtain an auth key for unlimited access.", "a": "zenquotes.io"},
              {"q": "\(longText)", "a": "Long"},
              {"q": "\(fitting)", "a": "Fits"}
            ]
            """
        #expect(
            Quote.parseZenQuotes(Data(json.utf8)) == [
                Quote(text: "Stay hungry.", author: "Someone"),
                Quote(text: fitting, author: "Fits"),
            ])
    }

    @Test func malformedRepliesGiveNoQuotes() {
        #expect(Quote.parseZenQuotes(Data("<html>rate limited</html>".utf8)).isEmpty)
        #expect(Quote.parseZenQuotes(Data(#"{"error": "x"}"#.utf8)).isEmpty)
    }

    @Test func builtInQuotesFitOneNotchLine() {
        #expect(!Quote.builtIn.isEmpty)
        for quote in Quote.builtIn {
            #expect(!quote.text.isEmpty && quote.text.count <= Quote.maxLength, "\(quote.text)")
            #expect(!quote.author.isEmpty)
        }
    }

    @Test func randomBuiltInNeverRepeatsTheCurrentQuote() {
        let current = Quote.builtIn[3]
        for _ in 0..<50 {
            #expect(Quote.randomBuiltIn(excluding: current) != current)
        }
    }
}
