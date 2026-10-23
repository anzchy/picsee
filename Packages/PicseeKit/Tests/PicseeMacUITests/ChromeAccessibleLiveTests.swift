import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func chromeAccessibleValueTracksSessionWithoutHostRefresh() throws {
    _ = NSApplication.shared
    let effects = ChromeToolsHost()
    let session = ViewerSession(host: effects)
    let overlay = ViewerChromeOverlay(frame: NSRect(x: 0, y: 0, width: 640, height: 680), session: session)
    let scale = overlay.tools[5]
    #expect(scale.accessibilityValue() as? String == "Fit window")
    CommandRouter().route(.actualPixels, from: .button, to: session)
    #expect(scale.accessibilityValue() as? String == "1:1 · 100%")
    session.reportCanvasZoom(1.25)
    #expect(scale.accessibilityValue() as? String == "125%")
    CommandRouter().route(.fit, from: .button, to: session)
    #expect(scale.accessibilityValue() as? String == "Fit window")
    for tool in overlay.tools where tool !== scale { #expect(tool.accessibilityValue() == nil) }
}
