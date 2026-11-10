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
        case .home: "Search functions"
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
        let commands = model.visibleCommands
        VStack(alignment: .leading, spacing: 2) {
            if commands.isEmpty {
                Text("No matching functions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Functions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                    row(command, isSelected: index == model.selectedCommandIndex)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
    }

    private func row(_ command: LauncherCommand, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(command.kind == .emoji ? Color.orange : Color.blue)
                )
            Text(command.title)
                .font(.system(size: 15))
            Text(command.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.35) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.open(command) }
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
