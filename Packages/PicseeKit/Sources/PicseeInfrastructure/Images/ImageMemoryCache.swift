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
    let pinnedBytes: Int
    init(entries: Int, previewBytes: Int, detailBytes: Int, pinnedBytes: Int = 0) {
        self.entries = entries; self.previewBytes = previewBytes; self.detailBytes = detailBytes; self.pinnedBytes = pinnedBytes
    }
    var totalBytes: Int { previewBytes + detailBytes }
    var unpinnedBytes: Int { totalBytes - pinnedBytes }
}

/// Shared process-local pixel storage. Reads remain internal to the image pipeline.
public actor ImageMemoryCache {
    private struct Entry {
        let key: RenderKey
        let image: DecodedImage
        var pins = 0
        var variants: [DecodedImage] = []
        var stale = false
    }
    private let capacity: Int
    private var limit: Int
    // Oldest first; keys use complete session value equality, without an encoding or digest.
    private var entries: [Entry] = []
    private var pending: [UUID: RenderKey] = [:]
    public init(capacity: Int) { precondition(capacity >= 0); self.capacity = capacity; limit = capacity }
    func image(for key: RenderKey) -> DecodedImage? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.image
    }
    func insert(_ image: DecodedImage, for key: RenderKey) {
        guard image.image.bytesPerRow * image.image.height <= capacity else { return }
        guard pinCount(for: key) == 0 else { return }
        remove(key)
        entries.append(Entry(key: key, image: image))
        trim(to: limit)
    }
    func remove(_ key: RenderKey) { entries.removeAll { $0.key == key && $0.pins == 0 } }
    func pin(_ key: RenderKey, image: DecodedImage) {
        guard image.itemID == key.itemID, image.revision == key.revision else { return }
        if let index = entries.firstIndex(where: { $0.key == key }) {
            if entries[index].image.image !== image.image,
               !entries[index].variants.contains(where: { $0.image === image.image }) {
                entries[index].variants.append(image)
            }
            entries[index].pins += 1
        } else { entries.append(Entry(key: key, image: image, pins: 1)) }
    }
    func unpin(_ key: RenderKey) {
        guard let index = entries.firstIndex(where: { $0.key == key }), entries[index].pins > 0 else { return }
        entries[index].pins -= 1
        if entries[index].pins == 0 {
            entries[index].variants.removeAll()
            if entries[index].stale || entries[index].image.image.bytesPerRow * entries[index].image.image.height > capacity {
                entries.remove(at: index)
            }
            trim(to: limit)
        }
    }
    func pinCount(for key: RenderKey) -> Int { entries.first(where: { $0.key == key })?.pins ?? 0 }
    func trim(to limit: Int) {
        precondition(limit >= 0)
        self.limit = min(capacity, limit)
        while self.limit == 0 || usage().unpinnedBytes > self.limit {
            guard let index = entries.firstIndex(where: { $0.pins == 0 }) else { break }
            entries.remove(at: index)
        }
    }
    func lookup(_ key: RenderKey) -> ImageCacheRequest {
        for index in entries.indices where entries[index].key.itemID == key.itemID {
            entries[index].stale = entries[index].key.revision != key.revision
        }
        entries.removeAll { $0.stale && $0.pins == 0 }
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
        var seen: Set<ObjectIdentifier> = [], pinned: Set<ObjectIdentifier> = []
        var preview = 0, detail = 0, pinnedBytes = 0
        // A shared buffer is attributed to detail while any detail key retains it.
        for isPreview in [false, true] {
            for entry in entries where entry.key.isPreview == isPreview {
                for image in [entry.image] + entry.variants {
                    let id = ObjectIdentifier(image.image), cost = image.image.bytesPerRow * image.image.height
                    if seen.insert(id).inserted { if isPreview { preview += cost } else { detail += cost } }
                    if entry.pins > 0, pinned.insert(id).inserted { pinnedBytes += cost }
                }
            }
        }
        return ImageCacheUsage(entries: entries.count, previewBytes: preview, detailBytes: detail, pinnedBytes: pinnedBytes)
    }
}
