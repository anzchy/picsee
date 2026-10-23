import AppKit
import Testing
import PicseeApplication
@testable import PicseeMacUI

@MainActor func chromeMouse(_ tool: NSView, _ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: tool.convert(point, to: nil), modifierFlags: [],
        timestamp: 0, windowNumber: tool.window?.windowNumber ?? 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
}

@Test @MainActor func chromeLocksViewHoverPressAndOutsideRelease() throws {
    _ = NSApplication.shared
    let clock = ChromeViewClock()
    let host = ChromeToolsHost()
    let session = ViewerSession(clock: clock, host: host)
    let overlay = ViewerChromeOverlay(frame: NSRect(x: 0, y: 0, width: 960, height: 640), session: session)
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 960, height: 640),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = overlay
    defer { window.close() }
    let tool = try #require(overlay.tools.first)
    overlay.pointerMoved(NSPoint(x: 30, y: 30))
    #expect(session.chrome.locks == [.pointerHover])
    tool.mouseDown(with: try chromeMouse(tool, .leftMouseDown, NSPoint(x: 10, y: 10)))
    #expect(session.chrome.locks == [.pointerHover, .pointerPress])
    clock.now = 100; session.advanceChrome()
    overlay.pointerMoved(NSPoint(x: 480, y: 320))
    #expect(session.chrome.visibility == .locked([.pointerPress]))
    tool.mouseUp(with: try chromeMouse(tool, .leftMouseUp, NSPoint(x: -10, y: -10)))
    #expect(host.opened == 0)
    #expect(session.nextHideDeadline == 102.5)
    tool.mouseDown(with: try chromeMouse(tool, .leftMouseDown, NSPoint(x: 10, y: 10)))
    tool.mouseUp(with: try chromeMouse(tool, .leftMouseUp, NSPoint(x: 10, y: 10)))
    #expect(host.opened == 1)
    host.hasImage = false
    let disabled = try #require(overlay.tools.last)
    disabled.mouseDown(with: try chromeMouse(disabled, .leftMouseDown, NSPoint(x: 10, y: 10)))
    disabled.mouseUp(with: try chromeMouse(disabled, .leftMouseUp, NSPoint(x: 10, y: 10)))
    #expect(host.entries.isEmpty)
    #expect(session.chrome.locks.isEmpty)
}
