import PicseeCore

public enum SelectionModifier: Sendable { case plain, command, shift }

/// Identity-based selection over the caller's filtered, sorted order.
public struct BrowserSelection: Equatable, Sendable {
    public private(set) var selectedItemIDs: Set<ItemID> = []
    public private(set) var currentItemID: ItemID?
    public private(set) var anchorItemID: ItemID?
    public init() {}
    public mutating func click(_ id: ItemID, modifier: SelectionModifier = .plain, in items: [ItemID]) {
        guard let clicked = items.firstIndex(of: id) else { return }
        if modifier == .shift, let anchorItemID, let anchor = items.firstIndex(of: anchorItemID) {
            selectedItemIDs = Set(items[min(anchor, clicked)...max(anchor, clicked)])
            currentItemID = id
            return
        }
        if modifier == .command {
            if !selectedItemIDs.insert(id).inserted { selectedItemIDs.remove(id) }
        } else {
            selectedItemIDs = [id]
        }
        currentItemID = id
        anchorItemID = id
    }
    public mutating func reconcile(with items: [ItemID]) {
        let remaining = Set(items)
        selectedItemIDs.formIntersection(remaining)
        if let currentItemID, !remaining.contains(currentItemID) { self.currentItemID = nil }
        if let anchorItemID, !remaining.contains(anchorItemID) { self.anchorItemID = nil }
    }
}
