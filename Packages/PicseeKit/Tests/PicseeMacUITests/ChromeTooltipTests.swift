import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func chromeTooltipsNameCommandsAndRenderArrowShortcuts() throws {
    _ = NSApplication.shared
    let effects = ChromeToolsHost()
    let session = ViewerSession(host: effects)
    let overlay = ViewerChromeOverlay(frame: NSRect(x: 0, y: 0, width: 640, height: 680), session: session)
    #expect(overlay.tools.map(\.toolTip) == ["Open… (⌘O)", "Show image information (⌘I)", "Previous image (←)", "Next image (→)", "Zoom out (-)", "Actual Pixels (1)", "Zoom in (+)"])
    CommandRouter().route(.actualPixels, from: .button, to: session)
    overlay.refresh()
    #expect(overlay.tools[5].toolTip == "Fit window (0)")
    overlay.pointerMoved(NSPoint(x: -1, y: -1))
    #expect(overlay.tools[5].toolTip == "Fit window (0)")
    #expect(CommandID.previous.shortcutHint == "\u{f702}")
    #expect(CommandID.next.shortcutHint == "\u{f703}")
}
