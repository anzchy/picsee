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
