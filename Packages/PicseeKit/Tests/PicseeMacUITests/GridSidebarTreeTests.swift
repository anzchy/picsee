import AppKit
import Testing
import PicseeApplication
import PicseeInfrastructure
@testable import PicseeMacUI

@Test @MainActor func sidebarTreeRowsFollowPinnedOptionAGeometryAndCounts() throws {
    _ = NSApplication.shared
    let design = try PinnedDesign.page("grid-light")
    let tree = GridSidebarTreeView(frame: NSRect(x: 0, y: 0, width: 196, height: 732))
    let root = URL(fileURLWithPath: "/tmp/Images")
    let longName = String(repeating: "长目录名", count: 20)
    let children = [GridSidebarFolder(url: root.appendingPathComponent(longName), count: 0),
                    GridSidebarFolder(url: root.appendingPathComponent("English folder with a long name"), count: 1234),
                    GridSidebarFolder(url: root.appendingPathComponent("Unknown"))]
    tree.show(current: GridSidebarFolder(url: root, count: 8), parent: nil, children: children)
    tree.layoutSubtreeIfNeeded()
    #expect(tree.rows.count == 4)
    let current = try #require(tree.rows.first)
    #expect(current.glyph.image != nil)
    #expect(current.countLabel.stringValue == "8")
    let rowHeight = try design.length(".ds-nav-row", "min-height", viewport: 1280)
    #expect(abs(Double(current.frame.height) - rowHeight) < 0.1)
    #expect(current.nameLabel.maximumNumberOfLines == 1)
    #expect(current.nameLabel.lineBreakMode == .byTruncatingTail)
    #expect(tree.rows[1].countLabel.stringValue == "0")
    #expect(tree.rows[2].countLabel.stringValue == "1234")
    #expect(tree.rows[3].countLabel.stringValue.isEmpty)
    #expect(tree.rows[1].frame.minX > current.frame.minX)
    #expect(tree.guide.frame.width == 1)
    #expect(tree.guide.frame.minX < tree.rows[1].frame.minX)
    #expect(tree.rows.allSatisfy { $0.frame.maxX <= tree.bounds.maxX })
    #expect(tree.rows[1].accessibilityLabel()?.contains("0") == true)
    #expect(tree.rows[3].accessibilityLabel()?.contains("Unknown") == true)
    #expect(tree.rows[3].accessibilityLabel()?.contains("images") == false)
    tree.frame = NSRect(x: 0, y: 0, width: 160, height: 612)
    tree.layoutSubtreeIfNeeded()
    #expect(tree.rows.allSatisfy { $0.nameLabel.frame.maxX <= $0.countLabel.frame.minX || $0.countLabel.isHidden })
}

@Test @MainActor func sidebarTreeParentAndKeyboardSelectionUseActualURLs() throws {
    _ = NSApplication.shared
    let tree = GridSidebarTreeView(frame: NSRect(x: 0, y: 0, width: 196, height: 732))
    let parent = URL(fileURLWithPath: "/tmp/Images")
    let current = parent.appendingPathComponent("Trip")
    let child = current.appendingPathComponent("Day 1")
    var chosen: URL?
    tree.onSelectFolder = { chosen = $0 }
    tree.show(current: .init(url: current), parent: .init(url: parent), children: [.init(url: child)])
    tree.layoutSubtreeIfNeeded()
    try #require(tree.rows.count == 3)
    #expect(tree.rows.map(\.folderURL) == [parent, current, child])
    #expect(tree.rows[1].current)
    #expect(tree.rows[0].acceptsFirstResponder)
    tree.rows[0].performClick(nil)
    #expect(chosen == parent)
    chosen = nil
    let returnKey = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
        isARepeat: false, keyCode: 36))
    tree.rows[2].keyDown(with: returnKey)
    #expect(chosen == child)
}

