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

    func testSearchOnlyCommandsAreFoundByWord() {
        XCTAssertEqual(kinds("quit"), [.quit])
        XCTAssertEqual(kinds("выход"), [.quit])
        XCTAssertEqual(kinds("hide menu"), [.toggleMenuBarIcon])
        XCTAssertEqual(kinds("скрыть"), [.toggleMenuBarIcon])
    }

    func testSearchOnlyCommandsDoNotMatchInsideWords() {
        XCTAssertFalse(kinds("ca").contains(.quit))
        XCTAssertFalse(kinds("ar").contains(.toggleMenuBarIcon))
    }

    func testHiddenIconKeepsItsRowOnTheStartScreen() throws {
        let commands = LauncherCommand.matching("", menuBarIconHidden: true)
        XCTAssertEqual(commands.map(\.kind), [.emoji, .translate, .toggleMenuBarIcon])
        XCTAssertEqual(commands.last?.title, "Show Menu Bar Icon")
        XCTAssertEqual(commands.last?.isSearchOnly, false)
    }

    func testNoMatchReturnsNothing() {
        XCTAssertEqual(kinds("calendar"), [])
    }
}
