import AppKit
import Observation
import RailcastCore

enum OutputAction {
    case copy
    case paste
}

/// Key codes are physical positions, so shortcuts keep working on the Russian layout.
enum LauncherKey {
    case escape, tab, left, right, up, down, swapLanguages
    case enter(command: Bool)

    init?(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, modifiers) {
        case (53, _): self = .escape
        case (48, _): self = .tab
        case (36, .command), (76, .command): self = .enter(command: true)
        case (36, []), (76, []): self = .enter(command: false)
        case (37, .command): self = .swapLanguages
        case (123, []): self = .left
        case (124, []): self = .right
        case (125, []): self = .down
        case (126, []): self = .up
        default: return nil
        }
    }
}

enum HomeItem: Identifiable {
    case command(LauncherCommand)
    case app(InstalledApp)

    var id: String {
        switch self {
        case .command(let command): "command:\(command.id)"
        case .app(let app): "app:\(app.id)"
        }
    }
}

@MainActor
@Observable
final class LauncherModel {
    enum Mode {
        case home, emoji, translate
    }

    static let gridColumns = 9
    private static let maxRecents = gridColumns * 2
    private static let recentsKey = "recentEmoji"

    var mode = Mode.home {
        didSet {
            guard mode != oldValue else { return }
            refreshNow()
            warmUpIfTranslating()
        }
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            targetOverride = nil
            switch mode {
            case .home: refreshHome()
            case .emoji: refreshNow()
            case .translate: scheduler.edit(query, target: targetLanguage)
            }
        }
    }

    private(set) var results: [EmojiEntry] = []
    private(set) var selectedIndex = 0
    private(set) var selectedCommandIndex = 0
    private(set) var homeItems: [HomeItem] = []
    private(set) var focusRequest = 0

    @ObservationIgnored var onDismiss: () -> Void = {}
    @ObservationIgnored var onOutput: (String, OutputAction) -> Void = { _, _ in }
    @ObservationIgnored var onOpenApp: (InstalledApp) -> Void = { _ in }

    private let catalog: EmojiCatalog
    private let translator: any Translator
    private let scheduler: TranslationScheduler
    private let languages = LanguagePair.englishRussian
    private var targetOverride: String?
    @ObservationIgnored private var apps: [InstalledApp] = []

    init(catalog: EmojiCatalog, translator: any Translator) {
        self.catalog = catalog
        self.translator = translator
        scheduler = TranslationScheduler(translator: translator)
        results = catalog.browse(recents: recents)
        refreshHome()
        reloadApps()
    }

    var translation: TranslationState {
        scheduler.state
    }

    var selectedEntry: EmojiEntry? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    var targetLanguage: String {
        targetOverride ?? languages.target(for: query)
    }

    var sourceLanguage: String {
        languages.other(than: targetLanguage)
    }

    func prepareForShow() {
        focusRequest += 1
        reloadApps()
        warmUpIfTranslating()
    }

    func reset() {
        mode = .home
        query = ""
    }

    func open(_ command: LauncherCommand) {
        query = ""
        switch command.kind {
        case .emoji: mode = .emoji
        case .translate: mode = .translate
        }
    }

    func handle(_ key: LauncherKey) -> Bool {
        switch key {
        case .escape:
            if mode == .home {
                onDismiss()
            } else {
                reset()
            }
            return true
        case .tab:
            switch mode {
            case .home: break
            case .emoji: mode = .translate
            case .translate: mode = .emoji
            }
            return true
        case .swapLanguages:
            guard mode == .translate else { return false }
            targetOverride = languages.other(than: targetLanguage)
            refreshNow()
            return true
        case .enter(let command):
            confirm(command: command)
            return true
        case .left: return moveSelection(by: -1)
        case .right: return moveSelection(by: 1)
        case .up: return moveRow(by: -1)
        case .down: return moveRow(by: 1)
        }
    }

    func activate(_ item: HomeItem) {
        switch item {
        case .command(let command): open(command)
        case .app(let app): onOpenApp(app)
        }
    }

    func choose(index: Int) {
        selectedIndex = index
        confirm(command: false)
    }

    /// In translate mode the arrows stay with the text field, so the caret can move.
    private func moveSelection(by offset: Int) -> Bool {
        guard mode == .emoji else { return false }
        guard !results.isEmpty else { return true }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
        return true
    }

    private func moveRow(by rows: Int) -> Bool {
        guard mode == .home else { return moveSelection(by: rows * Self.gridColumns) }
        let lastIndex = homeItems.count - 1
        guard lastIndex >= 0 else { return true }
        selectedCommandIndex = min(max(selectedCommandIndex + rows, 0), lastIndex)
        return true
    }

    private func confirm(command: Bool) {
        switch mode {
        case .home:
            guard homeItems.indices.contains(selectedCommandIndex) else { return }
            activate(homeItems[selectedCommandIndex])
        case .emoji:
            guard let entry = selectedEntry else { return }
            remember(entry)
            onOutput(entry.character, command ? .copy : .paste)
        case .translate:
            switch translation {
            case .done(let result): onOutput(result.text, command ? .paste : .copy)
            case .failed: refreshNow()
            case .loading where scheduler.isWaiting: refreshNow()
            case .idle, .loading: break
            }
        }
    }

    private func refreshNow() {
        switch mode {
        case .home:
            scheduler.cancel()
            refreshHome()
        case .emoji:
            scheduler.cancel()
            selectedIndex = 0
            results = query.isEmpty ? catalog.browse(recents: recents) : catalog.search(query)
        case .translate:
            scheduler.translateNow(query, target: targetLanguage)
        }
    }

    private func refreshHome() {
        selectedCommandIndex = 0
        homeItems = LauncherCommand.matching(query).map(HomeItem.command)
            + AppSearch.search(apps, query: query).map(HomeItem.app)
    }

    /// Runs on every open, so newly installed apps appear without restarting Railcast.
    private func reloadApps() {
        Task { [weak self] in
            let scanned = await Task.detached { AppScanner.scan() }.value
            guard let self, scanned != apps else { return }
            apps = scanned
            if mode == .home {
                refreshHome()
            }
        }
    }

    private func warmUpIfTranslating() {
        guard mode == .translate else { return }
        Task { [translator] in await translator.warmUp() }
    }

    private var recents: [String] {
        UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
    }

    private func remember(_ entry: EmojiEntry) {
        let updated = [entry.character] + recents.filter { $0 != entry.character }
        UserDefaults.standard.set(Array(updated.prefix(Self.maxRecents)), forKey: Self.recentsKey)
    }
}
