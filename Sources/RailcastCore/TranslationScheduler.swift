import Foundation
import Observation

/// Decides how long to wait after an edit before the text is worth translating.
public struct TypingPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case skip
        case wait(Duration)
    }

    private static let minimumLetters = 2
    private static let pasteThreshold = 4
    private static let pauseMultiplier = 4
    private static let maxTypingGap = Duration.seconds(2)
    private static let maxSamples = 8

    private let sentenceEnd: Duration
    private let wordEnd: Duration
    private let midWordMinimum: Duration
    private let midWordMaximum: Duration
    private var gaps: [Duration] = []

    public init(
        sentenceEnd: Duration = .milliseconds(150),
        wordEnd: Duration = .milliseconds(300),
        midWordMinimum: Duration = .milliseconds(500),
        midWordMaximum: Duration = .milliseconds(1200)
    ) {
        self.sentenceEnd = sentenceEnd
        self.wordEnd = wordEnd
        self.midWordMinimum = midWordMinimum
        self.midWordMaximum = midWordMaximum
    }

    public mutating func decide(previous: String, current: String, sinceLastEdit: Duration?) -> Decision {
        if let gap = sinceLastEdit, gap < Self.maxTypingGap {
            gaps = (gaps + [gap]).suffix(Self.maxSamples)
        }

        guard current.unicodeScalars.filter(\.properties.isAlphabetic).count >= Self.minimumLetters else {
            return .skip
        }
        // Several characters arriving in one edit means a paste, so the text is already complete.
        if current.count - previous.count >= Self.pasteThreshold {
            return .wait(.zero)
        }

        switch current.last {
        case ".", "?", "!", "…": return .wait(sentenceEnd)
        case ",", ";", ":": return .wait(wordEnd)
        case let last? where last.isWhitespace: return .wait(wordEnd)
        default: return .wait(midWordPause)
        }
    }

    /// A slow typist pauses longer between letters, so "stopped typing" must mean a longer silence.
    private var midWordPause: Duration {
        guard !gaps.isEmpty else { return midWordMinimum }
        let median = gaps.sorted()[gaps.count / 2]
        return min(max(median * Self.pauseMultiplier, midWordMinimum), midWordMaximum)
    }
}

public enum TranslationState: Equatable, Sendable {
    case idle
    case loading(previous: String?)
    case done(TranslationResult)
    case failed(String)
}

/// Turns a stream of edits into as few translation requests as possible.
@MainActor
@Observable
public final class TranslationScheduler {
    private struct Request: Hashable {
        let text: String
        let target: String
    }

    private static let maxCachedResults = 128

    public private(set) var state = TranslationState.idle

    @ObservationIgnored private let translator: any Translator
    @ObservationIgnored private var policy: TypingPolicy
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var inFlight: Request?
    @ObservationIgnored private var cache: [Request: TranslationResult] = [:]
    @ObservationIgnored private var lastText = ""
    @ObservationIgnored private var lastEdit: ContinuousClock.Instant?

    public init(translator: any Translator, policy: TypingPolicy = TypingPolicy()) {
        self.translator = translator
        self.policy = policy
    }

    /// True while a request is held back waiting for typing to stop.
    public var isWaiting: Bool {
        task != nil && inFlight == nil
    }

    /// Call for every change the user makes to the text.
    public func edit(_ text: String, target: String) {
        let now = ContinuousClock.now
        let gap = lastEdit.map { now - $0 }
        lastEdit = now

        let decision = policy.decide(previous: lastText, current: text, sinceLastEdit: gap)
        lastText = text
        switch decision {
        case .skip:
            cancel()
            state = .idle
        case .wait(let delay):
            schedule(text, target: target, delay: delay)
        }
    }

    /// Skips the typing pause. Use when the user explicitly asks for a translation.
    public func translateNow(_ text: String, target: String) {
        lastText = text
        schedule(text, target: target, delay: .zero)
    }

    public func cancel() {
        task?.cancel()
        task = nil
        inFlight = nil
    }

    private func schedule(_ text: String, target: String, delay: Duration) {
        let request = Request(text: text.trimmingCharacters(in: .whitespacesAndNewlines), target: target)
        guard !request.text.isEmpty else {
            cancel()
            state = .idle
            return
        }
        guard request != inFlight else { return }
        cancel()

        if let cached = cache[request] {
            state = .done(cached)
            return
        }

        state = .loading(previous: visibleText)
        task = Task { [translator] in
            do {
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
                try Task.checkCancellation()
                inFlight = request
                let result = try await translator.translate(request.text, target: request.target)
                try Task.checkCancellation()
                store(result, for: request)
                finish(with: .done(result))
            } catch is CancellationError {
                // A newer edit replaced this request.
            } catch let error as URLError where error.code == .cancelled {
                // Same, surfaced by URLSession.
            } catch {
                finish(with: .failed(error.localizedDescription))
            }
        }
    }

    private func finish(with newState: TranslationState) {
        task = nil
        inFlight = nil
        state = newState
    }

    private func store(_ result: TranslationResult, for request: Request) {
        if cache.count >= Self.maxCachedResults {
            cache.removeAll()
        }
        cache[request] = result
    }

    private var visibleText: String? {
        switch state {
        case .done(let result): result.text
        case .loading(let previous): previous
        case .idle, .failed: nil
        }
    }
}
