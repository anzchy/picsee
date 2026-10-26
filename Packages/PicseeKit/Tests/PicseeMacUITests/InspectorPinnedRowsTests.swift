import AppKit
import SwiftUI
import Testing
@testable import PicseeMacUI

// Pages 16/34: .inspector dl uses a fixed 48 px label column, 7 px column gap,
// 13 px row gap. These values come from the pinned pages through PinnedDesign.
@Test @MainActor func issue136PinnedInspectorRendersEveryEnglishAndChineseFieldInColumns() throws {
    _ = NSApplication.shared
    for (pageName, theme) in [("viewer-inspector", DesignTheme.dark),
                              ("viewer-inspector-light", DesignTheme.light)] {
        let page = try PinnedDesign.page(pageName)
        let columns = try page.raw(".inspector dl", "grid-template-columns", viewport: 1280).split(separator: " ")
        let gap = try page.raw(".inspector dl", "gap", viewport: 1280).split(separator: " ")
        let labelWidth = try page.lengthValue(String(columns[0]), viewport: 1280)
        let columnGap = try page.lengthValue(String(gap[1]), viewport: 1280)
        #expect(labelWidth == 48 && columnGap == 7)
        let background = try page.color(":root", "--color-bg", viewport: 1280)
        let color = Color(red: background.red, green: background.green, blue: background.blue)
        for (label, value) in [
            ("Dimensions", "6000 × 4000"), ("Type", "PNG"), ("Created", "Unknown"),
            ("Modified", "Unknown"), ("Size", "1 MB"),
            ("尺寸", "6000 × 4000"), ("类型", "PNG"), ("创建日期", "未知"),
            ("修改日期", "未知"), ("大小", "1 MB")
        ] {
            #expect(InspectorPanelLayout.labelWidth(label) == CGFloat(labelWidth))
            let renderer = ImageRenderer(content: InspectorFieldRow(label: label, value: value, id: "test")
                .frame(width: 186, height: 34).background(color)
                .environment(\.colorScheme, theme == .dark ? .dark : .light))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let pixels = NSBitmapImageRep(cgImage: image)
            let ink = (0..<34).flatMap { y in (0..<186).compactMap { x -> (Int, Int)? in
                guard let pixel = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      abs(pixel.redComponent - background.red) > 0.12 else { return nil }
                return (x, y)
            } }
            #expect(ink.contains { $0.0 < Int(labelWidth) }, "\(pageName) \(label): label missing")
            #expect(ink.contains { $0.0 >= Int(labelWidth + columnGap) }, "\(pageName) \(label): value missing")
            #expect(!ink.contains { (Int(labelWidth)..<Int(labelWidth + columnGap)).contains($0.0) },
                    "\(pageName) \(label): columns overlap")
            #expect(ink.allSatisfy { $0.0 < 186 && $0.1 < 34 }, "\(pageName) \(label): clipped")
        }
    }
}

