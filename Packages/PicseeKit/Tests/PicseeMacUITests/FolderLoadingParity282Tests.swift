import AppKit
import Testing
@testable import PicseeMacUI

@MainActor private func issue282StateView(_ id: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == id { return root }
    for child in root.subviews {
        if let match = issue282StateView(id, in: child) { return match }
    }
    return nil
}

@MainActor private func issue282Frame(_ id: String, in host: ViewerStateHost) throws -> NSRect {
    let view = try #require(issue282StateView(id, in: host))
    return host.convert(view.bounds, from: view)
}

private func issue282PathEndpoints(_ path: CGPath) -> (start: CGPoint, end: CGPoint)? {
    var start: CGPoint?
    var end: CGPoint?
    path.applyWithBlock { element in
        let point: CGPoint?
        switch element.pointee.type {
        case .moveToPoint, .addLineToPoint:
            point = element.pointee.points[0]
        case .addQuadCurveToPoint:
            point = element.pointee.points[1]
        case .addCurveToPoint:
            point = element.pointee.points[2]
        case .closeSubpath:
            point = nil
        @unknown default:
            point = nil
        }
        guard let point else { return }
        if start == nil { start = point }
        end = point
    }
    guard let start, let end else { return nil }
    return (start, end)
}

@Test @MainActor func issue282ReadingContentMatchesPinnedFramesAndCancelStyle() throws {
    for (appearanceName, designAppearance) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        let design = try PinnedDesign.page("folder-loading", appearance: designAppearance)
        let scene = StatesScene(width: 1084)
        defer { scene.window.close() }
        scene.state.appearance = NSAppearance(named: appearanceName)
        scene.state.display(.readingFolder)
        scene.state.layoutSubtreeIfNeeded()
        let progress = try issue282Frame("state.folder-progress", in: scene.state)
        let headingView = try #require(issue282StateView("state.folder-title", in: scene.state) as? NSTextField)
        let heading = try issue282Frame("state.folder-title", in: scene.state)
        let subtitleView = try #require(issue282StateView("state.folder-subtitle", in: scene.state) as? NSTextField)
        let subtitle = try issue282Frame("state.folder-subtitle", in: scene.state)
        let cancel = try #require(issue282StateView("state.cancel-folder", in: scene.state) as? NSButton)

        // folder-loading.html: .mock-progress is 28x28; h2 adds 18px after its 8px bottom margin.
        #expect(progress.size == NSSize(width: 28, height: 28))
        #expect(progress.minY - heading.maxY == 26)
        #expect(headingView.font?.pointSize == 16)
        #expect(headingView.font == .systemFont(ofSize: 16, weight: .medium))
        #expect(headingView.stringValue == "Reading Folder…")
        // folder-loading.html: .empty-state p is 13px with margin-top 9px and line-height 1.7.
        #expect(subtitleView.font?.pointSize == 13)
        #expect(abs(subtitle.height - 22.1) < 0.01)
        #expect(heading.minY - subtitle.maxY == 9)
        #expect(subtitleView.stringValue == "Looking for images to browse. Please wait.")
        // folder-loading.html: .text-button is borderless, accent-text, padding 8 and margin-top 8.
        #expect(!cancel.isBordered)
        #expect(cancel.frame.height >= 30)
        #expect(subtitle.minY - cancel.frame.maxY == 8)
        #expect(cancel.acceptsFirstResponder)
        #expect(cancel.accessibilityLabel() == "Cancel Reading")
        var tint: NSColor?
        cancel.effectiveAppearance.performAsCurrentDrawingAppearance {
            tint = cancel.contentTintColor?.usingColorSpace(.sRGB)
        }
        let expected = try design.color(".text-button", "color", viewport: 1280)
        let actual = try #require(tint)
        #expect(abs(actual.redComponent - expected.red) < 0.01)
        #expect(abs(actual.greenComponent - expected.green) < 0.01)
        #expect(abs(actual.blueComponent - expected.blue) < 0.01)

        let frames = [progress, heading, subtitle, cancel.frame]
        let union = frames.dropFirst().reduce(progress) { $0.union($1) }
        #expect(abs(union.midX - scene.state.bounds.midX) <= 1)
        #expect(abs(union.midY - scene.state.bounds.midY) <= 1)
        var restored = 0
        scene.state.onCancelFolderReading = { restored += 1 }
        cancel.performClick(nil)
        #expect(restored == 1)
    }
}

@Test @MainActor func issue282ReadingRingUsesAccentSegmentAndStopsForReduceMotion() throws {
    for (page, appearanceName) in [("folder-loading", NSAppearance.Name.aqua), ("folder-loading", .darkAqua)] {
        let design = try PinnedDesign.page(page, appearance: appearanceName == .aqua ? "light" : "dark")
        let view = ReadingProgressView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        view.appearance = NSAppearance(named: appearanceName)
        view.reduceMotion = { false }
        view.start()
        // folder-loading.html: one 28x28 border box, 2px stroke, with its top quarter in accent.
        #expect(view.dividerLayer.lineWidth == 2)
        #expect(view.accentLayer.lineWidth == 2)
        #expect(view.accentLayer.lineCap == .butt)
        let dividerPath = try #require(view.dividerLayer.path)
        let accentPath = try #require(view.accentLayer.path)
        let dividerBounds = dividerPath.boundingBoxOfPath
        #expect(dividerBounds == CGRect(x: 1, y: 1, width: 26, height: 26))
        let center = CGPoint(x: dividerBounds.midX, y: dividerBounds.midY)
        #expect(center == CGPoint(x: 14, y: 14))
        let accentEndpoints = try #require(issue282PathEndpoints(accentPath))
        let expectedStart = CGPoint(x: center.x + 13 * cos(CGFloat.pi / 4),
                                    y: center.y + 13 * sin(CGFloat.pi / 4))
        let expectedEnd = CGPoint(x: center.x + 13 * cos(3 * CGFloat.pi / 4),
                                  y: center.y + 13 * sin(3 * CGFloat.pi / 4))
        #expect(abs(accentEndpoints.start.x - expectedStart.x) < 0.0001)
        #expect(abs(accentEndpoints.start.y - expectedStart.y) < 0.0001)
        #expect(abs(accentEndpoints.end.x - expectedEnd.x) < 0.0001)
        #expect(abs(accentEndpoints.end.y - expectedEnd.y) < 0.0001)
        #expect(abs(hypot(accentEndpoints.start.x - center.x, accentEndpoints.start.y - center.y) - 13) < 0.0001)
        #expect(abs(hypot(accentEndpoints.end.x - center.x, accentEndpoints.end.y - center.y) - 13) < 0.0001)
        let dividerColor = try #require(view.dividerLayer.strokeColor)
        let divider = try #require(NSColor(cgColor: dividerColor)?.usingColorSpace(.sRGB))
        let expectedDivider = try design.color(":root", "--color-border", viewport: 1280)
        #expect(abs(divider.redComponent - expectedDivider.red) < 0.01)
        #expect(abs(divider.greenComponent - expectedDivider.green) < 0.01)
        #expect(abs(divider.blueComponent - expectedDivider.blue) < 0.01)
        let accentColor = try #require(view.accentLayer.strokeColor)
        let accent = try #require(NSColor(cgColor: accentColor)?.usingColorSpace(.sRGB))
        let expectedAccent = try design.color(":root", "--color-accent", viewport: 1280)
        #expect(abs(accent.redComponent - expectedAccent.red) < 0.01)
        #expect(abs(accent.greenComponent - expectedAccent.green) < 0.01)
        #expect(abs(accent.blueComponent - expectedAccent.blue) < 0.01)
        #expect(view.layer?.animation(forKey: "picsee.reading.rotation") != nil)
        view.reduceMotion = { true }
        view.start()
        #expect(view.layer?.animation(forKey: "picsee.reading.rotation") == nil)
        #expect(view.accessibilityRole() == .progressIndicator)
    }
}

@Test @MainActor func issue282ReadingRingUpdatesRotationWhenReduceMotionChanges() {
    let view = ReadingProgressView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
    #expect(view.notificationCenter === NSWorkspace.shared.notificationCenter)
    var reduceMotion = false
    view.reduceMotion = { reduceMotion }
    view.start()
    #expect(view.layer?.animation(forKey: "picsee.reading.rotation") != nil)

    reduceMotion = true
    NotificationCenter.default.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                    object: NSWorkspace.shared)
    #expect(view.layer?.animation(forKey: "picsee.reading.rotation") != nil)
    view.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                 object: NSWorkspace.shared)
    #expect(view.layer?.animation(forKey: "picsee.reading.rotation") == nil)

    reduceMotion = false
    NotificationCenter.default.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                    object: NSWorkspace.shared)
    #expect(view.layer?.animation(forKey: "picsee.reading.rotation") == nil)
    view.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                 object: NSWorkspace.shared)
    #expect(view.layer?.animation(forKey: "picsee.reading.rotation") != nil)
}
