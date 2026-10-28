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

@MainActor private func b4RenderedRing(_ view: NSView, in root: NSView) throws -> NSRect {
    let layer = try #require(view.layer)
    _ = root
    let ring = try #require(layer.sublayers?.last)
    let tilt = layer.affineTransform()
    let extraX = (ring.frame.width - layer.bounds.width) * abs(tilt.a) +
        (ring.frame.height - layer.bounds.height) * abs(tilt.c)
    let extraY = (ring.frame.width - layer.bounds.width) * abs(tilt.b) +
        (ring.frame.height - layer.bounds.height) * abs(tilt.d)
    return layer.frame.insetBy(dx: -extraX / 2, dy: -extraY / 2)
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
    let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("B4PinnedDesign")
    let css = try PinnedDesign.page("b4-first-launch", source: fixtureRoot.appendingPathComponent("a/b/c/d/source.swift").path)
    let rule = try css.b4SizeRule()
    let scene = StatesScene()
    defer { scene.window.close() }
    let launch = try #require(scene.state.subviews.compactMap { $0 as? FirstLaunchView }.first)
    for size in [
        NSSize(width: 960, height: 640), NSSize(width: 800, height: 600),
        NSSize(width: 1440, height: 900), NSSize(width: 720, height: 480),
        NSSize(width: 719, height: 479)
    ] {
        let expectedScale = CGFloat(min(rule.maxScale, max(rule.minScale,
            min(Double(size.width) / rule.width, Double(size.height) / rule.height))))
        let hidden = Double(size.width) < rule.hideWidth || Double(size.height) < rule.hideHeight
        scene.window.setContentSize(size)
        scene.content.frame = NSRect(origin: .zero, size: size)
        scene.state.frame = scene.content.bounds
        launch.frame = scene.state.bounds
        launch.layoutSubtreeIfNeeded()
        let print = try #require(b4View("first-launch.print.alley", in: scene.state))
        #expect(abs(print.frame.width - CGFloat(rule.printWidth) * expectedScale) < 0.5)
        #expect(abs(print.frame.height - CGFloat(rule.printHeight) * expectedScale) < 0.5)
        #expect(print.isHidden == hidden)
        let centre = try #require(b4View("first-launch.stack", in: scene.state))
        #expect(centre.frame.size == NSSize(width: 220, height: 150))
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
    let chip = try #require(b4View("first-launch.chip.images", in: scene.state) as? NSTextField)
    let firstChip = try #require(b4View("first-launch.chip.folder", in: scene.state))
    let chipPadding = try css.edges(".chips span", "padding", viewport: 960)
    let chipTextWidth = ceil((chip.stringValue as NSString).size(withAttributes: [.font: chip.font!]).width)
    #expect(abs(Double(chip.frame.width - chipTextWidth) - chipPadding.left - chipPadding.right) <= 1)
    try css.assertLength(Double(chip.font!.pointSize), ".chips span", "font-size", viewport: 960)
    try css.assertLength(Double(chip.frame.minX - firstChip.frame.maxX), ".chips", "gap", viewport: 960)
    let margins = try css.edges(".drop", "margin", viewport: 960)
    #expect(Double(drop.frame.minX) == margins.left)
    #expect(Double(scene.state.bounds.maxX - drop.frame.maxX) == margins.right)
    #expect(Double(drop.frame.minY) == margins.bottom)
}

@Test @MainActor func p316B4LongestChipsRemainVisibleAt800() throws {
    let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("B4PinnedDesign")
    let css = try PinnedDesign.page("b4-first-launch", source: fixtureRoot.appendingPathComponent("a/b/c/d/source.swift").path)
    let padding = try css.edges(".chips span", "padding", viewport: 800)
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
        #expect(chip.frame.width >= measured + CGFloat(padding.left + padding.right))
        #expect(chip.frame.minX >= 16 && chip.frame.maxX <= size.width - 16)
        #expect(chip.font?.pointSize == 12)
    }
}

@Test @MainActor func p316B4AllSixRenderedPrintsKeepCentreClear() throws {
    let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("B4PinnedDesign")
    let css = try PinnedDesign.page("b4-first-launch", source: fixtureRoot.appendingPathComponent("a/b/c/d/source.swift").path)
    let scene = StatesScene()
    defer { scene.window.close() }
    scene.state.layoutSubtreeIfNeeded()
    let specs = try css.b4PrintSpecs()
    let rule = try css.b4SizeRule()
    let expected960: [(String, CGFloat, CGFloat, CGFloat)] = specs.map { spec in
        let a = CGFloat(spec.a), b = CGFloat(spec.b)
        let x: CGFloat, y: CGFloat
        switch spec.anchor {
        case "TL": x = a; y = 640 - b - 110
        case "T": x = 480 + a - 75; y = 640 - b - 110
        case "R": x = 960 - a - 150; y = 320 - b - 55
        case "BR": x = 960 - a - 150; y = b
        case "BL": x = a; y = b
        default: x = a; y = 320 - b - 55
        }
        return (spec.name, x, y, CGFloat(spec.angle))
    }
    for (name, x, y, _) in expected960 {
        let print = try #require(b4View("first-launch.print.\(name)", in: scene.state))
        #expect(!print.isHidden)
        #expect(abs(print.frame.minX - x) <= 0.5)
        #expect(abs(print.frame.minY - y) <= 0.5)
        #expect(abs(print.alphaValue - (try css.b4PrintOpacity("light"))) < 0.001)
        let ring = try b4RenderedRing(print, in: scene.state)
        #expect(abs(ring.midX - print.frame.midX) < 0.5)
        #expect(abs(ring.midY - print.frame.midY) < 0.5)
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
            let spec = try #require(specs.first { $0.name == name })
            let scale = CGFloat(min(rule.maxScale, max(rule.minScale,
                min(Double(size.width) / rule.width, Double(size.height) / rule.height))))
            let a = CGFloat(spec.a) * scale, b = CGFloat(spec.b) * scale
            let pw = CGFloat(rule.printWidth) * scale, ph = CGFloat(rule.printHeight) * scale
            let base: NSPoint
            switch spec.anchor {
            case "TL": base = NSPoint(x: a, y: size.height - b - ph)
            case "TR": base = NSPoint(x: size.width - a - pw, y: size.height - b - ph)
            case "BL": base = NSPoint(x: a, y: b)
            case "BR": base = NSPoint(x: size.width - a - pw, y: b)
            case "L": base = NSPoint(x: a, y: size.height / 2 - b - ph / 2)
            case "R": base = NSPoint(x: size.width - a - pw, y: size.height / 2 - b - ph / 2)
            case "T": base = NSPoint(x: size.width / 2 + a - pw / 2, y: size.height - b - ph)
            default: base = NSPoint(x: size.width / 2 + a - pw / 2, y: b)
            }
            let pushX = abs(print.frame.minX - base.x), pushY = abs(print.frame.minY - base.y)
            #expect(max(pushX, pushY) <= CGFloat(rule.maxPush) + 0.5)
            #expect(min(pushX, pushY) <= 0.5)
            let radians = abs(angle) * .pi / 180
            let halfW = ((print.frame.width + 12) * cos(radians) + (print.frame.height + 12) * sin(radians)) / 2
            let halfH = ((print.frame.width + 12) * sin(radians) + (print.frame.height + 12) * cos(radians)) / 2
            let rotated = try b4RenderedRing(print, in: scene.state)
            #expect(abs(rotated.width - 2 * halfW) < 0.5)
            #expect(abs(rotated.height - 2 * halfH) < 0.5)
            if !print.isHidden { #expect(!rotated.intersects(centre), "\(name) overlaps centre at \(size)") }
        }
    }
}

@Test @MainActor func p316B4TiltUsesPinnedCentrePivot() throws {
    let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("B4PinnedDesign")
    let css = try PinnedDesign.page("b4-first-launch", source: fixtureRoot.appendingPathComponent("a/b/c/d/source.swift").path)
    let alleyAngle = try #require(css.b4PrintSpecs().first { $0.name == "alley" }?.angle)
    let scene = StatesScene()
    defer { scene.window.close() }
    scene.state.layoutSubtreeIfNeeded()
    let print = try #require(b4View("first-launch.print.alley", in: scene.state))
    let layer = try #require(print.layer)
    let radians = abs(CGFloat(alleyAngle)) * .pi / 180
    let expectedWidth = print.frame.width * cos(radians) + print.frame.height * sin(radians)
    let expectedHeight = print.frame.width * sin(radians) + print.frame.height * cos(radians)
    #expect(abs(layer.frame.midX - print.frame.midX) < 0.5)
    #expect(abs(layer.frame.midY - print.frame.midY) < 0.5)
    #expect(abs(layer.frame.width - expectedWidth) < 0.5)
    #expect(abs(layer.frame.height - expectedHeight) < 0.5)
    // CSS negative rotation becomes positive in AppKit's upward Y axis.
    let corner = layer.convert(CGPoint(x: 0, y: layer.bounds.height), to: layer.superlayer)
    #expect(corner.x < print.frame.minX)
}

@Test @MainActor func p316B4FrontPhotoFollowsPinnedDragTransform() throws {
    let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("B4PinnedDesign")
    let css = try PinnedDesign.page("b4-first-launch", source: fixtureRoot.appendingPathComponent("a/b/c/d/source.swift").path)
    let target = try css.b4FrontDrag()
    let scene = StatesScene()
    defer { scene.window.close() }
    let launch = try #require(scene.state.subviews.compactMap { $0 as? FirstLaunchView }.first)
    let stack = try #require(b4View("first-launch.stack", in: scene.state))
    let front = try #require(stack.subviews.last)
    launch.setDragActive(true); launch.layoutSubtreeIfNeeded()
    let frame = try #require(front.layer?.frame)
    #expect(abs(frame.width - stack.bounds.width * CGFloat(target.scale)) < 0.5)
    #expect(abs(frame.height - stack.bounds.height * CGFloat(target.scale)) < 0.5)
    #expect(abs(frame.midX - stack.frame.midX) < 0.5)
    #expect(abs(frame.midY - stack.frame.midY + CGFloat(target.dy)) < 0.5)
    launch.reduceMotionOverride = true
    launch.setDragActive(false); launch.setDragActive(true); launch.layoutSubtreeIfNeeded()
    let reduced = try #require(front.layer?.frame)
    #expect(abs(reduced.width - stack.bounds.width) < 0.5)
    #expect(abs(reduced.midY - stack.frame.midY) < 0.5)
}

@Test @MainActor func p316B4SideCardsComposePinnedRotateTranslate() throws {
    let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("B4PinnedDesign")
    let css = try PinnedDesign.page("b4-first-launch", source: fixtureRoot.appendingPathComponent("a/b/c/d/source.swift").path)
    let scene = StatesScene()
    defer { scene.window.close() }
    let launch = try #require(scene.state.subviews.compactMap { $0 as? FirstLaunchView }.first)
    let stack = try #require(b4View("first-launch.stack", in: scene.state))
    for active in [false, true] {
        launch.setDragActive(active); launch.layoutSubtreeIfNeeded()
        for index in 1...2 {
            let selector = "\(active ? ".over " : "").stack .f:nth-child(\(index))"
            let pinned = try css.b4CardTransform(selector)
            let native = CGAffineTransform(rotationAngle: -CGFloat(pinned.angle) * .pi / 180)
                .translatedBy(x: CGFloat(pinned.dx), y: -CGFloat(pinned.dy))
            let card = try #require(stack.subviews[index - 1].layer)
            #expect(abs(card.frame.midX - stack.frame.midX - native.tx) < 0.5)
            #expect(abs(card.frame.midY - stack.frame.midY - native.ty) < 0.5)
            #expect(abs(card.affineTransform().b - sin(-CGFloat(pinned.angle) * .pi / 180)) < 0.001)
        }
    }
}

@Test @MainActor func p316B4PinnedCentreSpacingAndButtonGroup() throws {
    let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("B4PinnedDesign")
    let css = try PinnedDesign.page("b4-first-launch", source: fixtureRoot.appendingPathComponent("a/b/c/d/source.swift").path)
    let scene = StatesScene()
    defer { scene.window.close() }
    scene.state.layoutSubtreeIfNeeded()
    let stack = try #require(b4View("first-launch.stack", in: scene.state))
    let heading = try #require(b4View("first-launch.heading", in: scene.state))
    let button = try #require(scene.state.buttons.first)
    let shortcut = try #require(b4View("first-launch.shortcut", in: scene.state))
    let key = try #require(b4View("first-launch.shortcut-key", in: scene.state) as? NSTextField)
    let chip = try #require(b4View("first-launch.chip.images", in: scene.state))
    let group = button.frame.union(shortcut.frame).union(key.frame)
    #expect(abs(group.midX - stack.frame.midX) <= 1)
    #expect(abs(group.midY - button.frame.midY) <= 1)
    let gap = try css.length(".centre", "gap", viewport: 960)
    let stackMargin = try css.length(".stack", "margin-bottom", viewport: 960)
    #expect(abs(Double(stack.frame.minY - heading.frame.maxY) - stackMargin - gap) <= 1)
    #expect(abs(Double(heading.frame.minY - button.frame.maxY) - gap) <= 1)
    #expect(abs(Double(button.frame.minY - chip.frame.maxY) - gap) <= 1)
    try css.assertLength(Double(shortcut.frame.minX - button.frame.maxX), ".sub", "gap", viewport: 960, tolerance: 1)
    let padding = try css.edges(".btn", "padding", viewport: 960)
    let titleWidth = ceil((button.title as NSString).size(withAttributes: [.font: button.font!]).width)
    #expect(abs(Double(button.frame.width - titleWidth) - padding.left - padding.right) <= 2)
    try css.assertLength(Double(key.font!.pointSize), "kbd", "font-size", viewport: 960)
    #expect(abs(key.frame.midY - button.frame.midY) <= 1)
}

@Test @MainActor func p316B4ChipTextIsVerticallyCentred() throws {
    let scene = StatesScene()
    defer { scene.window.close() }
    scene.state.layoutSubtreeIfNeeded()
    let chip = try #require(b4View("first-launch.chip.images", in: scene.state) as? CenteredChipLabel)
    #expect(abs(chip.textDrawRect.midY - chip.bounds.midY) <= 1)
}
