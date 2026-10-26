import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@MainActor private final class MultiPreviewPresentationHost: ViewerSessionHost {
    let presentation: GridViewerPresentation
    let grid: GridBrowserView
    let snapshot: () -> FolderSnapshot
    let offset: NSPoint
    var hasImage = true
    init(presentation: GridViewerPresentation, grid: GridBrowserView,
         snapshot: @escaping () -> FolderSnapshot, offset: NSPoint) {
        self.presentation = presentation; self.grid = grid; self.snapshot = snapshot; self.offset = offset
    }
    func performCanvas(_ command: CommandID, from entry: CommandEntry) {}
    func requestOpen() {}
    func applyFocus(_ focus: FocusContext) {}
    func showInspector(_ visible: Bool) {}
    func presentGridItem(_ id: ItemID) { presentation.showViewer() }
    func returnToGrid() {
        presentation.restoreGrid(snapshot(), selection: session!.selection, offset: offset)
    }
    weak var session: ViewerSession?
}

@Test @MainActor func gridPresentationRestoresReconciledMultiSelectionAndOffsetAfterSpaceEscape() throws {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: "/tmp/picsee-preview-presentation")
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: folder)
    let entries = (0..<30).map { FolderEntry(url: folder.appendingPathComponent("\($0).jpg"), root: root) }
    let ids = entries.map(\.itemID)
    func snapshot(_ entries: [FolderEntry], _ generation: UInt64) -> FolderSnapshot {
        FolderSnapshot(version: .init(rootID: root.id, folder: folder, generation: generation),
            entries: entries, isComplete: true)
    }
    var shown = snapshot(entries, 1)
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let window = NSWindow(contentRect: grid.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = grid
    let canvas = NSView(), chrome = NSView(), state = NSView(), inspector = NSView()
    let presentation = GridViewerPresentation(canvas: canvas, chrome: chrome, state: state,
        grid: grid, inspector: inspector)
    let session = ViewerSession()
    session.beginBrowsing(items: ids, sourceVersion: .init(1), scrollAnchor: ids[0])
    session.select(ids[2]); session.select(ids[5], modifier: .command); session.select(ids[8], modifier: .command)
    grid.display(shown, selection: session.selection)
    grid.layoutSubtreeIfNeeded(); grid.collectionView.layoutSubtreeIfNeeded()
    grid.restoreContentOffset(NSPoint(x: 0, y: 75))
    let offset = grid.contentOffset
    let host = MultiPreviewPresentationHost(presentation: presentation, grid: grid,
        snapshot: { shown }, offset: offset)
    host.session = session
    session.host = host
    #expect(CommandRouter().route(.preview, from: .key, to: session))
    #expect(session.previewSet?.itemIDs == [ids[2], ids[5], ids[8]])
    #expect(!presentation.isGridVisible)
    shown = snapshot(entries.filter { $0.itemID != ids[5] }, 2)
    session.updateItems(shown.navigationEntries.map(\.itemID), sourceVersion: .init(2))
    #expect(CommandRouter().route(.escape, from: .key, to: session))
    #expect(presentation.isGridVisible)
    #expect(grid.selection.selectedItemIDs == [ids[2], ids[8]])
    #expect(Set(grid.collectionView.selectionIndexPaths.compactMap { grid.itemID(at: $0.item) }) ==
        session.selection.selectedItemIDs)
    #expect(grid.currentItemID == session.selection.currentItemID)
    #expect(grid.contentOffset == offset)
}
