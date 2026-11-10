import Foundation

public struct EmojiEntry: Sendable, Identifiable, Hashable {
    public let character: String
    public let name: String
    public let localizedName: String
    let searchNames: [String]
    let nameWords: [String]
    let keywords: [String]

    public var id: String { character }
}

public struct EmojiCatalog: Sendable {
    private struct Record: Decodable {
        let c: String
        let n: String
        let r: String
        let k: [String]
    }

    public private(set) var entries: [EmojiEntry]

    /// Returns a catalog with more search words, keyed by emoji. Unknown emoji are ignored.
    public func addingKeywords(_ extra: [String: [String]]) -> EmojiCatalog {
        var byKey: [String: [String]] = [:]
        for (character, terms) in extra {
            byKey[Self.withoutVariationSelector(character), default: []] += terms
        }

        var catalog = self
        catalog.entries = entries.map { entry in
            guard let terms = byKey[Self.withoutVariationSelector(entry.character)] else { return entry }
            return EmojiEntry(
                character: entry.character,
                name: entry.name,
                localizedName: entry.localizedName,
                searchNames: entry.searchNames,
                nameWords: entry.nameWords,
                keywords: Array(Set(entry.keywords + terms.map(Self.normalize)))
            )
        }
        return catalog
    }

    private static func withoutVariationSelector(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FE0F}", with: "")
    }

    public init(json: Data) throws {
        entries = try JSONDecoder().decode([Record].self, from: json).map { record in
            let names = [record.n, record.r].filter { !$0.isEmpty }.map(Self.normalize)
            return EmojiEntry(
                character: record.c,
                name: record.n,
                localizedName: record.r,
                searchNames: names,
                nameWords: names.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) },
                keywords: record.k.map(Self.normalize)
            )
        }
    }

    /// Every word of the query must match. Better matches come first, and ties keep catalog order.
    public func search(_ query: String) -> [EmojiEntry] {
        let tokens = Self.normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return entries }

        var matches: [(score: Int, order: Int, entry: EmojiEntry)] = []
        for (order, entry) in entries.enumerated() {
            var total = 0
            var matchedAll = true
            for token in tokens {
                let score = Self.score(token, entry)
                if score == 0 {
                    matchedAll = false
                    break
                }
                total += score
            }
            if matchedAll {
                matches.append((total, order, entry))
            }
        }
        matches.sort { ($0.score, $1.order) > ($1.score, $0.order) }
        return matches.map(\.entry)
    }

    /// Recently used entries first, then the rest of the catalog.
    public func browse(recents: [String]) -> [EmojiEntry] {
        let recentSet = Set(recents)
        let byCharacter = Dictionary(uniqueKeysWithValues: entries.map { ($0.character, $0) })
        return recents.compactMap { byCharacter[$0] } + entries.filter { !recentSet.contains($0.character) }
    }

    private static func score(_ token: String, _ entry: EmojiEntry) -> Int {
        if entry.searchNames.contains(token) { return 100 }
        if entry.searchNames.contains(where: { $0.hasPrefix(token) }) { return 80 }
        if entry.nameWords.contains(where: { $0.hasPrefix(token) }) { return 60 }
        if entry.keywords.contains(token) { return 50 }
        if entry.keywords.contains(where: { $0.hasPrefix(token) }) { return 30 }
        guard token.count >= 3 else { return 0 }
        let isContained = entry.searchNames.contains { $0.contains(token) }
            || entry.keywords.contains { $0.contains(token) }
        return isContained ? 10 : 0
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
    }
}
