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

@Test func issue136EnglishAndChineseLabelsFitTheirColumn() {
    let font = NSFont.systemFont(ofSize: 12)
    for label in ["Dimensions", "Modified", "Created", "Type", "Size",
                  "尺寸", "修改日期", "创建日期", "类型", "大小"] {
        let measured = (label as NSString).size(withAttributes: [.font: font]).width
        #expect(InspectorPanelLayout.labelWidth(label) >= measured)
        #expect(InspectorPanelLayout.labelWidth(label) >= 48)
        #expect(InspectorPanelLayout.labelWidth(label) < 110)
    }
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
        // Pinned pages 16/34: --color-bg and --color-surface, independent of DesignColor.
        let base: [Double] = theme == .dark ? [15, 17, 21] : [255, 255, 255]
        let preview: [Double] = theme == .dark ? [22, 26, 34] : [246, 247, 251]
        for (point, expected) in [(NSPoint(x: 205, y: 400), base),
                                  (NSPoint(x: 205, y: 460), base),
                                  (NSPoint(x: 100, y: 275), base),
                                  (NSPoint(x: 30, y: 85), preview),
                                  (NSPoint(x: 110, y: 105), preview)] {
            let color = try #require(pixels.colorAt(x: Int(point.x), y: Int(point.y))).usingColorSpace(.deviceRGB)!
            for i in 0..<3 {
                let actual = [color.redComponent, color.greenComponent, color.blueComponent][i]
                #expect(abs(actual - expected[i] / 255) < 0.06)
            }
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
    let pixels = NSBitmapImageRep(cgImage: image)
    let background = DesignColor.sidebarBackground.components(.light)
    let hasActualPreviewPixel = stride(from: 60, through: 170, by: 10).contains { y in
        stride(from: 25, through: 190, by: 10).contains { x in
            guard let pixel = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
            return abs(pixel.redComponent - background[0]) > 0.05
                && abs(pixel.greenComponent - background[1]) > 0.05
        }
    }
    #expect(hasActualPreviewPixel)
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
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let closeButton = descendants(host).compactMap { $0 as? NSButton }
        .first { $0.accessibilityIdentifier() == "inspector.close" }
    #expect(closeButton?.acceptsFirstResponder == true)
    #expect(closeButton?.focusRingType == .exterior)
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
