/// A process-wide telemetry sink. Lookup fields contain no user identity or location.
public protocol ResourceSnapshotTracing: Sendable {
    func lookup(isPreview: Bool, hit: Bool)
}
