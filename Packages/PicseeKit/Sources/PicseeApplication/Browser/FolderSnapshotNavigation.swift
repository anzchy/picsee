import Foundation
import PicseeCore

@MainActor public protocol FolderScanHost: AnyObject {
    func openFolderImage(_ url: URL, rootID: AccessRootID)
    func rememberFolder(_ folder: URL, rootID: AccessRootID) async throws
    func showEmptyFolder()
}

extension FolderScanCoordinator {
    /// Nil lets a nonmember use the existing native grant/navigation path.
    public func canMove(_ direction: NavigationDirection, currentURL: URL? = nil) -> Bool? {
        guard let navigation = navigation(matching: currentURL), let snapshot else { return nil }
        return !snapshot.isComplete || neighbor(in: navigation, direction: direction) != nil
    }
    /// A member endpoint is handled, including a provisional endpoint's enabled no-op.
    @discardableResult public func move(_ direction: NavigationDirection, currentURL: URL? = nil) -> Bool {
        guard let navigation = navigation(matching: currentURL), let snapshot else { return false }
        pendingDirection = nil
        if let entry = neighbor(in: navigation, direction: direction) {
            currentItemID = entry.itemID
            self.currentURL = entry.url
            host?.openFolderImage(entry.url, rootID: snapshot.version.rootID)
        }
        return true
    }
    func advancePending() {
        guard !Task.isCancelled, let direction = pendingDirection, automaticPresentationAllowed?() != false,
              let navigation = navigation(matching: nil), neighbor(in: navigation, direction: direction) != nil else { return }
        move(direction)
    }
    private func navigation(matching actual: URL?) -> (entries: [FolderEntry], index: Int)? {
        guard let snapshot, let currentItemID else { return nil }
        if let actual, actual.standardizedFileURL != currentURL?.standardizedFileURL { return nil }
        // An allowed inward file link shares the pipeline's canonical identity.
        // Keep all scanner URLs in the snapshot, but navigate each identity once.
        var seen = Set<ItemID>()
        let entries = snapshot.entries.filter { seen.insert($0.itemID).inserted }
        guard let index = entries.firstIndex(where: { $0.itemID == currentItemID }) else { return nil }
        return (entries, index)
    }
    private func neighbor(in navigation: (entries: [FolderEntry], index: Int), direction: NavigationDirection) -> FolderEntry? {
        let index = navigation.index + (direction == .next ? 1 : -1)
        return navigation.entries.indices.contains(index) ? navigation.entries[index] : nil
    }
}

extension ViewerSession {
    public func endFolderScan() { folderScan?.end() }
    public func cancelFolderReading() { folderScan?.cancel() }
}
