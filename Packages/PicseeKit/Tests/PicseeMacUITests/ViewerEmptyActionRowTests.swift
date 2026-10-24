import AppKit
import Testing
@testable import PicseeMacUI

@MainActor private func emptyActionView(_ id: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == id { return root }
    for child in root.subviews {
        if let view = emptyActionView(id, in: child) { return view }
    }
    return nil
}

@MainActor private func emptyActionFrame(_ id: String, in host: ViewerStateHost) throws -> NSRect {
    let view = try #require(emptyActionView(id, in: host))
    return host.convert(view.bounds, from: view)
}

@MainActor private func sizeEmptyScene(_ scene: StatesScene, to size: NSSize) {
    scene.window.setContentSize(size)
    scene.content.frame = NSRect(origin: .zero, size: size)
    scene.state.frame = scene.content.bounds
    scene.state.needsLayout = true
    scene.state.layoutSubtreeIfNeeded()
}

@MainActor private func assertEmptyActionGroupContained(_ scene: StatesScene) throws {
    let ids = ["state.icon", "state.heading", "state.description", "state.open", "state.drop-hint"]
    let frames = try ids.map { try emptyActionFrame($0, in: scene.state) }
    let union = frames.dropFirst().reduce(try #require(frames.first)) { $0.union($1) }
    #expect(abs(union.midX - scene.state.bounds.midX) <= 1)
    #expect(abs(union.midY - scene.state.bounds.midY) <= 1)
    let visible = scene.state.bounds.insetBy(dx: 16, dy: 16)
    for rect in frames { #expect(visible.contains(rect)) }
    #expect(abs(frames[2].minY - frames[3].maxY - 18) <= 0.5)
    let children = try #require(scene.state.accessibilityChildren() as? [NSView])
    let button = try #require(emptyActionView("state.open", in: scene.state))
    let hint = try #require(emptyActionView("state.drop-hint", in: scene.state))
    let buttonIndex = try #require(children.firstIndex { $0 === button })
    let hintIndex = try #require(children.firstIndex { $0 === hint })
    #expect(buttonIndex < hintIndex)
}

@Test @MainActor func issue92EmptyActionsInlineAtWideEnglishAndChineseSizes() throws {
    let scene = StatesScene(width: 1280)
    defer { scene.window.close() }
    for (size, buttonTitle, hintText) in [
        (NSSize(width: 1280, height: 800), "Choose Folder…", "You can also drop images or folders here."),
        (NSSize(width: 800, height: 680), "选择文件夹…", "也可以拖入图片或文件夹")
    ] {
        scene.state.display(.empty)
        let button = try #require(emptyActionView("state.open", in: scene.state) as? NSButton)
        let hint = try #require(emptyActionView("state.drop-hint", in: scene.state) as? NSTextField)
        button.title = buttonTitle
        hint.stringValue = hintText
        sizeEmptyScene(scene, to: size)
        let action = try emptyActionFrame("state.open", in: scene.state)
        let note = try emptyActionFrame("state.drop-hint", in: scene.state)
        #expect(abs(note.minX - action.maxX - 16) <= 0.5)
        #expect(abs(note.midY - action.midY) <= 0.5)
        #expect(note.height <= action.height)
        try assertEmptyActionGroupContained(scene)
    }
}

@Test @MainActor func issue92EmptyActionsStackWhenLocalizedCopyCannotFit() throws {
    let scene = StatesScene(width: 360)
    defer { scene.window.close() }
    for hintText in ["You can also drop images or folders here.", String(repeating: "也可以拖入图片或文件夹", count: 5)] {
        scene.state.display(.failed(.corruptImage, "B.jpg"))
        scene.state.display(.empty)
        let hint = try #require(emptyActionView("state.drop-hint", in: scene.state) as? NSTextField)
        hint.stringValue = hintText
        sizeEmptyScene(scene, to: NSSize(width: 360, height: 680))
        let action = try emptyActionFrame("state.open", in: scene.state)
        let note = try emptyActionFrame("state.drop-hint", in: scene.state)
        #expect(abs(action.minY - note.maxY - 9) <= 0.5)
        #expect(abs(note.midX - scene.state.bounds.midX) <= 1)
        try assertEmptyActionGroupContained(scene)
    }
}
