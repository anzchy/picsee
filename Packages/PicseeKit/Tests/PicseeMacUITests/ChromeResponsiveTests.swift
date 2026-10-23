import AppKit
import Testing
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func chromeResponsiveResizeKeepsEveryControlHitDistinct() throws {
    _ = NSApplication.shared
    let effects = ChromeToolsHost()
    let session = ViewerSession(host: effects)
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 960, height: 640),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let overlay = ViewerChromeOverlay(frame: window.contentView!.bounds, session: session)
    overlay.autoresizingMask = [.width, .height]; window.contentView = overlay
    defer { window.close() }
    overlay.refresh(filename: String(repeating: "long-filename-", count: 30) + ".png")
    // Include the reported 640pt failure and the 800×680 design minimum case.
    for width: CGFloat in [960, 640, 800, 610, 480, 334, 300, 238, 960] {
        window.setContentSize(NSSize(width: width, height: 680))
        for (index, group) in overlay.groups.enumerated() {
            #expect(overlay.bounds.contains(group.frame))
            for other in overlay.groups.dropFirst(index + 1) { #expect(!group.frame.intersects(other.frame)) }
        }
        for tool in overlay.tools where tool.acceptsFirstResponder {
            let centre = tool.convert(NSPoint(x: tool.bounds.midX, y: tool.bounds.midY), to: overlay)
            #expect(overlay.hitTest(centre) === tool)
        }
    }
    ChromeTitlebarPolicy.apply(to: window, visible: true, fullScreen: false)
    #expect(window.contentMinSize == NSSize(width: 238, height: 168))
}
