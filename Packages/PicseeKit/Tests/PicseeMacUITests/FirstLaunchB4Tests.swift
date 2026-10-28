import AppKit
import Testing
import PicseeApplication
@testable import PicseeMacUI

@MainActor private func b4View(_ id: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == id { return root }
    for child in root.subviews {
        if let found = b4View(id, in: child) { return found }
    }
    return nil
}

// Design: 9234b14, prototype-first-launch-b4-final.html SHA-256
// 8ba81de68f67911b0c3bdfbc90ff1513860ebf41d32c9b216fef6be8576d50da.
@Test @MainActor func p316B4FirstLaunchPresentsPinnedCentre() throws {
    let scene = StatesScene(width: 960)
    defer { scene.window.close() }
    scene.state.display(.empty)
    scene.state.layoutSubtreeIfNeeded()
    #expect(scene.state.textLines == ["Drop a photo folder here", "or press ⌘O", "Folder", "One or more images", "Common image formats"])
    #expect(scene.state.buttons.map(\.title) == ["Choose Folder…"])
    #expect(b4View("first-launch.stack", in: scene.state) != nil)
    #expect(b4View("first-launch.drop", in: scene.state) != nil)
    #expect(b4View("first-launch.print.alley", in: scene.state) != nil)
    #expect(b4View("first-launch.chip.images", in: scene.state) != nil)
}

@Test @MainActor func p316B4PrintFramesFollowPinnedSizeRule() throws {
    let scene = StatesScene()
    defer { scene.window.close() }
    let launch = try #require(scene.state.subviews.compactMap { $0 as? FirstLaunchView }.first)
    for (size, expectedScale, hidden) in [
        (NSSize(width: 960, height: 640), CGFloat(1), false),
        (NSSize(width: 800, height: 600), CGFloat(5.0 / 6.0), false),
        (NSSize(width: 1440, height: 900), CGFloat(1.25), false),
        (NSSize(width: 720, height: 480), CGFloat(0.75), false),
        (NSSize(width: 719, height: 479), CGFloat(0.75), true)
    ] {
        scene.window.setContentSize(size)
        scene.content.frame = NSRect(origin: .zero, size: size)
        scene.state.frame = scene.content.bounds
        launch.frame = scene.state.bounds
        launch.layoutSubtreeIfNeeded()
        let print = try #require(b4View("first-launch.print.alley", in: scene.state))
        #expect(abs(print.frame.width - 150 * max(0.8, expectedScale)) < 0.5)
        #expect(abs(print.frame.height - 110 * max(0.8, expectedScale)) < 0.5)
        #expect(print.isHidden == hidden)
        let centre = try #require(b4View("first-launch.stack", in: scene.state))
        #expect(centre.frame.size == NSSize(width: 220, height: 150))
    }
    for item in FirstLaunchLayout.prints(in: NSSize(width: 800, height: 600), centre: NSRect(x: 190, y: 130, width: 420, height: 308)) {
        #expect(item.push <= 60)
    }
}

@Test @MainActor func p316B4DecoderInitIsUnavailable() {
    #expect(FirstLaunchView(coder: NSCoder()) == nil)
}

@Test @MainActor func p316B4PinnedCSSMatchesRenderedCentre() throws {
    let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("B4PinnedDesign")
    let source = fixtureRoot.appendingPathComponent("a/b/c/d/source.swift").path
    let css = try PinnedDesign.page("b4-first-launch", source: source)
    let scene = StatesScene()
    defer { scene.window.close() }
    scene.state.layoutSubtreeIfNeeded()
    let stack = try #require(b4View("first-launch.stack", in: scene.state))
    let drop = try #require(b4View("first-launch.drop", in: scene.state))
    let heading = try #require(b4View("first-launch.heading", in: scene.state) as? NSTextField)
    try css.assertLength(Double(stack.frame.width), ".stack", "width", viewport: 960)
    try css.assertLength(Double(stack.frame.height), ".stack", "height", viewport: 960)
    try css.assertLength(Double(heading.font!.pointSize), ".drop h1", "font-size", viewport: 960)
    let margins = try css.edges(".drop", "margin", viewport: 960)
    #expect(Double(drop.frame.minX) == margins.left)
    #expect(Double(scene.state.bounds.maxX - drop.frame.maxX) == margins.right)
    #expect(Double(drop.frame.minY) == margins.bottom)
}

@Test @MainActor func p316B4LongestChipsRemainVisibleAt800() throws {
    let scene = StatesScene(width: 800)
    defer { scene.window.close() }
    let size = NSSize(width: 800, height: 600)
    scene.window.setContentSize(size)
    scene.content.frame = NSRect(origin: .zero, size: size)
    scene.state.frame = scene.content.bounds
    scene.state.layoutSubtreeIfNeeded()
    let launch = try #require(scene.state.subviews.compactMap { $0 as? FirstLaunchView }.first)
    for label in ["One or more images", "单张或多张图片"] {
        let chip = try #require(b4View("first-launch.chip.images", in: scene.state) as? NSTextField)
        chip.stringValue = label
        launch.needsLayout = true; launch.layoutSubtreeIfNeeded()
        let measured = ceil((label as NSString).size(withAttributes: [.font: chip.font!]).width)
        #expect(chip.frame.width >= measured + 18)
        #expect(chip.frame.minX >= 16 && chip.frame.maxX <= size.width - 16)
        #expect(chip.font?.pointSize == 12)
    }
}

@Test @MainActor func p316B4AllSixRenderedPrintsKeepCentreClear() throws {
    let scene = StatesScene()
    defer { scene.window.close() }
    scene.state.layoutSubtreeIfNeeded()
    let expected960: [(String, CGFloat, CGFloat, CGFloat)] = [
        ("alley", 70, 470, -7), ("lakeside", 601, 504, 4),
        ("hillside", 780, 239, 8), ("gate", 634, 14, -5),
        ("temple", 52, 30, 6), ("lakehouse", 26, 299, -4)
    ]
    for (name, x, y, _) in expected960 {
        let print = try #require(b4View("first-launch.print.\(name)", in: scene.state))
        #expect(!print.isHidden)
        #expect(abs(print.frame.minX - x) <= 0.5)
        #expect(abs(print.frame.minY - y) <= 0.5)
        #expect(abs(print.alphaValue - 0.3) < 0.001)
    }
    let launch = try #require(scene.state.subviews.compactMap { $0 as? FirstLaunchView }.first)
    for size in [NSSize(width: 800, height: 600), NSSize(width: 720, height: 480)] {
        scene.window.setContentSize(size)
        scene.content.frame = NSRect(origin: .zero, size: size)
        scene.state.frame = scene.content.bounds
        launch.frame = scene.state.bounds
        launch.layoutSubtreeIfNeeded()
        let stack = try #require(b4View("first-launch.stack", in: scene.state))
        let chip = try #require(b4View("first-launch.chip.images", in: scene.state))
        let centre = NSRect(x: size.width / 2 - 226, y: chip.frame.minY - 16,
                            width: 452, height: stack.frame.maxY - chip.frame.minY + 32)
        for (name, _, _, angle) in expected960 {
            let print = try #require(b4View("first-launch.print.\(name)", in: scene.state))
            let radians = abs(angle) * .pi / 180
            let halfW = ((print.frame.width + 12) * cos(radians) + (print.frame.height + 12) * sin(radians)) / 2
            let halfH = ((print.frame.width + 12) * sin(radians) + (print.frame.height + 12) * cos(radians)) / 2
            let rotated = NSRect(x: print.frame.midX - halfW, y: print.frame.midY - halfH,
                                 width: 2 * halfW, height: 2 * halfH)
            if !print.isHidden { #expect(!rotated.intersects(centre), "\(name) overlaps centre at \(size)") }
        }
    }
}
