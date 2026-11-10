import AppKit
import RailcastCore
import SwiftUI

struct LauncherView: View {
    @Bindable var model: LauncherModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            Group {
                switch model.mode {
                case .home: CommandList(model: model)
                case .emoji: EmojiGrid(model: model)
                case .translate: TranslationPane(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { isFieldFocused = true }
        .onChange(of: model.focusRequest) { isFieldFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: fieldSymbol)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField(fieldPlaceholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($isFieldFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var fieldSymbol: String {
        switch model.mode {
        case .home: "magnifyingglass"
        case .emoji: "face.smiling"
        case .translate: "character.bubble"
        }
    }

    private var fieldPlaceholder: String {
        switch model.mode {
        case .home: "Search functions and apps"
        case .emoji: "Search emoji and symbols"
        case .translate: "Text to translate"
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(footerTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            ForEach(footerHints, id: \.self) { hint in
                Text(hint).foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var footerTitle: String {
        switch model.mode {
        case .home:
            "Railcast"
        case .emoji:
            model.selectedEntry?.name ?? "No results"
        case .translate:
            "\(LanguagePair.displayName(of: model.sourceLanguage)) → \(LanguagePair.displayName(of: model.targetLanguage))"
        }
    }

    private var footerHints: [String] {
        switch model.mode {
        case .home: ["↑↓ Select", "↵ Open"]
        case .emoji: ["esc Back", "⇥ Translate", "⌘↵ Copy", "↵ Paste"]
        case .translate: ["esc Back", "⇥ Emoji", "⌘L Swap", "⌘↵ Paste", "↵ Copy"]
        }
    }
}

private struct CommandList: View {
    let model: LauncherModel

    var body: some View {
        if model.homeItems.isEmpty {
            Text("No matching functions or apps")
                .foregroundStyle(.secondary)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.homeItems.indices, id: \.self) { index in
                            if let title = sectionTitle(at: index) {
                                sectionHeader(title)
                            }
                            row(model.homeItems[index], isSelected: index == model.selectedCommandIndex)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: model.selectedCommandIndex) { _, index in proxy.scrollTo(index) }
                .onChange(of: model.query) { proxy.scrollTo(0, anchor: .top) }
            }
        }
    }

    private func sectionTitle(at index: Int) -> String? {
        let items = model.homeItems
        switch items[index] {
        case .command:
            if index == 0 { return "Functions" }
            if case .app = items[index - 1] { return "Railcast" }
            return nil
        case .app:
            if index > 0, case .app = items[index - 1] { return nil }
            return "Apps"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 4)
    }

    private func row(_ item: HomeItem, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            icon(for: item)
            Text(title(of: item))
                .font(.system(size: 15))
                .lineLimit(1)
            Text(subtitle(of: item))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.35) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.activate(item) }
    }

    private func tint(of command: LauncherCommand) -> Color {
        switch command.kind {
        case .emoji: .orange
        case .translate: .blue
        case .toggleMenuBarIcon, .quit: .gray
        }
    }

    private func title(of item: HomeItem) -> String {
        switch item {
        case .command(let command): command.title
        case .app(let app): app.name
        }
    }

    private func subtitle(of item: HomeItem) -> String {
        switch item {
        case .command(let command): command.subtitle
        case .app: "Application"
        }
    }

    @ViewBuilder
    private func icon(for item: HomeItem) -> some View {
        switch item {
        case .command(let command):
            Image(systemName: command.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint(of: command))
                )
        case .app(let app):
            Image(nsImage: AppIcons.icon(forPath: app.path))
                .resizable()
                .frame(width: 28, height: 28)
        }
    }
}

/// Moving the selection redraws every visible row, so icons are loaded once.
@MainActor
private enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}

private struct EmojiGrid: View {
    let model: LauncherModel

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: LauncherModel.gridColumns
    )

    var body: some View {
        if model.results.isEmpty {
            Text("No results").foregroundStyle(.secondary)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(model.results.indices, id: \.self) { index in
                            cell(index)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: model.selectedIndex) { _, index in proxy.scrollTo(index) }
                .onChange(of: model.query) { proxy.scrollTo(0, anchor: .top) }
            }
        }
    }

    private func cell(_ index: Int) -> some View {
        Text(model.results[index].character)
            .font(.system(size: 34))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(index == model.selectedIndex ? Color.accentColor.opacity(0.35) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { model.choose(index: index) }
            .id(index)
    }
}

private struct TranslationPane: View {
    let model: LauncherModel

    var body: some View {
        switch model.translation {
        case .idle:
            Text("Type or paste text").foregroundStyle(.secondary)
        case .loading(let previous):
            if let previous {
                resultText(previous).opacity(0.45)
            } else {
                ProgressView().controlSize(.small)
            }
        case .done(let result):
            resultText(result.text)
        case .failed(let message):
            VStack(spacing: 6) {
                Text(message)
                Text("Press ↵ to retry").foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func resultText(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 20))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
