import AppKit
import Testing
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func chromeGroupLayersResolveLightDarkAndBack() throws {
    _ = NSApplication.shared
    let overlay = ViewerChromeOverlay(frame: NSRect(x: 0, y: 0, width: 640, height: 680), session: ViewerSession())
    let cases: [(NSAppearance.Name, [CGFloat])] = [(.aqua, [1, 1, 1, 1]), (.darkAqua, [20/255, 24/255, 33/255, 1]), (.aqua, [1, 1, 1, 1])]
    for (name, expected) in cases {
        overlay.appearance = try #require(NSAppearance(named: name))
        overlay.viewDidChangeEffectiveAppearance()
        for group in overlay.groups {
            let cg = try #require(group.layer?.backgroundColor)
            let color = try #require(NSColor(cgColor: cg)?.usingColorSpace(.sRGB))
            #expect(abs(color.redComponent - expected[0]) < 0.00001)
            #expect(abs(color.greenComponent - expected[1]) < 0.00001)
            #expect(abs(color.blueComponent - expected[2]) < 0.00001)
            #expect(color.alphaComponent == 1)
        }
    }
}
