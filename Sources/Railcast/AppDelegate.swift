import AppKit
import Carbon.HIToolbox
import RailcastCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launcher: LauncherController?
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()

        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? EmojiCatalog(json: data)
        else {
            fatalError("emoji.json is missing or invalid. Run Scripts/build-app.sh and launch the .app.")
        }

        let start = ContinuousClock.now
        let systemKeywords = SystemEmojiKeywords.load(language: "ru")
        NSLog("Railcast: loaded system keywords for %d emoji in %@", systemKeywords.count, "\(ContinuousClock.now - start)")

        let launcher = LauncherController(catalog: catalog.addingKeywords(systemKeywords))
        self.launcher = launcher

        registerHotKey()
        launcher.onMenuBarIconChange = { [weak self] isHidden in
            self?.updateStatusItem(isHidden: isHidden)
        }
        updateStatusItem(isHidden: launcher.isMenuBarIconHidden)
        launcher.applyLaunchArguments(CommandLine.arguments)
    }

    /// Opening Railcast.app again shows the panel, which also works while the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launcher?.show()
        return false
    }

    private func updateStatusItem(isHidden: Bool) {
        if isHidden {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        } else if statusItem == nil {
            statusItem = makeStatusItem()
        }
    }

    /// Retries while another app holds the shortcut, so quitting that app is enough to free it.
    private func registerHotKey(isRetry: Bool = false) {
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.launcher?.toggle()
        }
        if hotKey != nil {
            NSLog("Railcast: registered Option-Space")
            return
        }
        if !isRetry {
            NSLog("Railcast: Option-Space is taken, retrying")
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            registerHotKey(isRetry: true)
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarImage()

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Railcast (⌥Space)", action: #selector(openLauncher), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Railcast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        return item
    }

    private static func menuBarImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return NSImage(systemSymbolName: "command", accessibilityDescription: "Railcast") }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Railcast"
        return image
    }

    @objc private func hideMenuBarIcon() {
        launcher?.isMenuBarIconHidden = true
    }

    @objc private func openLauncher() {
        launcher?.show()
    }

    /// Accessory apps show no menu bar, but text fields still need these items for ⌘C, ⌘V, ⌘A and ⌘Z.
    private static func makeMainMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = edit
        let menu = NSMenu()
        menu.addItem(editItem)
        return menu
    }
}
