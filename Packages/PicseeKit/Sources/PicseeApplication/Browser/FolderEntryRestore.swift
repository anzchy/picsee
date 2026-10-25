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
}

extension ViewerSession {
    /// Records what the window shows before a folder entry replaces it; an entry already reading keeps its first point.
    public func beginFolderEntry(shownImage: URL?, hasCompleteGrid: Bool) {
        guard folderEntryRestore == nil else { return }
        let target: FolderEntryRestoreTarget = hasCompleteGrid ? .grid : shownImage.map { .viewer($0) } ?? .empty
        folderEntryRestore = FolderEntryRestorePoint(target: target)
    }
    /// Stops the reading scan once; nil when no entry is reading.
    public func cancelFolderEntry() -> FolderEntryRestoreTarget? {
        guard let point = folderEntryRestore else { return nil }
        folderEntryRestore = nil
        cancelFolderReading()
        leaveBrowsing()
        return point.target
    }
    public func completeFolderEntry() { folderEntryRestore = nil }
}
