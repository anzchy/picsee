import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@MainActor private final class StaticMotionSource: ReduceMotionSource {
    var reduceMotion = false
    var onChange: (@MainActor () -> Void)?
}

@MainActor @Test func emptyRescanClearsAppWindowImageIdentity() throws {
    _ = NSApplication.shared
    let unavailable = Task<AccessServices, Error> { throw CancellationError() }
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: unavailable,
        motionPolicy: MotionPolicy(source: StaticMotionSource()))
    let window = try #require(controller.window)
    defer { window.close() }
    let imageURL = URL(fileURLWithPath: "/nested/only.png")
    let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
        bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = DecodedImage(image: try #require(context.makeImage()), sourcePixelSize: CGSize(width: 1, height: 1))

    controller.installImage(image, fileURL: imageURL)
    #expect(window.title == "only.png")
    #expect(window.representedURL == imageURL)

    controller.clearFolderImageForNoMatches()
    #expect(!controller.hasImage)
    #expect(controller.session.imageLoader.fileURL == nil)
    #expect(window.title == "Picsee")
    #expect(window.representedURL == nil)

    controller.beginImageOpening()
    #expect(window.title == "Picsee")
    #expect(window.representedURL == nil)
    controller.installImage(image, fileURL: imageURL)
    controller.imageLoadFailed(CancellationError())
    #expect(window.title == "Picsee")
    #expect(window.representedURL == nil)
}

@MainActor @Test func issue136WindowRoutesInspectorCommandTabAndEscape() throws {
    _ = NSApplication.shared
    let unavailable = Task<AccessServices, Error> { throw CancellationError() }
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: unavailable,
        motionPolicy: MotionPolicy(source: StaticMotionSource()))
    let window = try #require(controller.window)
    defer { window.close() }
    let item = ItemID.rootRelative(rootID: AccessRootID(), relativePath: "current.png")
    controller.session.beginBrowsing(items: [item], sourceVersion: .init(1), scrollAnchor: item)
    controller.session.focus(item)
    func key(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = []) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code))
        window.sendEvent(event)
    }
    try key(34, "i", modifiers: .command)
    #expect(controller.inspectorVisible)
    for _ in 0..<12 where controller.session.inspectorFocus.focus != .panel
        && controller.session.inspectorFocus.focus != .textInput {
        try key(48, "\t")
    }
    #expect(controller.session.inspectorFocus.focus == .panel || controller.session.inspectorFocus.focus == .textInput)
    try key(53, "\u{1b}")
    #expect(controller.session.inspectorFocus.focus == .canvas)
    #expect(controller.inspectorVisible)
}
