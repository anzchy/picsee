import AppKit
import Testing
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@MainActor @Test func issue219HelpOpensOneShortcutWindowAndCommandWClosesIt() throws {
    _ = NSApplication.shared
    let previousMenu = NSApp.mainMenu
    var shortcutWindow: ShortcutWindow!
    let menu = CommandMenu(preferencesStore: InMemoryDisplayPreferencesStore(),
        openWithoutWindow: {}, openSettings: {}, openDiagnostics: {},
        openShortcuts: { shortcutWindow.show() }, windowController: { nil })
    shortcutWindow = ShortcutWindow(menu: try #require(NSApp.mainMenu),
        appearanceAdapter: WindowAppearanceAdapter(preferencesStore: InMemoryDisplayPreferencesStore()))
    defer {
        shortcutWindow.window.close()
        NSApp.mainMenu = previousMenu
        withExtendedLifetime(menu) {}
        withExtendedLifetime(shortcutWindow) {}
    }
    let main = try #require(NSApp.mainMenu)
    let help = try #require(main.items.first { $0.title == "Help" }?.submenu)
    let shortcuts = try #require(help.items.first { $0.identifier?.rawValue == "help.keyboard-shortcuts.menu" })
    #expect(menu.validateMenuItem(shortcuts))
    #expect(shortcuts.isEnabled)
    #expect(shortcuts.keyEquivalent.isEmpty)
    #expect(shortcuts.action != nil)
    #expect(shortcuts.title == String(localized: "Keyboard Shortcuts"))
    #expect(shortcuts.accessibilityLabel()?.contains("Coming Soon") == false)
    #expect(shortcuts.accessibilityLabel()?.contains("即将推出") == false)

    let action = try #require(shortcuts.action)
    #expect(NSApp.sendAction(action, to: shortcuts.target, from: shortcuts))
    let first = shortcutWindow.window
    #expect(first.isVisible)
    #expect(first.title == String(localized: "Keyboard Shortcuts"))
    #expect(first.styleMask.contains(.titled))
    #expect(first.styleMask.contains(.closable))
    #expect(first.identifier?.rawValue == "keyboard-shortcuts.window")
    #expect(NSApp.sendAction(action, to: shortcuts.target, from: shortcuts))
    #expect(shortcutWindow.window === first)

    let file = try #require(main.items.first { $0.title == "File" }?.submenu)
    let close = try #require(file.items.first { $0.keyEquivalent == "w" })
    #expect(close.keyEquivalentModifierMask == [.command])
    #expect(close.action == #selector(NSWindow.performClose(_:)))
    #expect(NSApp.sendAction(try #require(close.action), to: first, from: close))
    #expect(!first.isVisible)
}

@MainActor @Test func issue219RealMainMenuCatalogListsEverySourceExactlyOnce() throws {
    _ = NSApplication.shared
    let previousMenu = NSApp.mainMenu
    let menu = CommandMenu(preferencesStore: InMemoryDisplayPreferencesStore(),
        openWithoutWindow: {}, openSettings: {}, openDiagnostics: {}, windowController: { nil })
    defer { NSApp.mainMenu = previousMenu; withExtendedLifetime(menu) {} }
    let catalog = ShortcutCatalog(menu: try #require(NSApp.mainMenu), language: .english)
    let sources = catalog.cards.flatMap { $0.rows.flatMap { $0.sources.map(\.id) } }
    let expected = [
        "command:open", "menu:Settings…", "menu:Close", "menu:Minimize", "menu:Hide Picsee",
        "menu:Hide Others", "menu:Quit Picsee", "key:grid-arrows", "command:preview", "command:enter",
        "menu:Search current folder", "menu:Hide sidebar", "command:previous", "command:next", "command:escape",
        "command:fit", "command:actualPixels", "command:zoomIn", "command:zoomOut", "key:viewer-tab",
        "command:inspector", "menu:Enter Full Screen",
    ]
    #expect(expected.count == 22)
    #expect(sources.count == expected.count)
    #expect(Set(sources).count == expected.count)
    for id in expected { #expect(sources.filter { $0 == id }.count == 1, "missing or duplicated \(id)") }
}
