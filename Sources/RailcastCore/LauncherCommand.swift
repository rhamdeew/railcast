import Foundation

public struct LauncherCommand: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable {
        case emoji, translate
    }

    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let symbolName: String
    let keywords: [String]

    public var id: String { title }

    public static let all = [
        LauncherCommand(
            kind: .emoji,
            title: "Search Emoji & Symbols",
            subtitle: "Find and paste",
            symbolName: "face.smiling",
            keywords: ["emoji", "symbols", "эмодзи", "смайл", "символы"]
        ),
        LauncherCommand(
            kind: .translate,
            title: "Google Translate",
            subtitle: "English ⇄ Русский",
            symbolName: "character.bubble",
            keywords: ["translate", "google", "перевод", "переводчик"]
        ),
    ]

    /// Every word of the query must appear in the title or in a keyword.
    public static func matching(_ query: String) -> [LauncherCommand] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return all.filter { command in
            let haystack = [command.title.lowercased()] + command.keywords
            return tokens.allSatisfy { token in haystack.contains { $0.contains(token) } }
        }
    }
}
