import AppKit
import Testing
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func chromeAccessibilityPressRoutesOnlyVisibleEnabledTools() throws {
    _ = NSApplication.shared
    let host = ChromeToolsHost()
    let session = ViewerSession(host: host)
    let overlay = ViewerChromeOverlay(frame: NSRect(x: 0, y: 0, width: 960, height: 640), session: session)
    let first = try #require(overlay.tools.first)
    #expect(first.accessibilityLabel() == "Open…")
    #expect(first.accessibilityPerformPress())
    #expect(host.opened == 1)
    overlay.setToolsVisible(false)
    #expect(!first.accessibilityPerformPress())
    #expect(host.opened == 1)
    overlay.setToolsVisible(true)
    host.hasImage = false
    #expect(try #require(overlay.tools.last).accessibilityPerformPress() == false)
    #expect(host.entries.isEmpty)
}
