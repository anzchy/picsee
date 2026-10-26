import AppKit
import PicseeCore

enum GridThumbnailPixelSizing {
    static func edge(tile: NSSize, backingScale: CGFloat) -> Int {
        let longest = max(tile.width, tile.height)
        guard longest.isFinite, backingScale.isFinite, longest > 0, backingScale > 0 else { return 0 }
        return min(1024, max(1, Int(ceil(min(longest * backingScale, 1024)))))
    }
}

/// One window's cancellable thumbnail requests. The source is supplied by the App's lease-bound adapter.
@MainActor final class GridThumbnailScheduler {
    typealias Loader = @Sendable (FolderEntry, AccessRootID, Int, DecodePriority) async throws -> (ImageDecodeRequest, DecodedImage)
    var onResult: ((Int, ImageDecodeRequest, DecodedImage) -> Void)?
    var onFailure: ((Int) -> Void)?
    private struct Record {
        let token: UUID
        let itemID: ItemID
        var task: Task<Void, Never>?
        var result: (ImageDecodeRequest, DecodedImage)?
    }
    private var snapshot: FolderSnapshot?
    private var records: [Int: Record] = [:]
    private var currentPixelEdge = 0
    var activeItemIDs: Set<ItemID> { Set(records.values.map(\.itemID)) }

    func setSnapshot(_ snapshot: FolderSnapshot?) {
        cancelAll()
        self.snapshot = snapshot?.isComplete == true ? snapshot : nil
    }

    func reconcile(visible: Set<Int>, columns: Int, pixelEdge: Int, loader: Loader?) {
        guard let snapshot, let loader, pixelEdge > 0, let first = visible.min(),
              let last = visible.max(), !snapshot.navigationEntries.isEmpty else {
            cancelAll(); return
        }
        if currentPixelEdge != pixelEdge { cancelAll(); currentPixelEdge = pixelEdge }
        let margin = max(1, columns) * 2
        let lower = max(0, first - margin)
        let upper = min(snapshot.navigationEntries.count - 1, last + margin)
        let desired = Set(lower...upper)
        for index in Array(records.keys) where !desired.contains(index) {
            records.removeValue(forKey: index)?.task?.cancel()
        }
        // Visible requests enter admission first; prefetch may use remaining non-current slots.
        for index in desired.sorted(by: { (visible.contains($0) ? 0 : 1, $0) < (visible.contains($1) ? 0 : 1, $1) }) {
            guard records[index] == nil else { continue }
            let entry = snapshot.navigationEntries[index]
            let token = UUID()
            records[index] = Record(token: token, itemID: entry.itemID, task: nil, result: nil)
            let priority: DecodePriority = visible.contains(index) ? .visible : .prefetch
            records[index]?.task = Task { [weak self] in
                do {
                    let (request, image) = try await loader(entry, snapshot.version.rootID, pixelEdge, priority)
                    guard !Task.isCancelled else { return }
                    self?.finish(index: index, token: token, request: request, image: image)
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.fail(index: index, token: token)
                }
            }
        }
    }

    private func finish(index: Int, token: UUID, request: ImageDecodeRequest, image: DecodedImage) {
        guard let record = records[index], record.token == token, let snapshot,
              snapshot.navigationEntries.indices.contains(index),
              snapshot.navigationEntries[index].itemID == record.itemID else { return }
        guard request.maximumPixelSize == currentPixelEdge,
              request.renderKey?.itemID == record.itemID,
              request.renderKey?.revision == image.revision,
              image.itemID == record.itemID else {
            fail(index: index, token: token)
            return
        }
        records[index]?.result = (request, image)
        records[index]?.task = nil
        onResult?(index, request, image)
    }

    private func fail(index: Int, token: UUID) {
        guard records[index]?.token == token else { return }
        records[index]?.task = nil
        onFailure?(index)
    }

    func result(at index: Int) -> (ImageDecodeRequest, DecodedImage)? { records[index]?.result }
    func token(at index: Int) -> UUID? { records[index]?.token }

    func stop() { cancelAll(); snapshot = nil }
    private func cancelAll() {
        for record in records.values { record.task?.cancel() }
        records.removeAll()
    }
    deinit { for record in records.values { record.task?.cancel() } }
}
