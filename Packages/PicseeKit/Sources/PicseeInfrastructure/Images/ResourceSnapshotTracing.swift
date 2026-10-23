public struct ResourceSnapshot: Equatable, Sendable {
    public let entries: Int
    public let previewBytes: Int
    public let detailBytes: Int
    public let pinnedBytes: Int
    public let reservedBytes: Int
    public let running: Int
    public let waiting: Int
    public let pressure: MemoryPressureLevel
    public var rss: String { "unknown" }
    public var retainedObjects: String { "unknown" }
}

/// A process-wide telemetry sink. Lookup fields contain no user identity or location.
public protocol ResourceSnapshotTracing: Sendable {
    func lookup(isPreview: Bool, hit: Bool)
    func snapshot(_ snapshot: ResourceSnapshot)
}

extension ResourceSnapshotTracing { public func snapshot(_ snapshot: ResourceSnapshot) { } }

struct ResourceSnapshotContext: Sendable {
    let tracer: any ResourceSnapshotTracing
    let activity: DecodeActivity
}
