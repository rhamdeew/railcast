import Foundation

public struct LauncherCommand: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable {
        case emoji, translate, toggleMenuBarIcon, quit
    }

    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let symbolName: String
    /// Hidden from the start screen, listed after apps, and matched only at the start of a word,
    /// so that typing an app's name and pressing Return cannot trigger it by accident.
    public let isSearchOnly: Bool
    let keywords: [String]

    public var id: String { title }

    private static let functions = [
        LauncherCommand(
            kind: .emoji,
            title: "Search Emoji & Symbols",
            subtitle: "Find and paste",
            symbolName: "face.smiling",
            isSearchOnly: false,
            keywords: ["emoji", "symbols", "эмодзи", "смайл", "символы"]
        ),
        LauncherCommand(
            kind: .translate,
            title: "Google Translate",
            subtitle: "English ⇄ Русский",
            symbolName: "character.bubble",
            isSearchOnly: false,
            keywords: ["translate", "google", "перевод", "переводчик"]
        ),
    ]

    private static let quit = LauncherCommand(
        kind: .quit,
        title: "Quit Railcast",
        subtitle: "Railcast",
        symbolName: "power",
        isSearchOnly: true,
        keywords: ["exit", "выход", "выйти", "закрыть"]
    )

    /// While the icon is hidden, its row stays on the start screen so it can always be brought back.
    private static func menuBarIconToggle(iconHidden: Bool) -> LauncherCommand {
        LauncherCommand(
            kind: .toggleMenuBarIcon,
            title: iconHidden ? "Show Menu Bar Icon" : "Hide Menu Bar Icon",
            subtitle: "Railcast",
            symbolName: "menubar.rectangle",
            isSearchOnly: !iconHidden,
            keywords: ["иконка", "значок", "скрыть", "показать", "трей"]
        )
    }

    /// Every word of the query must match.
    public static func matching(_ query: String, menuBarIconHidden: Bool = false) -> [LauncherCommand] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let all = functions + [menuBarIconToggle(iconHidden: menuBarIconHidden), quit]
        guard !tokens.isEmpty else { return all.filter { !$0.isSearchOnly } }

        return all.filter { command in
            let haystack = [command.title.lowercased()] + command.keywords
            return tokens.allSatisfy { token in
                haystack.contains { text in
                    guard command.isSearchOnly else { return text.contains(token) }
                    return text.split(whereSeparator: \.isWhitespace).contains { $0.hasPrefix(token) }
                }
            }
        }
    }
}
