import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@MainActor private func stateView(_ id: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == id { return root }
    for child in root.subviews {
        if let match = stateView(id, in: child) { return match }
    }
    return nil
}

@MainActor private func frame(_ id: String, in host: ViewerStateHost) throws -> NSRect {
    let view = try #require(stateView(id, in: host))
    return host.convert(view.bounds, from: view)
}

@Test @MainActor func issue92EmptyStateComposesSemanticContent() throws {
    let scene = StatesScene()
    defer { scene.window.close() }
    scene.state.display(.empty)
    scene.state.layoutSubtreeIfNeeded()
    let icon = try frame("state.icon", in: scene.state)
    let heading = try frame("state.heading", in: scene.state)
    let description = try frame("state.description", in: scene.state)
    let action = try frame("state.open", in: scene.state)
    let hint = try frame("state.drop-hint", in: scene.state)
    #expect(icon.size == NSSize(width: 32, height: 32))
    #expect(stateView("state.icon", in: scene.state)?.accessibilityLabel() == "Open folder")
    #expect(icon.minY > heading.maxY)
    #expect(heading.minY > description.maxY)
    #expect(description.minY > action.maxY)
    #expect(abs(icon.midX - scene.state.bounds.midX) < 1)
    #expect(hint.maxY < action.minY)
    #expect(stateView("state.heading", in: scene.state)?.accessibilityLabel() == scene.state.textLines[0])
}

@Test @MainActor func issue92FailureStateWrapsAtCompactSizeAndTracksNext() throws {
    let scene = StatesScene(width: 800)
    defer { scene.window.close() }
    scene.state.frame.size.height = 680
    let longName = String(repeating: "long-file-name-", count: 14) + ".jpg"
    scene.state.display(.failed(.corruptImage, longName), nextEnabled: true)
    scene.state.layoutSubtreeIfNeeded()
    let icon = try frame("state.icon", in: scene.state)
    let heading = try frame("state.heading", in: scene.state)
    let filename = try frame("state.filename", in: scene.state)
    let reason = try frame("state.reason", in: scene.state)
    let retry = try frame("state.retry", in: scene.state)
    let next = try frame("state.next", in: scene.state)
    #expect(icon.size == NSSize(width: 32, height: 32))
    #expect(stateView("state.icon", in: scene.state)?.accessibilityLabel() == "Unreadable image")
    #expect(icon.minY > heading.maxY)
    #expect(heading.minY > filename.maxY)
    #expect(filename.minY > reason.maxY)
    #expect(reason.minY > retry.maxY)
    #expect(filename.height > 18)
    #expect(retry.minX < next.minX)
    #expect(retry.minY > 80)
    scene.state.display(.failed(.corruptImage, longName), nextEnabled: false)
    scene.state.layoutSubtreeIfNeeded()
    #expect(stateView("state.next", in: scene.state) == nil)
    #expect(stateView("state.retry", in: scene.state) != nil)
}
