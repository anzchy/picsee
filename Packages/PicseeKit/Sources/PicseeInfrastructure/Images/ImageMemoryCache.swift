import CoreGraphics
import Foundation
import PicseeCore

struct ImageCacheRequest: Sendable {
    let key: RenderKey
    let id: UUID
    let image: DecodedImage?
}

struct ImageCacheUsage: Equatable, Sendable {
    let entries: Int
    let previewBytes: Int
    let detailBytes: Int
    var totalBytes: Int { previewBytes + detailBytes }
}

/// Shared process-local pixel storage. Reads remain internal to the image pipeline.
public actor ImageMemoryCache {
    private struct Entry {
        let key: RenderKey
        let image: DecodedImage
    }
    private let capacity: Int
    // Oldest first; keys use complete session value equality, without an encoding or digest.
    private var entries: [Entry] = []
    private var pending: [UUID: RenderKey] = [:]
    public init(capacity: Int) { precondition(capacity >= 0); self.capacity = capacity }
    func image(for key: RenderKey) -> DecodedImage? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.image
    }
    func insert(_ image: DecodedImage, for key: RenderKey) {
        guard image.image.bytesPerRow * image.image.height <= capacity else { return }
        remove(key)
        entries.append(Entry(key: key, image: image))
        while usage().totalBytes > capacity { entries.removeFirst() }
    }
    func remove(_ key: RenderKey) { entries.removeAll { $0.key == key } }
    func lookup(_ key: RenderKey) -> ImageCacheRequest {
        entries.removeAll { $0.key.itemID == key.itemID && $0.key.revision != key.revision }
        pending = pending.filter { $0.value.itemID != key.itemID || $0.value.revision == key.revision }
        let request = ImageCacheRequest(key: key, id: UUID(), image: image(for: key))
        if request.image == nil { pending[request.id] = key }
        return request
    }
    func finish(_ request: ImageCacheRequest, image: DecodedImage?) -> DecodedImage? {
        guard pending.removeValue(forKey: request.id) == request.key,
              let image, !Task.isCancelled, image.itemID == request.key.itemID,
              image.revision == request.key.revision else { return nil }
        // Independent waiters can complete after admission removed its shared job. Keep one buffer.
        if let retained = entries.first(where: { $0.key == request.key }) { return retained.image }
        insert(image, for: request.key)
        return image
    }
    func usage() -> ImageCacheUsage {
        var seen: Set<ObjectIdentifier> = [], preview = 0, detail = 0
        // A shared buffer is attributed to detail while any detail key retains it.
        for entry in entries where !entry.key.isPreview {
            if seen.insert(ObjectIdentifier(entry.image.image)).inserted {
                detail += entry.image.image.bytesPerRow * entry.image.image.height
            }
        }
        for entry in entries where entry.key.isPreview {
            if seen.insert(ObjectIdentifier(entry.image.image)).inserted {
                preview += entry.image.image.bytesPerRow * entry.image.image.height
            }
        }
        return ImageCacheUsage(entries: entries.count, previewBytes: preview, detailBytes: detail)
    }
}
