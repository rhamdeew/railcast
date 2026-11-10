import Foundation
import XCTest
@testable import RailcastCore

final class EmojiCatalogTests: XCTestCase {
    private let sample = Data("""
    [
      {"c":"😀","n":"grinning face","r":"широко улыбается","k":["face","happy","smile","счастье"]},
      {"c":"🙂","n":"slightly smiling face","r":"легкая улыбка","k":["face","smile"]},
      {"c":"🦔","n":"hedgehog","r":"ёж","k":["spiny"]},
      {"c":"→","n":"right-pointing arrow","r":"стрелка вправо","k":["arrow","right"]}
    ]
    """.utf8)

    private func catalog() throws -> EmojiCatalog {
        try EmojiCatalog(json: sample)
    }

    private func search(_ query: String) throws -> [String] {
        try catalog().search(query).map(\.character)
    }

    func testNameWordRanksAboveKeyword() throws {
        XCTAssertEqual(try search("smil"), ["🙂", "😀"])
    }

    func testEveryWordMustMatch() throws {
        XCTAssertEqual(try search("happy face"), ["😀"])
        XCTAssertEqual(try search("happy arrow"), [])
    }

    func testRussianQueries() throws {
        XCTAssertEqual(try search("счастье"), ["😀"])
        XCTAssertEqual(try search("стрелка"), ["→"])
    }

    func testYoAndYeAreEquivalent() throws {
        XCTAssertEqual(try search("еж"), ["🦔"])
        XCTAssertEqual(try search("ёж"), ["🦔"])
    }

    func testShortQueriesDoNotMatchInsideWords() throws {
        XCTAssertEqual(try search("ge"), [])
    }

    func testEmptyQueryReturnsEverything() throws {
        XCTAssertEqual(try search("  ").count, 4)
    }

    func testBrowsePutsRecentsFirstWithoutDuplicates() throws {
        let characters = try catalog().browse(recents: ["→", "🦔"]).map(\.character)
        XCTAssertEqual(characters, ["→", "🦔", "😀", "🙂"])
    }

    func testBundledDataLoadsAndFindsCommonEntries() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/emoji.json")
        let catalog = try EmojiCatalog(json: Data(contentsOf: url))

        XCTAssertGreaterThan(catalog.entries.count, 2000)
        XCTAssertEqual(Set(catalog.entries.map(\.character)).count, catalog.entries.count)
        XCTAssertEqual(catalog.search("grinning face").first?.character, "😀")
        XCTAssertTrue(catalog.search("euro").contains { $0.character == "€" })
        XCTAssertTrue(catalog.search("флаг россия").contains { $0.character == "🇷🇺" })
    }
}
