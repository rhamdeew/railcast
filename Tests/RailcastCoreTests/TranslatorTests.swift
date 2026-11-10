import Foundation
import XCTest
@testable import RailcastCore

final class TranslatorTests: XCTestCase {
    private actor Responses {
        private var queue: [Result<(Data, Int), Error>]
        private(set) var callCount = 0

        init(_ queue: [Result<(Data, Int), Error>]) {
            self.queue = queue
        }

        func next() -> Result<(Data, Int), Error> {
            callCount += 1
            return queue.removeFirst()
        }
    }

    private let validBody = Data(#"[[["Привет","Hello",null,null,10]],null,"en"]"#.utf8)

    private func translator(_ responses: Responses) -> GoogleTranslator {
        GoogleTranslator(maxAttempts: 2, retryDelay: .zero) { request in
            let (data, status) = try await responses.next().get()
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    func testParseJoinsSegmentsAndIgnoresTransliteration() throws {
        let body = Data(#"[[["Один. ","One. "],["Два.","Two."],[null,null,"Odin. Dva."]],null,"en"]"#.utf8)
        XCTAssertEqual(
            try GoogleTranslator.parse(body),
            TranslationResult(text: "Один. Два.", detectedSource: "en")
        )
    }

    func testParseRejectsUnexpectedBody() {
        XCTAssertThrowsError(try GoogleTranslator.parse(Data("<html>".utf8))) {
            XCTAssertEqual($0 as? TranslationError, .malformedResponse)
        }
    }

    func testRequestEncodesReservedCharactersInBody() throws {
        let request = GoogleTranslator.makeRequest(text: "a&b=c d", target: "ru")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "q=a%26b%3Dc%20d")
        XCTAssertTrue(try XCTUnwrap(request.url?.query).contains("tl=ru"))
    }

    func testRetriesServerErrorOnce() async throws {
        let responses = Responses([.success((Data(), 503)), .success((validBody, 200))])
        let result = try await translator(responses).translate("Hello", target: "ru")
        XCTAssertEqual(result.text, "Привет")
        let calls = await responses.callCount
        XCTAssertEqual(calls, 2)
    }

    func testRetriesNetworkFailureOnce() async throws {
        let responses = Responses([.failure(URLError(.timedOut)), .success((validBody, 200))])
        let result = try await translator(responses).translate("Hello", target: "ru")
        XCTAssertEqual(result.text, "Привет")
    }

    func testDoesNotRetryRateLimit() async {
        let responses = Responses([.success((Data(), 429)), .success((validBody, 200))])
        do {
            _ = try await translator(responses).translate("Hello", target: "ru")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? TranslationError, .rateLimited)
        }
        let calls = await responses.callCount
        XCTAssertEqual(calls, 1)
    }

    func testGivesUpAfterMaxAttempts() async {
        let responses = Responses([.success((Data(), 500)), .success((Data(), 502))])
        do {
            _ = try await translator(responses).translate("Hello", target: "ru")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? TranslationError, .badStatus(502))
        }
    }

    func testTargetLanguageFollowsScript() {
        let pair = LanguagePair.englishRussian
        XCTAssertEqual(pair.target(for: "Hello world"), "ru")
        XCTAssertEqual(pair.target(for: "Привет, мир"), "en")
        XCTAssertEqual(pair.target(for: "Я люблю Swift"), "en")
        XCTAssertEqual(pair.other(than: "ru"), "en")
    }
}
