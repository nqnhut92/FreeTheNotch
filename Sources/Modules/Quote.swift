// Quote of the Day model: no reference equivalent. Online quotes come from
// the ZenQuotes API (zenquotes.io).

import Foundation

struct Quote: Codable, Equatable {
    let text: String
    let author: String

    /// One line in the 720 pt notch.
    static let maxLength = 110

    /// A built-in quote other than `current`, so a click always changes it.
    static func randomBuiltIn(excluding current: Quote?) -> Quote {
        builtIn.filter { $0 != current }.randomElement() ?? builtIn[0]
    }

    /// A ZenQuotes `/api/quotes` reply (`[{"q": text, "a": author}]`) as
    /// quotes that fit the notch. Skips empty and long ones and the API's own
    /// "too many requests" notice, which it sends as a quote by
    /// "zenquotes.io".
    static func parseZenQuotes(_ data: Data) -> [Quote] {
        struct Item: Decodable {
            let q: String
            let a: String
        }
        let items = (try? JSONDecoder().decode([Item].self, from: data)) ?? []
        return
            items
            .map {
                Quote(
                    text: $0.q.trimmingCharacters(in: .whitespacesAndNewlines),
                    author: $0.a.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .filter { !$0.text.isEmpty && $0.text.count <= maxLength && $0.author != "zenquotes.io" }
    }
}

/// Where quotes come from.
enum QuoteSource: String, CaseIterable {
    case online, builtIn

    var title: String { self == .online ? "Online (ZenQuotes)" : "Built-in" }
}

extension Quote {
    /// Offline fallback and the "Built-in" source. Old, public-domain authors
    /// and proverbs only, so nothing copyrighted is bundled.
    static let builtIn: [Quote] = [
        Quote(text: "We suffer more often in imagination than in reality.", author: "Seneca"),
        Quote(text: "Waste no more time arguing what a good man should be. Be one.", author: "Marcus Aurelius"),
        Quote(text: "It is not that we have a short time to live, but that we waste a lot of it.", author: "Seneca"),
        Quote(text: "No man is free who is not master of himself.", author: "Epictetus"),
        Quote(text: "First say to yourself what you would be; and then do what you have to do.", author: "Epictetus"),
        Quote(text: "A journey of a thousand miles begins with a single step.", author: "Lao Tzu"),
        Quote(text: "Well begun is half done.", author: "Aristotle"),
        Quote(text: "He who has a why to live can bear almost any how.", author: "Friedrich Nietzsche"),
        Quote(text: "Do what you can, with what you have, where you are.", author: "Theodore Roosevelt"),
        Quote(text: "The best way out is always through.", author: "Robert Frost"),
        Quote(text: "Fall seven times, stand up eight.", author: "Japanese proverb"),
        Quote(text: "This too shall pass.", author: "Persian proverb"),
        Quote(
            text: "Our greatest glory is not in never falling, but in rising every time we fall.",
            author: "Oliver Goldsmith"),
        Quote(text: "Nothing is impossible to a willing heart.", author: "John Heywood"),
        Quote(text: "Hope is the thing with feathers that perches in the soul.", author: "Emily Dickinson"),
        Quote(text: "Difficulties strengthen the mind, as labour does the body.", author: "Seneca"),
        Quote(text: "Begin at once to live, and count each separate day as a separate life.", author: "Seneca"),
        Quote(text: "Very little is needed to make a happy life.", author: "Marcus Aurelius"),
        Quote(text: "Rest is not idleness.", author: "John Lubbock"),
        Quote(text: "Little by little, one travels far.", author: "Spanish proverb"),
        Quote(text: "Be kind, for everyone you meet is fighting a hard battle.", author: "Ian Maclaren"),
        Quote(text: "Out of difficulties grow miracles.", author: "Jean de La Bruy\u{00E8}re"),
        Quote(text: "Nothing great was ever achieved without enthusiasm.", author: "Ralph Waldo Emerson"),
        Quote(text: "Adopt the pace of nature: her secret is patience.", author: "Ralph Waldo Emerson"),
        Quote(
            text: "Write it on your heart that every day is the best day in the year.", author: "Ralph Waldo Emerson"),
        Quote(text: "Happiness depends upon ourselves.", author: "Aristotle"),
        Quote(text: "Smooth seas do not make skillful sailors.", author: "African proverb"),
        Quote(text: "The best time to plant a tree was 20 years ago. The second best time is now.", author: "Proverb"),
        Quote(text: "Genius is one percent inspiration and ninety-nine percent perspiration.", author: "Thomas Edison"),
        Quote(text: "Energy and persistence conquer all things.", author: "Benjamin Franklin"),
        Quote(text: "Well done is better than well said.", author: "Benjamin Franklin"),
        Quote(text: "Lost time is never found again.", author: "Benjamin Franklin"),
        Quote(text: "Keep calm and carry on.", author: "1939 British poster"),
    ]
}
