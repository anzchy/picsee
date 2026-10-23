import AppKit
import SwiftUI
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func chromeToolsRenderAndActivateWithKeyboard() throws {
    _ = NSApplication.shared
    let effects = ChromeToolsHost()
    let clock = ChromeViewClock()
    let session = ViewerSession(clock: clock, host: effects)
    let overlay = ViewerChromeOverlay(frame: NSRect(x: 0, y: 0, width: 960, height: 640), session: session)
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 960, height: 640),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = overlay
    defer { window.close() }
    let first = try #require(overlay.tools.first)
    #expect(!first.mouseDownCanMoveWindow)
    #expect(!overlay.focusTool(reverse: false, entering: false))
    overlay.setToolsVisible(false)
    #expect(!overlay.focusTool(reverse: false, entering: true))
    overlay.setToolsVisible(true)
    #expect(overlay.focusTool(reverse: false, entering: true))
    first.keyDown(with: try chromeKey(49, " "))
    #expect(effects.opened == 1)
    first.keyDown(with: try chromeKey(0, "x"))
    #expect(effects.opened == 1)
    first.keyDown(with: try chromeKey(53, "\u{1b}"))
    #expect(session.inspectorFocus.focus == .canvas)
    #expect(first.focusRingMaskBounds == first.bounds)
    let bitmap = try #require(first.bitmapImageRepForCachingDisplay(in: first.bounds))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    first.drawFocusRingMask()
    NSGraphicsContext.restoreGraphicsState()
    effects.hasImage = false
    let disabled = try #require(overlay.tools.last)
    #expect(!disabled.becomeFirstResponder())
    effects.hasImage = true
    for dark in [false, true] {
        for id: CommandID in [.open, .inspector, .previous, .next, .zoomOut, .actualPixels, .zoomIn] {
            for mode in 0..<3 {
                if mode == 0 { session.beginCanvasImage() }
                if mode == 1 { CommandRouter().route(.actualPixels, from: .button, to: session) }
                if mode == 2 { session.reportCanvasZoom(1.25) }
                let renderer = ImageRenderer(content: ChromeToolFace(session: session, id: id)
                    .frame(width: 160, height: 40).background(DesignColor.canvasBackground.color)
                    .environment(\.colorScheme, dark ? .dark : .light))
                #expect(try #require(renderer.cgImage).width == 160)
            }
        }
    }
    let scale = overlay.tools[5]
    CommandRouter().route(.actualPixels, from: .button, to: session)
    #expect(scale.command == .fit)
    scale.activate()
    #expect(session.zoomMode == .fit)
    overlay.pointerMoved(NSPoint(x: -1, y: -1))
    #expect(overlay.tools[5].toolTip == "Actual Pixels (1)")
}
