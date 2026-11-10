import Foundation

public struct TranslationResult: Sendable, Equatable {
    public let text: String
    public let detectedSource: String?

    public init(text: String, detectedSource: String?) {
        self.text = text
        self.detectedSource = detectedSource
    }
}

public enum TranslationError: Error, Equatable, LocalizedError {
    case rateLimited
    case badStatus(Int)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .rateLimited: "Google is rate-limiting requests. Try again in a minute."
        case .badStatus(let code): "Google returned HTTP \(code)."
        case .malformedResponse: "Google returned a response Railcast could not read."
        }
    }
}

public protocol Translator: Sendable {
    func translate(_ text: String, target: String) async throws -> TranslationResult
    /// Opens the connection ahead of the first request, so that request skips the TLS handshake.
    func warmUp() async
}

public struct LanguagePair: Sendable {
    public static let englishRussian = LanguagePair(first: "en", second: "ru")

    public let first: String
    public let second: String

    public func other(than language: String) -> String {
        language == first ? second : first
    }

    /// Cyrillic text goes to English. Everything else goes to Russian.
    public func target(for text: String) -> String {
        var cyrillic = 0
        var other = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            if (0x0400...0x052F).contains(scalar.value) {
                cyrillic += 1
            } else {
                other += 1
            }
        }
        return cyrillic > other ? "en" : "ru"
    }

    public static func displayName(of language: String) -> String {
        switch language {
        case "en": "English"
        case "ru": "Русский"
        default: language
        }
    }
}

/// Uses Google's free, unofficial endpoint, which needs no API key but has no guarantees.
public struct GoogleTranslator: Translator {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let host = URL(string: "https://translate.googleapis.com/")!
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        return URLSession(configuration: configuration)
    }()

    private let send: Send
    private let maxAttempts: Int
    private let retryDelay: Duration

    public init(
        maxAttempts: Int = 2,
        retryDelay: Duration = .milliseconds(250),
        send: Send? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.retryDelay = retryDelay
        self.send = send ?? { try await Self.session.data(for: $0) }
    }

    public func translate(_ text: String, target: String) async throws -> TranslationResult {
        let request = Self.makeRequest(text: text, target: target)
        var attempt = 1
        while true {
            do {
                return try await perform(request)
            } catch where attempt < maxAttempts && Self.isRetryable(error) {
                attempt += 1
                try await Task.sleep(for: retryDelay)
            }
        }
    }

    public func warmUp() async {
        var request = URLRequest(url: Self.host)
        request.httpMethod = "HEAD"
        _ = try? await send(request)
    }

    private func perform(_ request: URLRequest) async throws -> TranslationResult {
        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return try Self.parse(data)
        case 429: throw TranslationError.rateLimited
        default: throw TranslationError.badStatus(status)
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if case TranslationError.badStatus(let code) = error { return code >= 500 }
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        return false
    }

    static func makeRequest(text: String, target: String) -> URLRequest {
        var components = URLComponents(url: host, resolvingAgainstBaseURL: false)!
        components.path = "/translate_a/single"
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
        ]
        // POST because long text would not fit in a URL.
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        request.httpBody = Data("q=\(encoded)".utf8)
        return request
    }

    /// The response looks like `[[["Привет","Hello",...],...],null,"en",...]`.
    static func parse(_ data: Data) throws -> TranslationResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any]
        else { throw TranslationError.malformedResponse }

        let text = segments.compactMap { ($0 as? [Any])?.first as? String }.joined()
        guard !text.isEmpty else { throw TranslationError.malformedResponse }
        return TranslationResult(text: text, detectedSource: root.count > 2 ? root[2] as? String : nil)
    }
}
