import Foundation
import XCTest
@testable import RailcastCore

final class TypingPolicyTests: XCTestCase {
    private func delay(after text: String) -> Duration? {
        var policy = TypingPolicy()
        let previous = String(text.dropLast())
        guard case .wait(let duration) = policy.decide(previous: previous, current: text, sinceLastEdit: nil) else {
            return nil
        }
        return duration
    }

    func testFewerThanTwoLettersIsSkipped() {
        XCTAssertNil(delay(after: "a"))
        XCTAssertNil(delay(after: "1 2"))
    }

    func testFinishedTextWaitsLessThanAWordInProgress() throws {
        let midWord = try XCTUnwrap(delay(after: "Hello wor"))
        let wordEnd = try XCTUnwrap(delay(after: "Hello world "))
        let comma = try XCTUnwrap(delay(after: "Hello world,"))
        let sentence = try XCTUnwrap(delay(after: "Hello world."))

        XCTAssertLessThan(sentence, wordEnd)
        XCTAssertEqual(wordEnd, comma)
        XCTAssertLessThan(wordEnd, midWord)
    }

    func testPasteIsImmediate() {
        var policy = TypingPolicy()
        XCTAssertEqual(
            policy.decide(previous: "", current: "Hello world", sinceLastEdit: nil),
            .wait(.zero)
        )
    }

    func testSlowTypistGetsLongerPause() {
        func pause(typingGap: Duration) -> TypingPolicy.Decision {
            var policy = TypingPolicy()
            for _ in 0..<5 {
                _ = policy.decide(previous: "hell", current: "hello", sinceLastEdit: typingGap)
            }
            return policy.decide(previous: "hell", current: "hello", sinceLastEdit: typingGap)
        }

        XCTAssertEqual(pause(typingGap: .milliseconds(50)), .wait(.milliseconds(500)))
        XCTAssertEqual(pause(typingGap: .milliseconds(200)), .wait(.milliseconds(800)))
        XCTAssertEqual(pause(typingGap: .milliseconds(900)), .wait(.milliseconds(1200)))
    }
}

@MainActor
final class TranslationSchedulerTests: XCTestCase {
    private actor Recorder {
        private(set) var requests: [String] = []

        func add(_ text: String) {
            requests.append(text)
        }
    }

    private struct StubTranslator: Translator {
        let recorder: Recorder

        func translate(_ text: String, target: String) async throws -> TranslationResult {
            await recorder.add(text)
            return TranslationResult(text: "[\(text)]", detectedSource: "en")
        }

        func warmUp() async {}
    }

    private let recorder = Recorder()

    private func makeScheduler() -> TranslationScheduler {
        TranslationScheduler(
            translator: StubTranslator(recorder: recorder),
            policy: TypingPolicy(
                sentenceEnd: .milliseconds(300),
                wordEnd: .milliseconds(300),
                midWordMinimum: .milliseconds(300),
                midWordMaximum: .milliseconds(300)
            )
        )
    }

    /// Feeds the text one character at a time, as a person typing would.
    private func type(_ text: String, into scheduler: TranslationScheduler) async throws {
        var typed = ""
        for character in text {
            typed.append(character)
            scheduler.edit(typed, target: "ru")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitForResult(_ scheduler: TranslationScheduler, _ expected: String) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if case .done(let result) = scheduler.state, result.text == expected { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out. State: \(scheduler.state)")
    }

    private var requests: [String] {
        get async { await recorder.requests }
    }

    func testTypingAWordSendsOneRequestForTheFinishedWord() async throws {
        let scheduler = makeScheduler()
        try await type("hello", into: scheduler)
        try await waitForResult(scheduler, "[hello]")
        let sent = await requests
        XCTAssertEqual(sent, ["hello"])
    }

    func testTypingASentenceSendsOnlyTheFinalText() async throws {
        let scheduler = makeScheduler()
        try await type("How are you today", into: scheduler)
        try await waitForResult(scheduler, "[How are you today]")
        let sent = await requests
        XCTAssertEqual(sent, ["How are you today"])
    }

    func testSingleLetterSendsNothing() async throws {
        let scheduler = makeScheduler()
        scheduler.edit("a", target: "ru")
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(scheduler.state, .idle)
        let sent = await requests
        XCTAssertEqual(sent, [])
    }

    func testTrailingSpaceDoesNotSendAgain() async throws {
        let scheduler = makeScheduler()
        scheduler.translateNow("hello", target: "ru")
        try await waitForResult(scheduler, "[hello]")

        scheduler.edit("hello ", target: "ru")
        try await Task.sleep(for: .milliseconds(450))
        try await waitForResult(scheduler, "[hello]")
        let sent = await requests
        XCTAssertEqual(sent, ["hello"])
    }

    func testBackspacingToTranslatedTextUsesCache() async throws {
        let scheduler = makeScheduler()
        scheduler.translateNow("hello", target: "ru")
        try await waitForResult(scheduler, "[hello]")
        scheduler.translateNow("hello world", target: "ru")
        try await waitForResult(scheduler, "[hello world]")

        scheduler.edit("hello", target: "ru")
        XCTAssertEqual(scheduler.state, .done(TranslationResult(text: "[hello]", detectedSource: "en")))
        let sent = await requests
        XCTAssertEqual(sent, ["hello", "hello world"])
    }

    func testDifferentTargetIsNotServedFromCache() async throws {
        let scheduler = makeScheduler()
        scheduler.translateNow("hello", target: "ru")
        try await waitForResult(scheduler, "[hello]")

        scheduler.translateNow("hello", target: "en")
        guard case .loading = scheduler.state else {
            return XCTFail("Expected a new request, got \(scheduler.state)")
        }
        try await waitForResult(scheduler, "[hello]")
        let sent = await requests
        XCTAssertEqual(sent, ["hello", "hello"])
    }

    func testTranslateNowSkipsTheTypingPause() async throws {
        let scheduler = makeScheduler()
        scheduler.edit("hello", target: "ru")
        XCTAssertTrue(scheduler.isWaiting)

        let start = ContinuousClock.now
        scheduler.translateNow("hello", target: "ru")
        try await waitForResult(scheduler, "[hello]")
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(250))
        let sent = await requests
        XCTAssertEqual(sent, ["hello"])
    }
}
