import Foundation
import PicseeCore

/// A displayed image owns a lease; each decode obtains another before even asking the pipeline.
public actor AccessImageSource {
    private let access: any AccessLeasing
    private let pipeline: any ImagePipeline
    private let request: AccessRequest
    private var display: AccessLease?
    private var pending = 0
    private var closed = false
    public static func open(_ request: AccessRequest, access: any AccessLeasing,
                            pipeline: any ImagePipeline) async throws -> AccessImageSource {
        let lease = try await access.acquire(request)
        do {
            try Task.checkCancellation()
            return AccessImageSource(request: request, access: access, pipeline: pipeline, display: lease)
        } catch { await access.release(lease); throw error }
    }
    private init(request: AccessRequest, access: any AccessLeasing, pipeline: any ImagePipeline, display: AccessLease) {
        self.request = request; self.access = access; self.pipeline = pipeline; self.display = display
    }
    public func image(maximumPixelSize: Int, isPreview: Bool = false,
                      priority: DecodePriority = .current) async throws -> (ImageDecodeRequest, DecodedImage) {
        try await image(isPreview: isPreview, priority: priority) { pipeline, file, root in
            try await pipeline.request(for: file, maximumPixelSize: maximumPixelSize, identityRoot: root)
        }
    }
    /// The edge follows the source's ratio when the pipeline can read the header first; otherwise the fallback.
    public func image(covering coverage: ThumbnailCoverage, isPreview: Bool = false,
                      priority: DecodePriority = .current) async throws -> (ImageDecodeRequest, DecodedImage) {
        try await image(isPreview: isPreview, priority: priority) { pipeline, file, root in
            if let sizing = pipeline as? any CoverageRequesting {
                return try await sizing.request(for: file, covering: coverage, identityRoot: root)
            }
            return try await pipeline.request(for: file, maximumPixelSize: coverage.fallbackEdge, identityRoot: root)
        }
    }
    private func image(isPreview: Bool, priority: DecodePriority,
                       prepare: @escaping @Sendable (any ImagePipeline, URL, ItemIdentityRoot?) async throws -> ImageDecodeRequest)
        async throws -> (ImageDecodeRequest, DecodedImage) {
        guard !closed else { throw FileAccessError.startFailed }
        pending += 1
        let pipeline = pipeline
        let cacheProvider = pipeline as? any ThumbnailCacheProviding
        let thumbnailCache = cacheProvider?.thumbnailCache
        do {
            let result = try await access.withLease(request) { lease in
                let file: URL
                switch request {
                case .fileGrant(let original): file = lease.resolvedFileURL ?? original
                case .root(_, let url): file = url
                }
                let root = lease.rootID.map { ItemIdentityRoot(id: $0, url: lease.url) }
                let prepared = try await prepare(pipeline, file, root)
                let maximumPixelSize = prepared.maximumPixelSize
                try Task.checkCancellation()
                let request = ImageDecodeRequest(fileURL: file, maximumPixelSize: maximumPixelSize,
                                                 renderKey: prepared.renderKey, priority: priority,
                                                 isPreview: isPreview, identityRoot: root)
                var ticket: ThumbnailCacheTicket?
                if let thumbnailCache {
                    do { ticket = try await thumbnailCache.prepare(request) }
                    catch is CancellationError { throw CancellationError() }
                    catch { ticket = nil } // Re-creatable cache failure cannot block source decoding.
                    if let ticket {
                        do {
                            if let cached = try await cacheProvider?.cachedImage(for: ticket),
                               let key = request.renderKey,
                               cached.itemID == key.itemID, cached.revision == key.revision,
                               cached.image.width > 0, cached.image.height > 0,
                               cached.image.width <= maximumPixelSize,
                               cached.image.height <= maximumPixelSize,
                               cached.sourcePixelSize.width > 0, cached.sourcePixelSize.height > 0,
                               cached.sourcePixelSize.width.isFinite, cached.sourcePixelSize.height.isFinite {
                                try Task.checkCancellation()
                                return (request, cached)
                            }
                        } catch is CancellationError { throw CancellationError() }
                        catch { /* Source decoding remains authoritative on cache failure. */ }
                    }
                }
                try Task.checkCancellation()
                // A durable miss proves current source bytes, but a session-keyed memory hit
                // or shared in-flight decode has no proof that its pixels came from those bytes.
                let image: DecodedImage
                if let cacheProvider, ticket != nil {
                    image = try await cacheProvider.imageFresh(for: request)
                } else {
                    image = try await pipeline.image(for: request)
                }
                try Task.checkCancellation()
                if let thumbnailCache, let ticket {
                    do { try await thumbnailCache.store(image, for: ticket) }
                    catch is CancellationError { throw CancellationError() }
                    catch let error as ImageLoadError where error.kind == .sourceChanged { throw error }
                    catch { /* The decoded source remains deliverable. */ }
                }
                try Task.checkCancellation()
                return (request, image)
            }
            pending -= 1
            await releaseIfClosed()
            return result
        } catch {
            pending -= 1; closed = true
            await releaseIfClosed()
            throw error
        }
    }
    public func close() async {
        closed = true
        await releaseIfClosed()
    }
    private func releaseIfClosed() async {
        if closed, pending == 0, let lease = display {
            display = nil
            await access.release(lease)
        }
    }
}
