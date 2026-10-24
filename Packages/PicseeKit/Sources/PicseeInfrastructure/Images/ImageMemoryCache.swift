import CoreGraphics
import Foundation
import PicseeCore

struct ImageCacheRequest: Sendable {
    let key: RenderKey
    let id: UUID
    let image: DecodedImage?
    let sourceChanged: Bool
    let requiresSourceValidation: Bool
    init(key: RenderKey, id: UUID, image: DecodedImage?, sourceChanged: Bool = false, requiresSourceValidation: Bool = false) {
        self.key = key; self.id = id; self.image = image; self.sourceChanged = sourceChanged
        self.requiresSourceValidation = requiresSourceValidation
    }
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
    private var pressurePolicy: MemoryPressurePolicy
    // Oldest first; keys use complete session value equality, without an encoding or digest.
    private var entries: [Entry] = []
    private var pending: [UUID: RenderKey] = [:]
    private var epoch = 0
    private var observations: [UUID: (epoch: Int, itemID: ItemID?)] = [:]
    private var recent: [ItemID: (epoch: Int, revision: FileRevision)] = [:]
    public init(capacity: Int, pressureRecoveryDelay: TimeInterval = 5,
                pressureClock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        precondition(capacity >= 0); self.capacity = capacity; limit = capacity
        pressurePolicy = MemoryPressurePolicy(recoveryDelay: pressureRecoveryDelay, clock: pressureClock)
    }
    func pressure(_ level: MemoryPressureLevel, context: ResourceSnapshotContext? = nil) {
        let previous = pressurePolicy.level
        pressurePolicy.update(level)
        guard previous != pressurePolicy.level else { return }
        emit(context)
        switch level {
        case .normal: trim(to: capacity, context: context)
        case .warning: trim(to: capacity / 2, context: context)
        case .critical: trim(to: 0, context: context)
        }
    }
    func permits(_ priority: DecodePriority) -> Bool { pressurePolicy.permits(priority) }
    func image(for key: RenderKey, context: ResourceSnapshotContext? = nil) -> DecodedImage? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        emit(context)
        return entry.image
    }
    func insert(_ image: DecodedImage, for key: RenderKey, context: ResourceSnapshotContext? = nil) {
        guard image.image.bytesPerRow * image.image.height <= capacity else { return }
        guard pinCount(for: key) == 0 else { return }
        remove(key, context: context)
        entries.append(Entry(key: key, image: image))
        emit(context)
        trim(to: limit, context: context)
    }
    func remove(_ key: RenderKey, context: ResourceSnapshotContext? = nil) {
        guard let index = entries.firstIndex(where: { $0.key == key && $0.pins == 0 }) else { return }
        entries.remove(at: index); emit(context)
    }
    func pin(_ key: RenderKey, image: DecodedImage, context: ResourceSnapshotContext? = nil) {
        guard image.itemID == key.itemID, image.revision == key.revision else { return }
        if let index = entries.firstIndex(where: { $0.key == key }) {
            if entries[index].image.image !== image.image,
               !entries[index].variants.contains(where: { $0.image === image.image }) {
                entries[index].variants.append(image)
            }
            entries[index].pins += 1
        } else { entries.append(Entry(key: key, image: image, pins: 1)) }
        emit(context)
    }
    func unpin(_ key: RenderKey, context: ResourceSnapshotContext? = nil) {
        guard let index = entries.firstIndex(where: { $0.key == key }), entries[index].pins > 0 else { return }
        entries[index].pins -= 1
        emit(context)
        if entries[index].pins == 0 {
            if !entries[index].variants.isEmpty { entries[index].variants.removeAll(); emit(context) }
            if entries[index].stale || entries[index].image.image.bytesPerRow * entries[index].image.image.height > capacity {
                entries.remove(at: index)
                emit(context)
            }
            trim(to: limit, context: context)
        }
    }
    func pinCount(for key: RenderKey) -> Int { entries.first(where: { $0.key == key })?.pins ?? 0 }
    func trim(to limit: Int, context: ResourceSnapshotContext? = nil) {
        precondition(limit >= 0)
        self.limit = min(capacity, limit)
        while self.limit == 0 || usage().unpinnedBytes > self.limit {
            guard let index = entries.firstIndex(where: { $0.pins == 0 }) else { break }
            entries.remove(at: index)
            emit(context)
        }
    }
    func withObservation<T: Sendable>(itemID: ItemID? = nil,
        _ operation: @Sendable (UUID) async throws -> T) async rethrows -> T {
        let id = UUID()
        observations[id] = (epoch, itemID)
        defer { observations[id] = nil; pruneObservations() }
        return try await operation(id)
    }
    private func pruneObservations() {
        // Only a still-running validation can need an intervening revision, including after eviction.
        recent = recent.filter { item, value in
            observations.values.contains { ($0.itemID == nil || $0.itemID == item) && $0.epoch < value.epoch }
        }
    }
    func lookup(_ key: RenderKey, observation: UUID? = nil, context: ResourceSnapshotContext? = nil) -> ImageCacheRequest {
        guard !entries.contains(where: { $0.key.itemID == key.itemID && $0.key.revision == key.revision && $0.stale }) else {
            return ImageCacheRequest(key: key, id: UUID(), image: nil, sourceChanged: true)
        }
        if let observation {
            guard let validation = observations[observation],
                  validation.itemID == nil || validation.itemID == key.itemID else {
                return ImageCacheRequest(key: key, id: UUID(), image: nil, sourceChanged: true)
            }
            if let latest = recent[key.itemID], latest.epoch > validation.epoch, latest.revision != key.revision {
                // Either header may have been delayed. Only a new leased source read can resolve this.
                return ImageCacheRequest(key: key, id: UUID(), image: nil, sourceChanged: true, requiresSourceValidation: true)
            }
        }
        // Revision values are opaque. Reject conflicting observations made during this validation,
        // rather than assuming either mtimes or request-start order identify the newest header.
        epoch += 1
        if let observation { observations[observation]?.itemID = key.itemID }
        recent[key.itemID] = (epoch, key.revision)
        pruneObservations()
        for index in entries.indices where entries[index].key.itemID == key.itemID {
            entries[index].stale = entries[index].stale || entries[index].key.revision != key.revision
        }
        while let index = entries.firstIndex(where: { $0.stale && $0.pins == 0 }) {
            entries.remove(at: index); emit(context)
        }
        pending = pending.filter { $0.value.itemID != key.itemID || $0.value.revision == key.revision }
        let request = ImageCacheRequest(key: key, id: UUID(), image: image(for: key, context: context))
        if request.image == nil { pending[request.id] = key }
        context?.tracer.lookup(isPreview: key.isPreview, hit: request.image != nil)
        return request
    }
    func finish(_ request: ImageCacheRequest, image: DecodedImage?, context: ResourceSnapshotContext? = nil) -> DecodedImage? {
        guard pending.removeValue(forKey: request.id) == request.key,
              let image, !Task.isCancelled, image.itemID == request.key.itemID,
              image.revision == request.key.revision else { return nil }
        // Independent waiters can complete after admission removed its shared job. Keep one buffer.
        if let retained = entries.first(where: { $0.key == request.key }) { return retained.image }
        insert(image, for: request.key, context: context)
        return image
    }
    private func emit(_ context: ResourceSnapshotContext?) {
        guard let context else { return }
        let state = usage(), activity = context.activity
        context.tracer.snapshot(ResourceSnapshot(entries: state.entries, previewBytes: state.previewBytes,
            detailBytes: state.detailBytes, pinnedBytes: state.pinnedBytes, reservedBytes: activity.reservedBytes,
            running: activity.running, waiting: activity.waiting, pressure: pressurePolicy.level))
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
