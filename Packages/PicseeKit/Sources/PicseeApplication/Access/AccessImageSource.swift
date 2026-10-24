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
    public func image(maximumPixelSize: Int, isPreview: Bool = false) async throws -> (ImageDecodeRequest, DecodedImage) {
        guard !closed else { throw FileAccessError.startFailed }
        pending += 1
        let file: URL
        switch request { case .fileGrant(let url), .root(_, let url): file = url }
        let pipeline = pipeline
        let cacheProvider = pipeline as? any ThumbnailCacheProviding
        let thumbnailCache = cacheProvider?.thumbnailCache
        do {
            let result = try await access.withLease(request) { lease in
                let root = lease.rootID.map { ItemIdentityRoot(id: $0, url: lease.url) }
                let prepared = try await pipeline.request(for: file, maximumPixelSize: maximumPixelSize, identityRoot: root)
                try Task.checkCancellation()
                let request = ImageDecodeRequest(fileURL: file, maximumPixelSize: maximumPixelSize,
                                                 renderKey: prepared.renderKey, isPreview: isPreview, identityRoot: root)
                var ticket: ThumbnailCacheTicket?
                if let thumbnailCache {
                    do { ticket = try await thumbnailCache.prepare(request) }
                    catch is CancellationError { throw CancellationError() }
                    catch { ticket = nil } // Re-creatable cache failure cannot block source decoding.
                    if let ticket {
                        do {
                            if let cached = try await thumbnailCache.load(ticket),
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
