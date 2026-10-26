import Foundation
import PicseeCore

/// What Cancel Reading returns to (ADR-0010: 回到之前显示的内容).
public enum FolderEntryRestoreTarget: Equatable, Sendable {
    case viewer(URL)
    case grid
    case empty
}

struct FolderEntryRestorePoint {
    let target: FolderEntryRestoreTarget
    let browsing: ViewerSession.BrowsingState
    let scan: FolderScanRestorePoint?
}

extension ViewerSession {
    /// Records what the window shows before a folder entry replaces it; an entry already reading keeps its first point.
    public func beginFolderEntry(shownImage: URL?, hasCompleteGrid: Bool) {
        guard folderEntryRestore == nil else { return }
        // A shown image wins, including one previewed from a grid; the grid's state is restored with it.
        let target: FolderEntryRestoreTarget = shownImage.map { .viewer($0) } ?? (hasCompleteGrid ? .grid : .empty)
        folderEntryRestore = FolderEntryRestorePoint(target: target, browsing: browsingState, scan: folderScan?.restorePoint)
    }
    /// Stops the reading scan once and puts back the browsing state and folder source; nil when no entry is reading.
    public func cancelFolderEntry() -> FolderEntryRestoreTarget? {
        guard let point = folderEntryRestore else { return nil }
        folderEntryRestore = nil
        // restore() stops the reading scan itself and keeps the restored folder's watch on the same stream.
        if let scan = point.scan, let folderScan { folderScan.restore(scan) } else { cancelFolderReading() }
        restoreBrowsingState(point.browsing)
        return point.target
    }
    public func completeFolderEntry() { folderEntryRestore = nil }
}
