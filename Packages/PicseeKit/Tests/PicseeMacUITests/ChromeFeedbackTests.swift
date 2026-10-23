import AppKit
import SwiftUI
import Testing
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func chromeNativePressAndFocusReachSharedComponentRendering() throws {
    _ = NSApplication.shared
    let host = ChromeRecallViewHost()
    let session = ViewerSession(host: host)
    let window = ChromeDispatchWindow(contentRect: NSRect(x: -20000, y: -20000, width: 800, height: 680),
        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: window.contentView!.bounds)
    let canvas = CanvasView(frame: content.bounds, session: session)
    let overlay = ViewerChromeOverlay(frame: content.bounds, session: session)
    content.addSubview(canvas); content.addSubview(overlay); window.contentView = content
    host.overlay = overlay; host.canvas = canvas; session.chromeHost = host
    overlay.linkKeyViews(to: canvas)
    defer { window.close() }
    window.makeKeyAndOrderFront(nil)
    for tool in [overlay.tools[4], overlay.tools[5]] {
        let visual = try #require(tool.subviews.first as? NSHostingView<ChromeToolFace>)
        window.makeFirstResponder(tool)
        #expect(visual.rootView.state.contains(.keyboardFocused))
        window.makeFirstResponder(canvas)
        #expect(!visual.rootView.state.contains(.keyboardFocused))
        window.sendEvent(try chromePointerEvent(.leftMouseDown, tool: tool, number: 1))
        let held = visual.rootView
        #expect(held.state.contains(.pressed))
        #expect(ComponentResolver.resolve(.icon, state: held.state, theme: .light).background == .selectionFill)
        let heldImage = try #require(ImageRenderer(content: held.frame(width: 160, height: 44)).cgImage)
        window.sendEvent(try chromePointerEvent(.leftMouseUp, tool: tool, number: 2))
        let released = visual.rootView
        #expect(!released.state.contains(.pressed))
        #expect(!released.state.contains(.keyboardFocused))
        #expect(ComponentResolver.resolve(.icon, state: released.state, theme: .light).background == nil)
        let releasedImage = try #require(ImageRenderer(content: released.frame(width: 160, height: 44)).cgImage)
        let heldData = try #require(heldImage.dataProvider?.data) as Data
        let releasedData = try #require(releasedImage.dataProvider?.data) as Data
        #expect(heldData != releasedData)
    }
}
