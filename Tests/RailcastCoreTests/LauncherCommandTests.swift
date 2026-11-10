import XCTest
@testable import RailcastCore

final class LauncherCommandTests: XCTestCase {
    private func kinds(_ query: String) -> [LauncherCommand.Kind] {
        LauncherCommand.matching(query).map(\.kind)
    }

    func testEmptyQueryListsEveryCommandInOrder() {
        XCTAssertEqual(kinds(""), [.emoji, .translate])
        XCTAssertEqual(kinds("   "), [.emoji, .translate])
    }

    func testMatchesTitleAndIsCaseInsensitive() {
        XCTAssertEqual(kinds("EMOJI"), [.emoji])
        XCTAssertEqual(kinds("goo trans"), [.translate])
    }

    func testMatchesRussianKeywords() {
        XCTAssertEqual(kinds("перевод"), [.translate])
        XCTAssertEqual(kinds("эмодзи"), [.emoji])
    }

    func testNoMatchReturnsNothing() {
        XCTAssertEqual(kinds("calendar"), [])
    }
}
