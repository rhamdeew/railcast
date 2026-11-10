import AppKit
import ApplicationServices
import RailcastCore
import SwiftUI

/// A panel that takes keyboard input without activating Railcast, so the previous app stays frontmost.
final class LauncherPanel: NSPanel {
    var onKey: ((LauncherKey) -> Bool)?
    var acceptsKeyboard = true

    override var canBecomeKey: Bool { acceptsKeyboard }

    override func sendEvent(_ event: NSEvent) {
        // Intercept here because the text field would otherwise consume Tab, Return and the arrows.
        if event.type == .keyDown, !isComposingText, let key = LauncherKey(event), onKey?(key) == true {
            return
        }
        super.sendEvent(event)
    }

    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
}

@MainActor
final class LauncherController: NSObject, NSWindowDelegate {
    private static let size = NSSize(width: 640, height: 440)

    private let model: LauncherModel
    private let panel: LauncherPanel

    init(catalog: EmojiCatalog) {
        model = LauncherModel(catalog: catalog, translator: GoogleTranslator())
        panel = LauncherPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onKey = { [weak model] key in
            model?.handle(key) ?? false
        }

        let hostingView = NSHostingView(rootView: LauncherView(model: model))
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        model.onDismiss = { [weak self] in self?.hide() }
        model.onOutput = { [weak self] text, action in self?.deliver(text, action) }
        model.onOpenApp = { [weak self] app in self?.launch(app) }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        positionPanel()
        model.prepareForShow()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
        model.reset()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// `--show [--emoji | --translate] [--query text]` displays the panel at launch, for testing the UI.
    /// The panel refuses key status in this mode, so it cannot capture what the user is typing elsewhere.
    func applyLaunchArguments(_ arguments: [String]) {
        guard arguments.contains("--show") else { return }
        if arguments.contains("--translate") {
            model.mode = .translate
        } else if arguments.contains("--emoji") {
            model.mode = .emoji
        }
        panel.acceptsKeyboard = false
        positionPanel()
        panel.orderFrontRegardless()
        if let index = arguments.firstIndex(of: "--query"), arguments.indices.contains(index + 1) {
            let text = arguments[index + 1]
            // Wait until the text field has appeared, or it overwrites the query with its empty value.
            Task { [model] in
                try? await Task.sleep(for: .milliseconds(300))
                model.query = text
            }
        }
    }

    /// Centers horizontally on the screen under the mouse, in its upper part.
    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: area.midX - Self.size.width / 2,
            y: area.minY + (area.height - Self.size.height) * 0.65
        ))
    }

    private func launch(_ app: InstalledApp) {
        hide()
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: app.path),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                NSLog("Railcast: could not open %@: %@", app.name, error.localizedDescription)
            }
        }
    }

    private func deliver(_ text: String, _ action: OutputAction) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        hide()
        guard action == .paste else { return }

        // Without this permission the text stays on the clipboard and macOS asks for access.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }
        Task {
            // Give focus time to return to the previous app.
            try? await Task.sleep(for: .milliseconds(80))
            Self.postPasteKeystroke()
        }
    }

    private static func postPasteKeystroke() {
        let virtualKeyV: CGKeyCode = 9
        let source = CGEventSource(stateID: .combinedSessionState)
        for isKeyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: isKeyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
