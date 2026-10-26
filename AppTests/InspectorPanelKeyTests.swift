import AppKit
import Testing
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@MainActor private final class KeyTestMotionSource: ReduceMotionSource {
    var reduceMotion = false
    var onChange: (@MainActor () -> Void)?
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
