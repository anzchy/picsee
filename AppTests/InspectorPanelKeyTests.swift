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
    let editor = try #require(shell.searchField.currentEditor())
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    #expect(window.firstResponder === editor)
    editor.insertText("cat")
    #expect(shell.searchField.stringValue == "cat")
    let commandI = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "i", charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34))
    window.sendEvent(commandI)
    #expect(!controller.session.inspectorFocus.isVisible)
    #expect(window.firstResponder === editor)
    #expect(shell.searchField.stringValue == "cat")
    window.sendEvent(commandI)
    #expect(controller.session.inspectorFocus.isVisible)
    #expect(window.firstResponder === editor)
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false, keyCode: 53))
    window.sendEvent(escape)
    #expect(shell.searchField.stringValue.isEmpty)
    #expect(controller.session.inspectorFocus.isVisible)
    shell.focusSearch()
    let tab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
        isARepeat: false, keyCode: 48))
    window.sendEvent(tab)
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    #expect(controller.session.inspectorFocus.focus == .panel)
    #expect(window.firstResponder !== shell.searchField.currentEditor())
    let reverseTab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: .shift, timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
        isARepeat: false, keyCode: 48))
    window.sendEvent(reverseTab)
    #expect(shell.searchField.currentEditor() === window.firstResponder)
    window.sendEvent(reverseTab)
    #expect(window.firstResponder !== shell.searchField.currentEditor())
    window.sendEvent(tab)
    #expect(shell.searchField.currentEditor() === window.firstResponder)
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
