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

@Test @MainActor func chromeFloatingPanelsSeparateFromCanvasAcrossAppearances() throws {
    _ = NSApplication.shared
    let overlay = ViewerChromeOverlay(frame: NSRect(x: 0, y: 0, width: 1280, height: 800),
        session: ViewerSession())
    overlay.refresh(filename: "a.png")
    let initialWidth = overlay.groups[1].frame.width
    var lightOpacity: Float = 0

    for (index, appearance) in [NSAppearance.Name.aqua, .darkAqua, .aqua].enumerated() {
        overlay.appearance = NSAppearance(named: appearance)
        overlay.viewDidChangeEffectiveAppearance()
        for group in overlay.groups {
            let layer = try #require(group.layer)
            #expect(layer.shadowColor != nil)
            #expect(layer.shadowOpacity > 0.1)
            #expect(layer.shadowOpacity < 0.4)
            #expect(layer.shadowRadius > 0)
            #expect(layer.shadowOffset.height < 0)
            #expect(layer.masksToBounds == false)
            let path = try #require(layer.shadowPath)
            #expect(path.boundingBoxOfPath == group.bounds)
        }
        let opacity = try #require(overlay.groups[0].layer).shadowOpacity
        if index == 0 { lightOpacity = opacity }
        if index == 1 { #expect(opacity > lightOpacity) }
        if index == 2 { #expect(opacity == lightOpacity) }
    }

    overlay.refresh(filename: String(repeating: "long-filename-", count: 30) + ".png")
    #expect(overlay.groups[1].frame.width > initialWidth)
    for group in overlay.groups {
        let layer = try #require(group.layer)
        let path = try #require(layer.shadowPath)
        #expect(path.boundingBoxOfPath == group.bounds)
    }
    overlay.setFrameSize(NSSize(width: 800, height: 680))
    for group in overlay.groups {
        let layer = try #require(group.layer)
        let path = try #require(layer.shadowPath)
        #expect(path.boundingBoxOfPath == group.bounds)
    }
}
