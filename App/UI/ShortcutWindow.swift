import AppKit
import PicseeMacUI

@MainActor
final class ShortcutWindow: NSObject {
    let window: NSWindow
    private let appearanceAdapter: WindowAppearanceAdapter

    init(menu: NSMenu, appearanceAdapter: WindowAppearanceAdapter) {
        self.appearanceAdapter = appearanceAdapter
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 502),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = String(localized: "Keyboard Shortcuts")
        window.identifier = NSUserInterfaceItemIdentifier("keyboard-shortcuts.window")
        window.isReleasedWhenClosed = false
        window.contentView = ShortcutListView(frame: NSRect(x: 0, y: 0, width: 820, height: 502),
            catalog: ShortcutCatalog(menu: menu))
        window.center()
    }

    func show() {
        appearanceAdapter.register(window)
        window.makeKeyAndOrderFront(nil)
    }
}
