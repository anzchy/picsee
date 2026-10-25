import Foundation

/// Source evidence obtained while the caller holds an access lease.
public struct ThumbnailCacheTicket: Sendable {
    public let request: ImageDecodeRequest
    public let key: DurableThumbnailKey
    public let sourceSHA256: String
    public let generation: UInt64
    public init(request: ImageDecodeRequest, key: DurableThumbnailKey, sourceSHA256: String, generation: UInt64 = 0) {
        self.request = request; self.key = key; self.sourceSHA256 = sourceSHA256; self.generation = generation
    }
}

/// Called only by AccessImageSource inside its access.withLease operation.
public protocol ThumbnailCaching: Sendable {
    func prepare(_ request: ImageDecodeRequest) async throws -> ThumbnailCacheTicket?
    func load(_ ticket: ThumbnailCacheTicket) async throws -> DecodedImage?
    func store(_ image: DecodedImage, for ticket: ThumbnailCacheTicket) async throws
}

/// Configuration bridge: the public image methods on a provider never consult this cache.
package protocol ThumbnailCacheProviding: ImagePipeline {
    var thumbnailCache: (any ThumbnailCaching)? { get }
    /// Decode a disk miss from source without reusing session memory or an in-flight keyed decode.
    func imageFresh(for request: ImageDecodeRequest) async throws -> DecodedImage
}
