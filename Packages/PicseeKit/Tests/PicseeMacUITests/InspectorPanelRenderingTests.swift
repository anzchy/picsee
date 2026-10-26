import AppKit
import SwiftUI
import Testing
import PicseeApplication
import PicseeCore
@testable import PicseeMacUI

private struct EmptyInspectorReader: InspectorMetadataReading {
    func read(_ url: URL, access: AccessRequest) async throws -> InspectorMetadata { .init() }
}
private struct FilledInspectorReader: InspectorMetadataReading {
    let value: InspectorMetadata
    func read(_ url: URL, access: AccessRequest) async throws -> InspectorMetadata { value }
}

@Test func issue136InspectorFrameLeavesGridTitleAndFooterVisible() {
    let bounds = NSRect(x: 0, y: 0, width: 960, height: 640)
    #expect(InspectorPanelLayout.frame(in: bounds, grid: true) == NSRect(x: 740, y: 40, width: 220, height: 572))
    #expect(InspectorPanelLayout.frame(in: bounds, grid: false) == NSRect(x: 740, y: 0, width: 220, height: 640))
}

@Test func issue136InspectorTypeNamesUseKnownExtensionOrHonestIdentifier() {
    #expect(InspectorPanel.typeName("public.png") == "PNG")
    #expect(InspectorPanel.typeName("com.example.unrecognized-image") == "com.example.unrecognized-image")
}

@Test @MainActor func issue136InspectorPanelUsesPage16And34GeometryAndSurfaceColors() throws {
    _ = NSApplication.shared
    let session = ViewerSession(), model = InspectorModel(reader: EmptyInspectorReader())
    for theme in DesignTheme.allCases {
        let renderer = ImageRenderer(content: InspectorPanel(model: model, session: session,
            close: {}, restoreCanvasFocus: {}, updateFocus: { _ in })
            .frame(height: 500)
            .environment(\.colorScheme, theme == .dark ? .dark : .light))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 220 && image.height == 500)
        let pixels = NSBitmapImageRep(cgImage: image)
        func renderedComponents(_ color: DesignColor) throws -> [Double] {
            let reference = ImageRenderer(content: Rectangle().fill(color.color).frame(width: 220, height: 500)
                .environment(\.colorScheme, theme == .dark ? .dark : .light))
            reference.scale = 1
            let rep = NSBitmapImageRep(cgImage: try #require(reference.cgImage))
            let sample = try #require(rep.colorAt(x: 100, y: 100)).usingColorSpace(.deviceRGB)!
            return [sample.redComponent, sample.greenComponent, sample.blueComponent]
        }
        let base = try renderedComponents(.canvasBackground)
        let preview = try renderedComponents(.sidebarBackground)
        let lower = try #require(pixels.colorAt(x: 205, y: 400)).usingColorSpace(.deviceRGB)!
        let picture = try #require(pixels.colorAt(x: 30, y: 85)).usingColorSpace(.deviceRGB)!
        for i in 0..<3 {
            #expect(abs(lower.cgColor.components![i] - base[i]) < 0.02)
            #expect(abs(picture.cgColor.components![i] - preview[i]) < 0.02)
        }
    }
}

@Test @MainActor func issue136InspectorPanelRendersKnownHeaderAndActualPreview() async throws {
    _ = NSApplication.shared
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TestAssets/synthetic/landscape-3x2.png")
    let preview = try Data(contentsOf: fixture)
    let metadata = InspectorMetadata(pixelWidth: 600, pixelHeight: 400, typeIdentifier: "public.png",
        creationDate: Date(timeIntervalSince1970: 1_000), modificationDate: Date(timeIntervalSince1970: 2_000),
        byteSize: Int64(preview.count), thumbnailData: preview)
    let model = InspectorModel(reader: FilledInspectorReader(value: metadata)), session = ViewerSession()
    let url = URL(fileURLWithPath: "/tmp/long-name.png")
    model.select(itemID: nil, url: url, access: .fileGrant(url))
    for _ in 0..<100 where model.value == .loading { await Task.yield() }
    #expect(model.value == .known(metadata))
    let renderer = ImageRenderer(content: InspectorPanel(model: model, session: session,
        close: {}, restoreCanvasFocus: {}, updateFocus: { _ in }).frame(height: 500))
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    #expect(image.width == 220 && image.height == 500)
    let pixel = try #require(NSBitmapImageRep(cgImage: image).colorAt(x: 110, y: 108)).usingColorSpace(.deviceRGB)!
    let background = DesignColor.sidebarBackground.components(.light)
    #expect(abs(pixel.redComponent - background[0]) > 0.05)
}

@Test @MainActor func issue136InspectorPanelFocusEntersAndEscRestoresCanvas() {
    _ = NSApplication.shared
    let session = ViewerSession(), model = InspectorModel(reader: EmptyInspectorReader())
    var updates: [FocusContext] = [], restored = 0
    let host = NSHostingView(rootView: InspectorPanel(model: model, session: session,
        close: {}, restoreCanvasFocus: { restored += 1 }, updateFocus: { updates.append($0) }))
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 220, height: 500),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    session.setInspectorVisible(true)
    session.tab(reverse: false)
    host.layoutSubtreeIfNeeded()
    let focusDeadline = Date().addingTimeInterval(1)
    while updates.isEmpty && Date() < focusDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    #expect(updates.contains(.panel))
    _ = CommandRouter().route(.escape, from: .key, to: session)
    host.layoutSubtreeIfNeeded()
    let restoreDeadline = Date().addingTimeInterval(1)
    while restored == 0 && Date() < restoreDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    #expect(restored > 0)
    #expect(session.inspectorFocus.focus == .canvas)
}
