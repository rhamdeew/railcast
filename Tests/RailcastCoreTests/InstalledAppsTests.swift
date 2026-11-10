import Foundation
import XCTest
@testable import RailcastCore

final class InstalledAppsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func makeApp(_ relativePath: String) throws {
        let contents = root.appendingPathComponent(relativePath).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data().write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func scannedNames() -> [String] {
        AppScanner.scan(roots: [root], extraApps: []).map(\.name)
    }

    func testFindsAppsInSubfoldersAndSortsThem() throws {
        try makeApp("Zebra.app")
        try makeApp("Utilities/Alpha.app")
        try makeApp("Vendor/Suite/Middle.app")
        XCTAssertEqual(scannedNames(), ["Alpha", "Middle", "Zebra"])
    }

    func testIgnoresEverythingThatIsNotAnApp() throws {
        try makeApp("Real.app")
        try Data().write(to: root.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Empty.app"),
            withIntermediateDirectories: true
        )
        XCTAssertEqual(scannedNames(), ["Real"])
    }

    func testDoesNotListHelperAppsInsideBundles() throws {
        try makeApp("Outer.app")
        try makeApp("Outer.app/Contents/Helpers/Inner.app")
        XCTAssertEqual(scannedNames(), ["Outer"])
    }

    func testStopsAtMaxFolderDepth() throws {
        try makeApp("a/b/c/TooDeep.app")
        XCTAssertEqual(scannedNames(), [])
    }

    func testSymlinkToAnAppIsListedOnce() throws {
        try makeApp("Target.app")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Link.app"),
            withDestinationURL: root.appendingPathComponent("Target.app")
        )
        XCTAssertEqual(AppScanner.scan(roots: [root], extraApps: []).count, 1)
    }

    func testFindsRealSystemAppsQuickly() {
        let start = ContinuousClock.now
        let apps = AppScanner.scan()
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
        XCTAssertTrue(apps.contains { $0.name == "Finder" })
        XCTAssertTrue(apps.contains { $0.name == "Calculator" })
        XCTAssertEqual(Set(apps.map(\.path)).count, apps.count)
    }

    private let sample = [
        InstalledApp(name: "Visual Studio Code", path: "/A/Visual Studio Code.app"),
        InstalledApp(name: "Safari", path: "/A/Safari.app"),
        InstalledApp(name: "Code Runner", path: "/A/Code Runner.app"),
        InstalledApp(name: "Decoder", path: "/A/Decoder.app"),
    ]

    private func search(_ query: String) -> [String] {
        AppSearch.search(sample, query: query).map(\.name)
    }

    func testPrefixBeatsWordBeatsSubstring() {
        XCTAssertEqual(search("code"), ["Code Runner", "Visual Studio Code", "Decoder"])
    }

    func testEveryWordMustMatch() {
        XCTAssertEqual(search("vis code"), ["Visual Studio Code"])
        XCTAssertEqual(search("safari code"), [])
    }

    func testEmptyQueryShowsNoApps() {
        XCTAssertEqual(search("  "), [])
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(search("SAF"), ["Safari"])
    }
}
