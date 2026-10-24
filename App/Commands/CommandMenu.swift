import AppKit
import PicseeCore
import PicseeApplication
import PicseeMacUI

extension CommandID {
    var menuTitle: String {
        switch self {
        case .previous: String(localized: "Previous Image")
        case .next: String(localized: "Next Image")
        case .fit: String(localized: "Fit")
        case .actualPixels: String(localized: "Actual Pixels")
        case .zoomIn: String(localized: "Zoom In")
        case .zoomOut: String(localized: "Zoom Out")
        case .open: String(localized: "Open…")
        case .inspector: String(localized: "Show Inspector")
        case .escape: String(localized: "Focus Canvas")
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
    private let preferencesStore: any DisplayPreferencesStore
    private var trackingMenus: Set<ObjectIdentifier> = []
    private let openWithoutWindow: () -> Void
    private(set) var isTracking = false
    private let recentFolders = NSMenu(title: String(localized: "Open Recent"))
    private let recentTarget = RecentFolderMenuTarget()
    private let extensionMenu = NSMenu(title: String(localized: "Extensions"))
    private weak var folderViewMenu: NSMenu?
    private var folderSubmenuItems: [NSMenuItem] = []

    init(preferencesStore: any DisplayPreferencesStore, openWithoutWindow: @escaping () -> Void) {
        self.preferencesStore = preferencesStore
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
        let app = submenu("Picsee")
        app.addItem(withTitle: String(localized: "About Picsee"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Hide Picsee"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.option, .command]
        app.addItem(withTitle: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Quit Picsee"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu(String(localized: "File"))
        let edit = submenu(String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: String(localized: "Redo"), action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: String(localized: String.LocalizationValue(title)), action: NSSelectorFromString(action), keyEquivalent: key)
        }
        let view = submenu(String(localized: "View"))
        folderViewMenu = view
        for id in CommandID.menuCommands {
            let item = NSMenuItem(title: id.menuTitle, action: #selector(invoke(_:)), keyEquivalent: id.defaultKey)
            item.keyEquivalentModifierMask = id.usesCommand ? [.command] : []
            item.representedObject = id.rawValue
            item.setAccessibilityIdentifier("command.\(id.rawValue).menu")
            item.target = self
            (id == .open ? file : view).addItem(item)
        }
        let always = view.addItem(withTitle: String(localized: "Always Show Tools"), action: #selector(toggleAlwaysShowTools(_:)), keyEquivalent: "")
        always.target = self
        always.identifier = NSUserInterfaceItemIdentifier("chrome.always-show-tools")
        always.setAccessibilityIdentifier("chrome.always-show-tools.menu")
        let appearanceMenu = NSMenu(title: String(localized: "Appearance"))
        appearanceMenu.delegate = self
        let appearanceItem = NSMenuItem(title: String(localized: "Appearance"), action: nil, keyEquivalent: "")
        appearanceItem.submenu = appearanceMenu
        appearanceItem.setAccessibilityIdentifier("prefs.appearance.menu")
        view.addItem(appearanceItem)
        let appearances: [(DisplayAppearance, String)] = [(.system, String(localized: "System")),
            (.light, String(localized: "Light")), (.dark, String(localized: "Dark"))]
        for (appearance, title) in appearances {
            let item = appearanceMenu.addItem(withTitle: title, action: #selector(selectAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = appearance.rawValue
            item.setAccessibilityIdentifier("prefs.appearance.\(appearance.rawValue).menu")
        }
        let sortMenu = NSMenu(title: String(localized: "Sort By"))
        sortMenu.delegate = self
        let sortItem = NSMenuItem(title: sortMenu.title, action: nil, keyEquivalent: "")
        sortItem.submenu = sortMenu
        sortItem.setAccessibilityIdentifier("folder.sort.menu")
        view.addItem(sortItem)
        folderSubmenuItems.append(sortItem)
        for key in FolderSortKey.allCases { addFolderItem(.sort(key), to: sortMenu) }
        let orderMenu = NSMenu(title: String(localized: "Sort Order"))
        orderMenu.delegate = self
        let orderItem = NSMenuItem(title: orderMenu.title, action: nil, keyEquivalent: "")
        orderItem.submenu = orderMenu
        orderItem.setAccessibilityIdentifier("folder.order.menu")
        view.addItem(orderItem)
        folderSubmenuItems.append(orderItem)
        for direction in FolderSortDirection.allCases { addFolderItem(.direction(direction), to: orderMenu) }
        extensionMenu.delegate = self
        let extensionItem = NSMenuItem(title: extensionMenu.title, action: nil, keyEquivalent: "")
        extensionItem.submenu = extensionMenu
        extensionItem.setAccessibilityIdentifier("folder.extensions.menu")
        view.addItem(extensionItem)
        folderSubmenuItems.append(extensionItem)
        addFolderItem(.loop, to: view)
        view.addItem(.separator())
        let fullScreen = view.addItem(withTitle: String(localized: "Enter Full Screen"),
            action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        let recentItem = NSMenuItem(title: String(localized: "Open Recent"), action: nil, keyEquivalent: "")
        recentItem.submenu = recentFolders
        recentFolders.autoenablesItems = false
        recentFolders.delegate = self
        file.addItem(recentItem)
        setRecentFolders([], onOpen: { _ in })
        ChromeWindowCommands.addClose(to: file)
        let windows = submenu(String(localized: "Window"))
        windows.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windows.addItem(withTitle: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
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

    @objc private func toggleAlwaysShowTools(_ item: NSMenuItem) {
        var value = preferencesStore.value
        value.alwaysShowTools.toggle()
        preferencesStore.value = value
    }
    @objc private func selectAppearance(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let appearance = DisplayAppearance(rawValue: raw) else { return }
        preferencesStore.value.appearance = appearance
    }
    private func addFolderItem(_ action: FolderMenuAction, to menu: NSMenu) {
        let title: String
        if case .extensionType(let value) = action, !value.isEmpty { title = value.uppercased() }
        else { title = String(localized: String.LocalizationValue(action.titleKey)) }
        let item = menu.addItem(withTitle: title, action: #selector(invokeFolder(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
        item.setAccessibilityIdentifier(action.accessibilityIdentifier)
    }
    @objc private func invokeFolder(_ item: NSMenuItem) {
        guard let action = item.representedObject as? FolderMenuAction,
              let session = (NSApp.keyWindow?.windowController as? CanvasWindowController)?.session,
              session.hasFolderSource, session.filePreviewSet == nil, session.previewSet == nil else { return }
        let selection = FolderMenuSelection(conditions: session.folderConditions, loopEnabled: session.folderLoopEnabled)
        let changed = FolderMenuPolicy.applying(action, to: selection)
        session.setFolderConditions(changed.conditions)
        session.setFolderLoopEnabled(changed.loopEnabled)
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let action = item.representedObject as? FolderMenuAction {
            let session = (NSApp.keyWindow?.windowController as? CanvasWindowController)?.session
            let selection = FolderMenuSelection(conditions: session?.folderConditions ?? .init(),
                loopEnabled: session?.folderLoopEnabled ?? false)
            let state = FolderMenuPolicy.state(for: action, selection: selection,
                hasFolderSource: session?.hasFolderSource == true,
                previewActive: session?.filePreviewSet != nil || session?.previewSet != nil)
            item.state = state.checked ? .on : .off
            return state.enabled
        }
        if item.action == #selector(selectAppearance(_:)),
           let raw = item.representedObject as? String, let appearance = DisplayAppearance(rawValue: raw) {
            item.state = preferencesStore.value.appearance == appearance ? .on : .off
            return true
        }
        if item.identifier?.rawValue == "chrome.always-show-tools" {
            item.state = preferencesStore.value.alwaysShowTools ? .on : .off
            return true
        }
        guard let raw = item.representedObject as? String, let id = CommandID(rawValue: raw) else { return false }
        let target = NSApp.keyWindow?.windowController as? CanvasWindowController
        if id == .inspector { item.title = target?.inspectorVisible == true ? String(localized: "Hide Inspector") : String(localized: "Show Inspector") }
        return target?.session.isEnabled(id) ?? (id == .open)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === folderViewMenu { updateFolderSubmenus() }
        guard menu === extensionMenu else { return }
        extensionMenu.removeAllItems()
        addFolderItem(.clearFilter, to: extensionMenu)
        extensionMenu.addItem(.separator())
        let session = (NSApp.keyWindow?.windowController as? CanvasWindowController)?.session
        let available = (session?.folderAvailableExtensions ?? []) + Array(session?.folderConditions.selectedExtensions ?? [])
        for value in FolderMenuPolicy.extensionChoices(available: available) {
            addFolderItem(.extensionType(value), to: extensionMenu)
        }
    }
    private func updateFolderSubmenus() {
        let session = (NSApp.keyWindow?.windowController as? CanvasWindowController)?.session
        let enabled = session?.hasFolderSource == true && session?.filePreviewSet == nil && session?.previewSet == nil
        for item in folderSubmenuItems { item.isEnabled = enabled }
    }
    func menuWillOpen(_ menu: NSMenu) {
        if menu === folderViewMenu { updateFolderSubmenus() }
        trackingMenus.insert(ObjectIdentifier(menu))
        isTracking = true
        (NSApp.keyWindow?.windowController as? CanvasWindowController)?.session.setMenuTracking(true)
    }
    func menuDidClose(_ menu: NSMenu) {
        trackingMenus.remove(ObjectIdentifier(menu))
        isTracking = !trackingMenus.isEmpty
        guard !isTracking else { return }
        // The key window can change during menu tracking. Release the original window too.
        for window in NSApp.windows {
            (window.windowController as? CanvasWindowController)?.session.setMenuTracking(false)
        }
    }
}
