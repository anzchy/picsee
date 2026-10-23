import AppKit
import PicseeCore

extension CommandID {
    var menuTitle: String {
        switch self {
        case .previous: String(localized: "Previous Image")
        case .next: String(localized: "Next Image")
        case .fit: "Fit"
        case .actualPixels: "Actual Pixels"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .open: "Open…"
        case .inspector: "Show Inspector"
        case .escape: "Focus Canvas"
        default: preconditionFailure("Unimplemented commands have no menu item")
        }
    }
}

/// Bare equivalents must defer to the native field editor before menu dispatch.
final class CommandMainMenu: NSMenu {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            guard NSApp.keyWindow?.windowController is CanvasWindowController,
                  !(NSApp.keyWindow?.firstResponder is NSTextInputClient) else { return false }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class CommandMenu: NSObject, NSMenuItemValidation, NSMenuDelegate {
    private let openWithoutWindow: () -> Void
    private(set) var isTracking = false
    private let recentFolders = NSMenu(title: String(localized: "Open Recent"))
    private let recentTarget = RecentFolderMenuTarget()

    init(openWithoutWindow: @escaping () -> Void) {
        self.openWithoutWindow = openWithoutWindow
        super.init()
        let main = CommandMainMenu(title: "Picsee")
        func submenu(_ title: String) -> NSMenu {
            let menu = NSMenu(title: title)
            menu.delegate = self
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
            return menu
        }
        submenu("Picsee").addItem(withTitle: "Quit Picsee", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu("File")
        let edit = submenu("Edit")
        edit.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        let view = submenu("View")
        for id in CommandID.menuCommands {
            let item = NSMenuItem(title: id.menuTitle, action: #selector(invoke(_:)), keyEquivalent: id.defaultKey)
            item.keyEquivalentModifierMask = id.usesCommand ? [.command] : []
            item.representedObject = id.rawValue
            item.setAccessibilityIdentifier("command.\(id.rawValue).menu")
            item.target = self
            (id == .open ? file : view).addItem(item)
        }
        view.addItem(.separator())
        let fullScreen = view.addItem(withTitle: String(localized: "Enter Full Screen"),
            action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        let recentItem = NSMenuItem(title: String(localized: "Open Recent"), action: nil, keyEquivalent: "")
        recentItem.submenu = recentFolders
        recentFolders.autoenablesItems = false
        file.addItem(recentItem)
        setRecentFolders([], onOpen: { _ in })
        let windows = submenu("Window")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        #if DEBUG
        let preview = windows.addItem(withTitle: String(localized: "Component Preview"), action: #selector(DesignPreviewLauncher.openPreview(_:)), keyEquivalent: "")
        preview.target = DesignPreviewLauncher.shared
        #endif
        NSApp.windowsMenu = windows
        NSApp.mainMenu = main
    }

    func setRecentFolders(_ folders: [RecentFolder], onOpen: @escaping (RecentFolder) -> Void) {
        recentTarget.onOpen = onOpen
        recentFolders.removeAllItems()
        if folders.isEmpty {
            let empty = recentFolders.addItem(withTitle: String(localized: "No Recent Folders"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
        for folder in folders {
            let item = recentFolders.addItem(withTitle: folder.displayName, action: #selector(RecentFolderMenuTarget.open(_:)), keyEquivalent: "")
            item.target = recentTarget
            item.representedObject = folder
        }
    }

    @objc private func invoke(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let id = CommandID(rawValue: raw) else { return }
        if let target = NSApp.keyWindow?.windowController as? CanvasWindowController {
            target.route(id, from: .menu)
        } else if id == .open { openWithoutWindow() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let raw = item.representedObject as? String, let id = CommandID(rawValue: raw) else { return false }
        let target = NSApp.keyWindow?.windowController as? CanvasWindowController
        if id == .inspector { item.title = target?.inspectorVisible == true ? "Hide Inspector" : "Show Inspector" }
        return target?.session.isEnabled(id) ?? (id == .open)
    }
    func menuWillOpen(_ menu: NSMenu) {
        isTracking = true
        (NSApp.keyWindow?.windowController as? CanvasWindowController)?.session.setMenuTracking(true)
    }
    func menuDidClose(_ menu: NSMenu) {
        isTracking = false
        // The key window can change during menu tracking. Release the original window too.
        for window in NSApp.windows {
            (window.windowController as? CanvasWindowController)?.session.setMenuTracking(false)
        }
    }
}
