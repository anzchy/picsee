import Foundation
import Testing

@Test func pinnedDesignGridRulesFollowViewport() throws {
    let page = try PinnedDesign.page("grid-light")
    #expect(try page.edges(".grid-bottom-bar", "padding", viewport: 1280).right == 12)
    #expect(try page.edges(".grid-bottom-bar", "padding", viewport: 480).right == 7)
    #expect(try page.length(".grid-toolbar-tools", "gap", viewport: 1280) == 6)
    #expect(try page.length(".grid-toolbar-tools", "gap", viewport: 800) == 2)
}

@Test func pinnedDesignTypographyAndColorsComeFromPages() throws {
    let empty = try PinnedDesign.page("search-empty")
    let heading = try empty.font(".empty-state h2", viewport: 1280)
    #expect(heading.size == 16)
    #expect(heading.weight == 500)
    let light = try PinnedDesign.page("grid-light").color(".grid-bottom-bar", "border-top", viewport: 1280)
    let dark = try PinnedDesign.page("grid-dark").color(".grid-bottom-bar", "border-top", viewport: 1280)
    #expect(light.alpha == 0.10)
    #expect(dark.alpha == 0.12)
    #expect(light.red == 26.0 / 255)
    #expect(dark.red == 229.0 / 255)
}

@Test func pinnedDesignReportsMissingRules() throws {
    let page = try PinnedDesign.page("viewer-inspector")
    #expect(throws: PinnedDesign.Error.self) {
        try page.length(".missing-selector", "gap", viewport: 1280)
    }
}

@Test func pinnedDesignExpressionsAndFailureExplainTheSource() throws {
    let page = try PinnedDesign.page("grid-light")
    #expect(try page.length(".thumbnail-wrap", "height", viewport: 1280) == 188.16)
    #expect(try page.length(".thumbnail-wrap", "height", viewport: 480) == 150)
    #expect(try page.length("body.tauri-macos", "--traffic-lights-clearance", viewport: 1280) == 62)
    let highlight = try page.color(":root", "--color-highlight", viewport: 1280)
    #expect(highlight.alpha == 0.65)
    do {
        try page.assertLength(99, ".grid-toolbar-tools", "gap", viewport: 800)
        Issue.record("Expected a CSS comparison failure")
    } catch let error as PinnedDesign.Error {
        #expect(error.description.contains(".grid-toolbar-tools gap at 800.0pt"))
        #expect(error.description.contains("expected 2.0pt"))
        #expect(error.description.contains("actual 99.0pt"))
    }
}

@Test func pinnedDesignRejectsChangedPageHash() throws {
    let source = URL(fileURLWithPath: #filePath)
    let root = source.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let original = root.appendingPathComponent("design/prototypes/picsee-browser/states")
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let states = temporary.appendingPathComponent("design/prototypes/picsee-browser/states")
    try FileManager.default.createDirectory(at: states, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.copyItem(at: original.appendingPathComponent("manifest.json"),
                                     to: states.appendingPathComponent("manifest.json"))
    try Data("<style>.grid-bottom-bar{padding:99px}</style>".utf8)
        .write(to: states.appendingPathComponent("grid-light.html"))
    let fakeSource = temporary.appendingPathComponent("Packages/PicseeKit/Tests/PicseeMacUITests/Test.swift")
    do {
        _ = try PinnedDesign.page("grid-light", source: fakeSource.path)
        Issue.record("Expected SHA256 mismatch")
    } catch let error as PinnedDesign.Error {
        #expect(error.description.contains("SHA256 mismatch"))
        #expect(error.description.contains("grid-light.html"))
    }
}

@Test func pinnedDesignLineHeightAndMinNeedExplicitBasis() throws {
    let page = try PinnedDesign.page("search-empty")
    #expect(abs(try page.lineHeight(".empty-state p", viewport: 1280) - 22.1) < 0.0001)
    #expect(try page.lengthValue("min(145px,100%)", viewport: 800, percentageBase: 120) == 120)
    #expect(throws: PinnedDesign.Error.self) {
        try page.lengthValue("min(145px,100%)", viewport: 800)
    }
}
