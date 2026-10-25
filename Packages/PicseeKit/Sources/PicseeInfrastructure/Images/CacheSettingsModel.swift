import Foundation
import Observation

@MainActor @Observable
public final class CacheSettingsModel {
    public private(set) var sizeBytes: Int64?
    public private(set) var isMeasuring = false
    public private(set) var diagnostic: String?
    private let cache: ThumbnailDiskCache
    private var refreshSequence: UInt64 = 0

    public init(cache: ThumbnailDiskCache) { self.cache = cache }
    public func refresh() async {
        await refresh(measureBytes: { [cache] in try await cache.sizeBytes() })
    }

    func refresh(measureBytes: @escaping @Sendable () async throws -> Int64) async {
        refreshSequence &+= 1
        let sequence = refreshSequence
        sizeBytes = nil
        isMeasuring = true
        let clearIssue = await cache.deferredClearFailure()
        let writeIssue = await cache.writeDiagnostics().lastFailure
        let measured: Int64?
        do { measured = try await measureBytes() }
        catch { measured = nil }
        guard sequence == refreshSequence else { return }
        sizeBytes = measured
        diagnostic = clearIssue ?? writeIssue
        isMeasuring = false
    }

    public func clear() async {
        await clear(onWaitRegistered: nil)
    }

    func clear(onWaitRegistered: (@Sendable () -> Void)?) async {
        refreshSequence &+= 1
        sizeBytes = nil
        isMeasuring = true
        var clearFailure: String?
        do { try await cache.clear() }
        catch { clearFailure = String(describing: error) }
        if clearFailure == nil {
            if let onWaitRegistered {
                await cache.waitForPendingDeletions(onRegistered: onWaitRegistered)
            } else {
                await cache.waitForPendingDeletions()
            }
        }
        await refresh()
        if let clearFailure { diagnostic = clearFailure }
    }
}
