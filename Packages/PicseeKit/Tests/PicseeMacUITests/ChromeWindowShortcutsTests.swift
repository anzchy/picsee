import AppKit
import Testing
import PicseeApplication
@testable import PicseeMacUI

@MainActor private final class ChromeCloseProbe: NSObject, NSWindowDelegate {
    var requests = 0
    func windowShouldClose(_ sender: NSWindow) -> Bool { requests += 1; return false }
}

@Test @MainActor func chromeWindowCloseShortcutWorksWithHiddenAndVisibleControls() throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 960, height: 640),
        styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let probe = ChromeCloseProbe(); window.delegate = probe
    let session = ViewerSession()
    let content = NSView(frame: window.contentView!.bounds)
    let canvas = CanvasView(frame: content.bounds, session: session)
    let overlay = ViewerChromeOverlay(frame: content.bounds, session: session)
    content.addSubview(canvas); content.addSubview(overlay); window.contentView = content
    defer { window.close(); withExtendedLifetime(probe) {} }
    let close = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "w", charactersIgnoringModifiers: "w",
        isARepeat: false, keyCode: 13))
    for visible in [false, true] {
        overlay.setToolsVisible(visible)
        #expect(window.performKeyEquivalent(with: close))
    }
    #expect(probe.requests == 2)
    let other = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "W", charactersIgnoringModifiers: "w",
        isARepeat: false, keyCode: 13))
    #expect(!overlay.performKeyEquivalent(with: other))
    #expect(probe.requests == 2)
    let detached = ViewerChromeOverlay(frame: .zero, session: session)
    #expect(!detached.performKeyEquivalent(with: close))
}
