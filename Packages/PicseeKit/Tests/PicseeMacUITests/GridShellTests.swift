import AppKit
import Testing
import PicseeApplication
import PicseeCore
@testable import PicseeMacUI

@Test @MainActor func gridShellFramesAndColumnsFollowSidebarAtDesignViewports() throws {
    _ = NSApplication.shared
    let store = InMemoryDisplayPreferencesStore()
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 1280, height: 772), preferencesStore: store)
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 1084, height: 732))
    shell.mainContent.addSubview(grid)
    shell.onMainFrameChange = { grid.frame = NSRect(origin: .zero, size: $0.size) }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                          styleMask: [], backing: .buffered, defer: false)
    let host = NSView(frame: window.contentView!.bounds)
    window.contentView = host
    host.addSubview(shell)
    shell.layoutSubtreeIfNeeded()
    let scroll = try #require(grid.subviews.compactMap { $0 as? NSScrollView }.first)
    scroll.scrollerStyle = .overlay
    scroll.tile()
    #expect(shell.sidebar.frame.width == 196)
    #expect(shell.footer.frame == NSRect(x: 0, y: 0, width: 1280, height: 40))
    #expect(shell.mainFrame == NSRect(x: 196, y: 40, width: 1084, height: 732))
    #expect(grid.frame.width == 1084)
    grid.layoutSubtreeIfNeeded()
    let layout = try #require(grid.collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)
    #expect(abs(layout.itemSize.width - 247) < 0.1) // four columns at 1084 pt

    shell.resizeSidebar(to: 320)
    shell.layoutSubtreeIfNeeded()
    #expect(shell.sidebar.frame.width == 320)
    #expect(shell.mainFrame.width == 960)
    grid.layoutSubtreeIfNeeded()
    #expect(abs(layout.itemSize.width - 223) < 0.1) // four columns at 960 pt
    #expect(store.value.gridSidebarWidth == 320)
    shell.resizeSidebar(to: 100)
    shell.layoutSubtreeIfNeeded()
    #expect(shell.sidebar.frame.width == 160)
    shell.toggleSidebar()
    shell.layoutSubtreeIfNeeded()
    #expect(shell.sidebar.isHidden)
    #expect(shell.mainFrame.width == 1280)
    grid.layoutSubtreeIfNeeded()
    #expect(grid.frame.width == 1280)
    #expect(abs(layout.itemSize.width - 233.6) < 0.1) // five columns after closing
    shell.toggleSidebar()
    #expect(store.value.gridSidebarWidth == 160)
    #expect(shell.mainFrame.width == 1120)

    shell.frame = NSRect(x: 0, y: 0, width: 800, height: 652)
    shell.layoutSubtreeIfNeeded()
    #expect(shell.footer.frame.maxY == shell.mainFrame.minY)
    #expect(shell.sidebar.frame.maxX == shell.mainFrame.minX)
    #expect(shell.mainFrame.maxX == 800)
    #expect(shell.mainFrame.maxY == 652)
    #expect(grid.frame == NSRect(x: 0, y: 0, width: 640, height: 612))
    grid.layoutSubtreeIfNeeded()
    #expect(abs(layout.itemSize.width - 194.667) < 0.1) // three columns at 800 × 680
}

@Test @MainActor func gridShellFooterButtonDragAndTruthfulFolderAreAccessible() throws {
    _ = NSApplication.shared
    let store = InMemoryDisplayPreferencesStore()
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 800, height: 652), preferencesStore: store)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 680),
                          styleMask: [], backing: .buffered, defer: false)
    window.contentView!.addSubview(shell)
    shell.layoutSubtreeIfNeeded()
    let active = shell
    let label = try #require(active.sidebar.subviews.compactMap { $0 as? NSTextField }.first)
    #expect(label.isHidden)
    active.showFolder("Actual Folder")
    #expect(label.stringValue == "Actual Folder")
    #expect(!label.isHidden)
    active.showFolder(nil)
    #expect(label.isHidden)

    #expect(active.toggleButton.accessibilityIdentifier() == "grid.sidebar.toggle")
    #expect(active.toggleButton.accessibilityLabel() == "Hide sidebar")
    active.toggleButton.performClick(nil)
    #expect(!store.value.gridSidebarVisible)
    #expect(active.toggleButton.accessibilityLabel() == "Show sidebar")
    active.toggleButton.performClick(nil)
    #expect(store.value.gridSidebarVisible)

    let divider = try #require(active.sidebar.subviews.first { $0.accessibilityIdentifier() == "grid.sidebar.resize" })
    divider.resetCursorRects()
    let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 196, y: 320),
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 1, clickCount: 1, pressure: 1))
    let moved = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 276, y: 320),
        modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil,
        eventNumber: 2, clickCount: 1, pressure: 1))
    divider.mouseDown(with: down)
    divider.mouseDragged(with: moved)
    #expect(store.value.gridSidebarWidth == 276)
    active.resizeSidebar(to: .infinity)
    #expect(store.value.gridSidebarWidth == 276)
    active.appearance = NSAppearance(named: .darkAqua)
    active.viewDidChangeEffectiveAppearance()

    #expect(GridShellView(coder: NSKeyedArchiver(requiringSecureCoding: false)) == nil)
}

@Test @MainActor func compactGridLongFilenameStaysInMainColumnAboveFooter() throws {
    _ = NSApplication.shared
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 800, height: 652),
                              preferencesStore: InMemoryDisplayPreferencesStore())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 680),
                          styleMask: [], backing: .buffered, defer: false)
    window.contentView!.addSubview(shell)
    shell.layoutSubtreeIfNeeded()
    let folder = URL(fileURLWithPath: "/tmp/picsee-compact-grid")
    let rootID = AccessRootID(rawValue: UUID())
    let root = ItemIdentityRoot(id: rootID, url: folder)
    let entry = FolderEntry(url: folder.appendingPathComponent(String(repeating: "a", count: 180) + ".jpg"), root: root)
    let grid = GridBrowserView(frame: NSRect(origin: .zero, size: shell.mainFrame.size))
    shell.mainContent.addSubview(grid)
    grid.display(FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: 1),
        entries: [entry], isComplete: true), selectedItemID: nil)
    grid.layoutSubtreeIfNeeded()
    let cell = try #require(grid.collectionView.visibleItems().compactMap { $0 as? GridPhotoItem }.first)
    let name = try #require(cell.view.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == entry.url.lastPathComponent })
    #expect(name.maximumNumberOfLines == 1)
    #expect(name.lineBreakMode == .byTruncatingTail)
    #expect(name.frame.maxX <= cell.view.bounds.maxX)
    #expect(shell.mainContent.frame.minY == shell.footer.frame.maxY)
}
