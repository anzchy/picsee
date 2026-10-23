import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func chromeAccessibleScaleAndFilenameUpdateWithoutDuplicateActions() throws {
    _ = NSApplication.shared
    let effects = ChromeToolsHost()
    let session = ViewerSession(host: effects)
    let overlay = ViewerChromeOverlay(frame: NSRect(x: 0, y: 0, width: 640, height: 680), session: session)
    let filename = String(repeating: "full-long-name-", count: 30) + ".png"
    let scale = overlay.tools[5]
    for (mode, value) in [(0, "Fit window"), (1, "1:1 · 100%"), (2, "125%")] {
        if mode == 0 { session.beginCanvasImage() }
        if mode == 1 { CommandRouter().route(.actualPixels, from: .button, to: session) }
        if mode == 2 { session.reportCanvasZoom(1.25) }
        overlay.refresh(filename: filename)
        overlay.setToolsVisible(true)
        #expect(scale.accessibilityValue() as? String == value)
        #expect(scale.accessibilityChildren()?.isEmpty == true)
        let children = try #require(overlay.accessibilityChildren())
        #expect(children.count == 8)
        let text = try #require(children.compactMap { $0 as? NSTextField }.first)
        #expect(text.accessibilityRole() == .staticText)
        #expect(text.accessibilityValue() as? String == filename)
        overlay.setToolsVisible(false)
        #expect(overlay.accessibilityChildren()?.isEmpty == true)
        #expect(text.isHiddenOrHasHiddenAncestor)
    }
    overlay.refresh()
    overlay.setToolsVisible(true)
    #expect(overlay.accessibilityChildren()?.count == 7)
}
