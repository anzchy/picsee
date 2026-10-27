import AppKit
import Testing
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI
import PicseeCore

@MainActor private final class KeyTestMotionSource: ReduceMotionSource {
    var reduceMotion = false
    var onChange: (@MainActor () -> Void)?
}

@MainActor @Test func issue136SmokeInspectorMenuEquivalentPreservesGridSearchEditor() throws {
    _ = NSApplication.shared
    let preferences = InMemoryDisplayPreferencesStore()
    let previousMenu = NSApp.mainMenu
    let unavailable = Task<AccessServices, Error> { throw CancellationError() }
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(), preferencesStore: preferences,
        accessServices: unavailable, motionPolicy: MotionPolicy(source: KeyTestMotionSource()))
    let menu = CommandMenu(preferencesStore: preferences, openWithoutWindow: {}, openSettings: {},
        windowController: { controller })
    let window = try #require(controller.window as? CommandWindow)
    defer { window.close(); NSApp.mainMenu = previousMenu; withExtendedLifetime(menu) {} }
    let shell = try #require(window.contentView?.subviews.compactMap { $0 as? GridShellView }.first)
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: URL(fileURLWithPath: "/tmp/issue136-smoke-menu"))
    let item = FolderEntry(url: root.url.appendingPathComponent("cat.jpg"), root: root)
    controller.session.beginBrowsing(items: [item.itemID], sourceVersion: .init(1), scrollAnchor: nil)
    controller.session.focus(item.itemID)
    controller.showGrid()
    func command(_ letter: String, keyCode: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: letter,
            charactersIgnoringModifiers: letter, isARepeat: false, keyCode: keyCode))
    }
    let mainMenu = try #require(NSApp.mainMenu)
    #expect(controller.route(.search, from: .key))
    let editor = try #require(shell.searchField.currentEditor() as? NSTextView)
    editor.insertText("ca")
    let caret = NSRange(location: 2, length: 0)
    editor.selectedRange = caret
    #expect(window.firstResponder === editor)
    let commandI = try command("i", keyCode: 34)
    #expect(mainMenu.performKeyEquivalent(with: commandI))
    #expect(controller.session.inspectorFocus.isVisible)
    #expect(!shell.searchField.isHidden)
    #expect(window.firstResponder === shell.searchField.currentEditor())
    #expect(shell.searchField.stringValue == "ca")
    #expect((shell.searchField.currentEditor() as? NSTextView)?.selectedRange == caret)
    #expect(mainMenu.performKeyEquivalent(with: commandI))
    #expect(!controller.session.inspectorFocus.isVisible)
    #expect(!shell.searchField.isHidden)
    #expect(window.firstResponder === shell.searchField.currentEditor())
    #expect((shell.searchField.currentEditor() as? NSTextView)?.selectedRange == caret)
    shell.searchField.currentEditor()?.insertText("t")
    #expect(shell.searchField.stringValue == "cat")
}

@MainActor @Test func issue136CombinedWindowSearchFocusEscapeAndInspectorToggle() throws {
    _ = NSApplication.shared
    let unavailable = Task<AccessServices, Error> { throw CancellationError() }
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: unavailable,
        motionPolicy: MotionPolicy(source: KeyTestMotionSource()))
    let window = try #require(controller.window as? CommandWindow)
    defer { window.close() }
    let shell = try #require(window.contentView?.subviews.compactMap { $0 as? GridShellView }.first)
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: URL(fileURLWithPath: "/tmp/issue136-combo"))
    let item = FolderEntry(url: root.url.appendingPathComponent("cat.jpg"), root: root)
    controller.session.beginBrowsing(items: [item.itemID], sourceVersion: .init(1), scrollAnchor: nil)
    controller.session.focus(item.itemID)
    controller.showGrid()
    #expect(controller.route(.inspector, from: .key))
    #expect(controller.session.inspectorFocus.isVisible)
    #expect(controller.route(.search, from: .key))
    let editor = try #require(shell.searchField.currentEditor() as? NSTextView)
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    #expect(window.firstResponder === editor)
    editor.insertText("cat")
    #expect(shell.searchField.stringValue == "cat")
    let caret = NSRange(location: 2, length: 0)
    editor.selectedRange = caret
    let commandI = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "i", charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34))
    window.sendEvent(commandI)
    #expect(!controller.session.inspectorFocus.isVisible)
    #expect(window.firstResponder === editor)
    #expect(shell.searchField.stringValue == "cat")
    #expect((shell.searchField.currentEditor() as? NSTextView)?.selectedRange == caret)
    window.sendEvent(commandI)
    #expect(controller.session.inspectorFocus.isVisible)
    #expect(window.firstResponder === editor)
    #expect((shell.searchField.currentEditor() as? NSTextView)?.selectedRange == caret)
    shell.searchField.currentEditor()?.insertText("X")
    #expect(shell.searchField.stringValue == "caXt")
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false, keyCode: 53))
    window.sendEvent(escape)
    #expect(shell.searchField.stringValue.isEmpty)
    #expect(controller.session.inspectorFocus.isVisible)
}

@MainActor @Test func issue136CombinedWindowWatchedSearchRefreshUpdatesInspectorSynchronously() async throws {
    _ = NSApplication.shared
    let delayed = Task<AccessServices, Error> {
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: delayed,
        motionPolicy: MotionPolicy(source: KeyTestMotionSource()))
    let window = try #require(controller.window)
    defer { window.close(); delayed.cancel() }
    let shell = try #require(window.contentView?.subviews.compactMap { $0 as? GridShellView }.first)
    let grid = try #require(shell.mainContent.subviews.compactMap { $0 as? GridBrowserView }.first)
    let folder = URL(fileURLWithPath: "/tmp/issue136-combo-refresh")
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: folder)
    let a = FolderEntry(url: folder.appendingPathComponent("match-a.jpg"), root: root)
    let d = FolderEntry(url: folder.appendingPathComponent("match-d.jpg"), root: root)
    func snapshot(_ entries: [FolderEntry], generation: UInt64) -> FolderSnapshot {
        FolderSnapshot(version: .init(rootID: root.id, folder: folder, generation: generation),
            entries: entries, isComplete: true)
    }
    controller.browseRecoveredFolder(folder, rootID: root.id)
    controller.applyObservedGridSnapshot(snapshot([a, d], generation: 1))
    grid.setCurrentItemID(d.itemID)
    controller.session.focus(d.itemID)
    shell.focusSearch()
    shell.setSearchTerm("match")
    shell.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: shell.searchField))
    let deadline = Date().addingTimeInterval(2)
    while !shell.searchStatus.stringValue.contains("Search:") && Date() < deadline { await Task.yield() }
    #expect(shell.searchStatus.stringValue.contains("Search:"))
    #expect(controller.route(.inspector, from: .key))
    #expect(controller.inspector.name == d.url.lastPathComponent)
    controller.applyObservedGridSnapshot(snapshot([a], generation: 2))
    #expect(controller.inspector.name == a.url.lastPathComponent)
    controller.applyObservedGridSnapshot(snapshot([], generation: 3))
    #expect(controller.inspector.name == nil)
    #expect(controller.session.inspectorFocus.isVisible)
}

@MainActor @Test func issue136Combo2DirectSearchUpdatesInspectorWithoutWindowUpdate() async throws {
    _ = NSApplication.shared
    let delayed = Task<AccessServices, Error> {
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: delayed,
        motionPolicy: MotionPolicy(source: KeyTestMotionSource()))
    let window = try #require(controller.window)
    defer { window.close(); delayed.cancel() }
    let shell = try #require(window.contentView?.subviews.compactMap { $0 as? GridShellView }.first)
    let grid = try #require(shell.mainContent.subviews.compactMap { $0 as? GridBrowserView }.first)
    let folder = URL(fileURLWithPath: "/tmp/issue136-combo2-search")
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: folder)
    let a = FolderEntry(url: folder.appendingPathComponent("match-a.jpg"), root: root)
    let d = FolderEntry(url: folder.appendingPathComponent("match-d.jpg"), root: root)
    let source = FolderSnapshot(version: .init(rootID: root.id, folder: folder, generation: 1),
        entries: [a, d], isComplete: true)
    controller.browseRecoveredFolder(folder, rootID: root.id)
    controller.applyObservedGridSnapshot(source)
    grid.setCurrentItemID(d.itemID)
    controller.session.focus(d.itemID)
    #expect(controller.route(.inspector, from: .key))
    #expect(controller.inspector.name == d.url.lastPathComponent)
    func type(_ term: String) {
        shell.focusSearch()
        shell.setSearchTerm(term)
        shell.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
            object: shell.searchField))
    }
    type("match-a")
    let firstDeadline = Date().addingTimeInterval(2)
    while !shell.searchStatus.stringValue.contains("match-a") && Date() < firstDeadline { await Task.yield() }
    #expect(shell.searchStatus.stringValue.contains("match-a"))
    #expect(controller.session.selection.currentItemID == a.itemID)
    #expect(controller.inspector.name == a.url.lastPathComponent)
    type("unmatched")
    let emptyDeadline = Date().addingTimeInterval(2)
    while !shell.searchStatus.stringValue.contains("unmatched") && Date() < emptyDeadline { await Task.yield() }
    #expect(shell.searchEmptyVisible)
    #expect(controller.inspector.name == nil)
    type("")
    #expect(controller.session.selection.currentItemID == d.itemID)
    #expect(controller.inspector.name == d.url.lastPathComponent)
}

@MainActor @Test func issue136Combo2TabVisitsFooterAndInspectorInBothDirections() throws {
    _ = NSApplication.shared
    let unavailable = Task<AccessServices, Error> { throw CancellationError() }
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: unavailable,
        motionPolicy: MotionPolicy(source: KeyTestMotionSource()))
    let window = try #require(controller.window as? CommandWindow)
    defer { window.close() }
    let shell = try #require(window.contentView?.subviews.compactMap { $0 as? GridShellView }.first)
    let grid = try #require(shell.mainContent.subviews.compactMap { $0 as? GridBrowserView }.first)
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: URL(fileURLWithPath: "/tmp/issue136-combo2-tab"))
    let item = FolderEntry(url: root.url.appendingPathComponent("cat.jpg"), root: root)
    controller.session.beginBrowsing(items: [item.itemID], sourceVersion: .init(1), scrollAnchor: nil)
    controller.session.focus(item.itemID)
    controller.showGrid()
    #expect(controller.route(.inspector, from: .key))
    #expect(window.makeFirstResponder(grid.collectionView))
    let tab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
    let reverse = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: .shift, timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
    let divider = try #require(shell.toggleButton.nextKeyView)
    let footer: [NSView] = [shell.toggleButton, divider, shell.searchButton, shell.sortButton]
    for target in footer {
        window.sendEvent(tab)
        #expect(window.firstResponder === target)
        #expect(shell.searchField.isHidden)
    }
    window.sendEvent(tab)
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    #expect(controller.session.inspectorFocus.focus == .panel)
    #expect((window.firstResponder as? NSView)?.accessibilityIdentifier() == "inspector.close")
    window.sendEvent(tab)
    #expect(window.firstResponder === grid.collectionView)
    window.sendEvent(reverse)
    #expect((window.firstResponder as? NSView)?.accessibilityIdentifier() == "inspector.close")
    for target in footer.reversed() {
        window.sendEvent(reverse)
        #expect(window.firstResponder === target)
        #expect(shell.searchField.isHidden)
    }
    window.sendEvent(reverse)
    #expect(window.firstResponder === grid.collectionView)
    shell.focusSearch()
    #expect(!shell.searchField.isHidden)
    window.sendEvent(tab)
    #expect(window.firstResponder === shell.sortButton)
    shell.showSearchEmpty(true, term: "unmatched")
    window.sendEvent(tab)
    #expect(window.firstResponder === shell.clearSearchButton)
    window.sendEvent(tab)
    #expect(controller.session.inspectorFocus.focus == .panel)
    #expect((window.firstResponder as? NSView)?.accessibilityIdentifier() == "inspector.close")
    window.sendEvent(reverse)
    #expect(window.firstResponder === shell.clearSearchButton)
    window.sendEvent(reverse)
    #expect(window.firstResponder === shell.sortButton)
    window.sendEvent(reverse)
    #expect(shell.searchField.isHidden)
    #expect(window.firstResponder === shell.searchButton)
}

@MainActor private final class PanelResponder: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor @Test func inspectorEscapeRoutesWithTextFieldFocusedAndUnfocused() throws {
    _ = NSApplication.shared
    let unavailable = Task<AccessServices, Error> { throw CancellationError() }
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: unavailable,
        motionPolicy: MotionPolicy(source: KeyTestMotionSource()))
    let window = try #require(controller.window as? CommandWindow)
    defer { window.close() }
    let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 24))
    window.contentView?.addSubview(field)
    controller.session.setInspectorVisible(true)
    #expect(window.makeFirstResponder(field))
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false, keyCode: 53))
    #expect(window.consumeKey?(escape) == true)
    #expect(controller.session.inspectorFocus.focus == .canvas)

    let panel = PanelResponder(frame: .zero)
    window.contentView?.addSubview(panel)
    controller.session.updateFocus(.panel)
    #expect(window.makeFirstResponder(panel))
    #expect(window.consumeKey?(escape) == true)
    #expect(controller.session.inspectorFocus.focus == .canvas)
}
