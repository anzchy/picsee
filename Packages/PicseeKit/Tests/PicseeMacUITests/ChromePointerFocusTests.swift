import AppKit
import Testing
import PicseeApplication
@testable import PicseeMacUI

// Offscreen test application has no activation lifecycle; model the key-window query only.
@MainActor final class ChromeDispatchWindow: NSPanel {
    override var isKeyWindow: Bool { true }
}

@MainActor func chromePointerEvent(_ type: NSEvent.EventType, tool: NSView, number: Int) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type,
        location: tool.convert(NSPoint(x: tool.bounds.midX, y: tool.bounds.midY), to: nil),
        modifierFlags: [], timestamp: 0, windowNumber: tool.window!.windowNumber,
        context: nil, eventNumber: number, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
}

@Test @MainActor func chromePointerWindowDispatchReleasesFocusButTabKeepsLock() throws {
    _ = NSApplication.shared
    let clock = ChromeViewClock()
    let host = ChromeRecallViewHost()
    let session = ViewerSession(clock: clock, host: host)
    let window = ChromeDispatchWindow(contentRect: NSRect(x: -20000, y: -20000, width: 800, height: 680),
        styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: window.contentView!.bounds)
    let canvas = CanvasView(frame: content.bounds, session: session)
    let overlay = ViewerChromeOverlay(frame: content.bounds, session: session)
    content.addSubview(canvas); content.addSubview(overlay); window.contentView = content
    host.canvas = canvas; host.overlay = overlay; session.chromeHost = host
    overlay.linkKeyViews(to: canvas)
    defer { window.close() }
    window.makeKeyAndOrderFront(nil)
    for tool in overlay.tools.suffix(3) {
        session.activity(); window.makeFirstResponder(canvas)
        let event = try chromePointerEvent(.leftMouseDown, tool: tool, number: 1)
        window.sendEvent(event)
        #expect(session.chrome.locks.contains(.pointerPress))
        window.sendEvent(try chromePointerEvent(.leftMouseUp, tool: tool, number: 2))
        #expect(window.firstResponder === canvas)
        #expect(!session.chrome.locks.contains(.keyboardFocus))
        clock.now += 2.5; session.advanceChrome()
        #expect(session.chrome.visibility == .hidden)
    }
    session.tab(reverse: true)
    #expect(window.firstResponder === overlay.tools.last)
    clock.now += 100; session.advanceChrome()
    #expect(session.chrome.visibility == .locked([.keyboardFocus]))
}
