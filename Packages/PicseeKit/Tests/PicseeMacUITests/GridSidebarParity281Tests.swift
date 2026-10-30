import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
@testable import PicseeMacUI

@MainActor private func issue281SidebarView(_ id: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == id { return root }
    for child in root.subviews {
        if let match = issue281SidebarView(id, in: child) { return match }
    }
    return nil
}

@Test @MainActor func issue281SidebarRowsAndAddFolderMatchPinnedFrames() throws {
    let design = try PinnedDesign.page("grid-light")
    let tree = GridSidebarTreeView(frame: NSRect(x: 0, y: 0, width: 196, height: 732))
    let root = URL(fileURLWithPath: "/tmp/Images")
    let children = [
        GridSidebarFolder(url: root.appendingPathComponent(String(repeating: "长目录名", count: 20)), count: 12345),
        GridSidebarFolder(url: root.appendingPathComponent("English folder with a long name"), count: 7),
        GridSidebarFolder(url: root.appendingPathComponent("Third"), count: 1),
    ]
    tree.show(current: GridSidebarFolder(url: root, count: 12), parent: nil, children: children)
    tree.layoutSubtreeIfNeeded()
    #expect(tree.rows.count == 4)
    // grid-light.html: .ds-nav-row is min-height 32px; child rows have no extra bottom gap.
    #expect(tree.rows[1].frame.minY - tree.rows[2].frame.minY == 32)
    #expect(tree.rows[2].frame.minY - tree.rows[3].frame.minY == 32)
    #expect(tree.rows[1].countLabel.stringValue == "12345")
    #expect(tree.rows[1].nameLabel.frame.maxX <= tree.rows[1].countLabel.frame.minX)
    #expect(tree.rows[1].nameLabel.lineBreakMode == .byTruncatingTail)

    let plus = try #require(issue281SidebarView("grid.sidebar.add-folder-plus", in: tree))
    #expect(plus.frame.minX > tree.heading.frame.minX)
    #expect(plus.frame.maxX <= tree.bounds.maxX)
    let add = try #require(issue281SidebarView("grid.sidebar.add-folder", in: tree) as? NSButton)
    // grid-light.html: .add-folder has margin 12px 4px 0, height 30px, dashed 1px border and control radius.
    #expect(add.frame.height == 30)
    #expect(add.frame.minX == 4)
    #expect(add.frame.maxX == tree.bounds.width - 4)
    #expect(tree.rows[3].frame.minY - add.frame.maxY == 12)
    #expect(add.title == "Add Folder")
    #expect(Double(add.layer?.cornerRadius ?? 0) == DesignMetrics.radii["control"]!)
    let dash = try #require(add.layer?.sublayers?.first { ($0 as? CAShapeLayer)?.lineDashPattern != nil } as? CAShapeLayer)
    #expect(dash.lineWidth == 1)
    #expect(add.isEnabled == false)
    #expect(add.refusesFirstResponder)
    let border = try #require(dash.strokeColor)
    let actual = try #require(NSColor(cgColor: border)?.usingColorSpace(.sRGB))
    let expected = try design.color(":root", "--color-border", viewport: 1280)
    #expect(abs(actual.redComponent - expected.red) < 0.01)
    #expect(abs(actual.greenComponent - expected.green) < 0.01)
    #expect(abs(actual.blueComponent - expected.blue) < 0.01)
}

@Test @MainActor func issue281SidebarDividerMatchesPinnedEdgeInLightAndDark() throws {
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 1280, height: 772),
            preferencesStore: InMemoryDisplayPreferencesStore())
        shell.appearance = NSAppearance(named: appearance)
        shell.layoutSubtreeIfNeeded()
        let divider = try #require(issue281SidebarView("grid.sidebar.divider", in: shell))
        #expect(divider.frame.minX == 195)
        #expect(divider.frame.width == 1)
        #expect(divider.frame.height == shell.sidebar.frame.height)
        #expect(divider.layer?.backgroundColor != nil)
    }
}
