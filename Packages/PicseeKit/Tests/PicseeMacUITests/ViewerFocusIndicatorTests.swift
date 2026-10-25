import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func viewerCanvasKeepsDocumentedKeyboardFocusOutlineAfterGridPreview() {
    _ = NSApplication.shared
    let session = ViewerSession()
    let item = ItemID.ephemeral(UUID())
    session.beginBrowsing(items: [item], sourceVersion: .init(1), scrollAnchor: item)
    #expect(CommandRouter().route(.preview, from: .key, to: session))
    let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), session: session)
    canvas.focusRingType = .exterior
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
        styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = canvas
    #expect(window.makeFirstResponder(canvas))
    #expect(session.mode == .viewing)
    #expect(window.firstResponder === canvas)
    #expect(canvas.focusRingType == .exterior)
    #expect(canvas.focusRingMaskBounds == canvas.bounds.insetBy(dx: 3, dy: 3))
    canvas.drawFocusRingMask()
}
