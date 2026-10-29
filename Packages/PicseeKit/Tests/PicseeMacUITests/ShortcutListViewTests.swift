import AppKit
import Testing
import PicseeApplication
@testable import PicseeMacUI

private let issue219Viewport = 820.0
private let issue219Appearances: [(NSAppearance.Name, String)] = [(.aqua, "light"), (.darkAqua, "dark")]

@MainActor private func issue219View(_ language: EntryPointLanguage, _ appearance: NSAppearance.Name) throws -> ShortcutListView {
    _ = NSApplication.shared
    let catalog = ShortcutCatalog(menu: issue219Menu(), language: language)
    let view = ShortcutListView(frame: NSRect(x: 0, y: 0, width: issue219Viewport, height: 502), catalog: catalog)
    view.appearance = NSAppearance(named: appearance)
    view.layoutSubtreeIfNeeded()
    return view
}

private func issue219Length(_ design: PinnedDesign, _ selector: String, _ property: String) throws -> Double {
    let raw = try design.raw(selector, property, viewport: issue219Viewport)
    return try design.lengthValue(String(raw.split(separator: " ")[0]), viewport: issue219Viewport)
}

@MainActor private func issue219Color(_ color: NSColor?, _ appearance: NSAppearance) throws -> PinnedDesign.Color {
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance { resolved = color?.usingColorSpace(.sRGB) }
    let color = try #require(resolved)
    return PinnedDesign.Color(red: Double(color.redComponent), green: Double(color.greenComponent),
        blue: Double(color.blueComponent), alpha: Double(color.alphaComponent))
}

@MainActor private func issue219CGColor(_ color: CGColor?, _ appearance: NSAppearance) throws -> PinnedDesign.Color {
    try issue219Color(color.flatMap(NSColor.init(cgColor:)), appearance)
}

@Test @MainActor func issue219ShortcutCardsAndWindowFollowPinnedFrames() throws {
    for (name, theme) in issue219Appearances {
        let design = try PinnedDesign.page("shortcuts", appearance: theme)
        let view = try issue219View(.english, name)
        try design.assertLength(Double(view.bounds.width), ".window", "width", viewport: issue219Viewport)
        let titlebar = try design.length(".titlebar", "height", viewport: issue219Viewport)
        try design.assertLength(Double(view.bounds.height) + titlebar, ".window", "height", viewport: issue219Viewport)
        try #require(view.cardViews.count == 3)
        let cards = view.cardViews
        let padding = try design.edges(".cards", "padding", viewport: issue219Viewport)
        let gap = try design.length(".cards", "gap", viewport: issue219Viewport)
        for index in cards.indices {
            let frame = cards[index].frame
            if index == 0 {
                #expect(abs(Double(frame.minX) - padding.left) <= 0.5)
            } else {
                try design.assertLength(Double(frame.minX - cards[index - 1].frame.maxX), ".cards", "gap", viewport: issue219Viewport)
            }
            #expect(abs(frame.width - cards[0].frame.width) <= 1)
            #expect(abs(Double(frame.minY) - padding.top) <= 0.5)
            if index == 2 { #expect(abs(Double(view.bounds.width - frame.maxX) - padding.right) <= 0.5) }
            let card = cards[index]
            let layer = try #require(card.layer)
            #expect(Double(layer.borderWidth) == (try issue219Length(design, ".shortcut-card", "border")))
            try design.assertLength(Double(layer.cornerRadius), ".shortcut-card", "border-radius", viewport: issue219Viewport)
            try design.assertColor(issue219CGColor(layer.borderColor, view.effectiveAppearance), ".shortcut-card", "border", viewport: issue219Viewport)
            try design.assertColor(issue219CGColor(layer.backgroundColor, view.effectiveAppearance), ".shortcut-card", "background", viewport: issue219Viewport)
            try #require(!card.rowViews.isEmpty)
            let rows = card.rowViews
            let border = try issue219Length(design, ".shortcut-card", "border")
            let titleMargin = try design.edges(".shortcut-card h3", "margin", viewport: issue219Viewport).top
            let actualPadding = PinnedDesign.Edges(
                top: Double(card.titleLabel.frame.minY) - border - titleMargin,
                right: Double(card.bounds.width - rows[0].frame.maxX) - border,
                bottom: Double(card.requiredHeight - rows[rows.count - 1].frame.maxY) - border,
                left: Double(rows[0].frame.minX) - border)
            try design.assertEdges(actualPadding, ".shortcut-card", "padding", viewport: issue219Viewport)
        }
        #expect(abs(Double(cards[1].frame.minX - cards[0].frame.maxX) - gap) <= 0.5)
    }
}

@Test @MainActor func issue219ShortcutTypographyRowsAndKeycapsFollowPinnedDesign() throws {
    for (name, theme) in issue219Appearances {
        let design = try PinnedDesign.page("shortcuts", appearance: theme)
        let view = try issue219View(.simplifiedChinese, name)
        try #require(view.cardViews.count == 3)
        for card in view.cardViews {
            let titleFont = try #require(card.titleLabel.font)
            try design.assertLength(Double(titleFont.pointSize), ".shortcut-card h3", "font-size", viewport: issue219Viewport)
            #expect(titleFont == NSFont.systemFont(ofSize: titleFont.pointSize, weight: .semibold))
            let whenFont = try #require(card.whenLabel.font)
            try design.assertFont(PinnedDesign.Font(size: Double(whenFont.pointSize), weight: 400, lineHeight: nil),
                ".shortcut-card .when", viewport: issue219Viewport)
            try design.assertColor(issue219Color(card.whenLabel.textColor, view.effectiveAppearance),
                ".shortcut-card .when", "color", viewport: issue219Viewport)
            for (rowIndex, row) in card.rowViews.enumerated() {
                try design.assertLength(Double(row.bounds.height), ".row", "height", viewport: issue219Viewport)
                #expect(row.nameLabel.frame.minX == 0)
                try #require(!row.keycapViews.isEmpty)
                let keys = row.keycapViews
                #expect(keys[keys.count - 1].frame.maxX == row.bounds.width)
                #expect(abs(keys[0].frame.minX - row.nameLabel.frame.maxX - 8) <= 0.5)
                #expect(row.separator.isHidden == (rowIndex == card.rowViews.count - 1))
                if !row.separator.isHidden {
                    #expect(row.separator.frame.height == 1)
                    try design.assertColor(issue219CGColor(row.separator.layer?.backgroundColor, view.effectiveAppearance),
                        ":root", "--color-border-subtle", viewport: issue219Viewport)
                }
                for (keyIndex, key) in keys.enumerated() {
                    #expect(key.frame.height == 22 && key.frame.width >= 22)
                    if keyIndex > 0 { #expect(abs(key.frame.minX - keys[keyIndex - 1].frame.maxX - 4) <= 0.5) }
                    let layer = try #require(key.layer)
                    #expect(layer.borderWidth == 1 && layer.cornerRadius == 4)
                    #expect(key.bottomEdge.frame.height == 1 && key.bottomEdge.frame.maxY == key.bounds.height)
                    try design.assertColor(issue219CGColor(layer.borderColor, view.effectiveAppearance), "kbd", "border", viewport: issue219Viewport)
                    try design.assertColor(issue219CGColor(layer.backgroundColor, view.effectiveAppearance), "kbd", "background", viewport: issue219Viewport)
                    try design.assertLength(Double(key.label.font?.pointSize ?? 0), "kbd", "font-size", viewport: issue219Viewport)
                    #expect(key.label.frame.minX == 6 && key.bounds.width - key.label.frame.maxX == 6)
                }
            }
        }
    }
}

@Test @MainActor func issue219ShortcutLongestLabelsFitChineseAndEnglish() throws {
    for language in [EntryPointLanguage.english, .simplifiedChinese] {
        let view = try issue219View(language, .aqua)
        try #require(view.cardViews.count == 3)
        for card in view.cardViews {
            for row in card.rowViews {
                try #require(!row.keycapViews.isEmpty)
                let keys = row.keycapViews
                #expect(row.nameLabel.lineBreakMode == .byClipping)
                #expect(row.nameLabel.intrinsicContentSize.width <= row.nameLabel.frame.width + 0.5,
                    "\(language) \(row.nameLabel.stringValue) truncated")
                #expect(row.nameLabel.frame.maxX + 8 <= keys[0].frame.minX + 0.5,
                    "\(language) \(row.nameLabel.stringValue) overlaps keycaps")
                for key in keys {
                    #expect(key.label.intrinsicContentSize.width <= key.label.frame.width + 0.5)
                    #expect(row.bounds.contains(key.frame))
                }
            }
        }
    }
}
