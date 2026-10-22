import CoreGraphics
import Foundation

public enum DecodePriority: Int, Sendable { case prefetch, visible, current }

public struct ImageDecodeRequest: Sendable {
    /// Pixel allocation ceiling for this admitted decode, rechecked against its own header.
    public let sourceByteBudget: Int?
    public let renderKey: RenderKey?
    public let priority: DecodePriority
    public let fileURL: URL
    /// Longest edge in pixels; callers convert viewport points using backing scale.
    public let maximumPixelSize: Int

    public init(fileURL: URL, maximumPixelSize: Int, renderKey: RenderKey? = nil, priority: DecodePriority = .current, sourceByteBudget: Int? = nil) {
        self.sourceByteBudget = sourceByteBudget
        self.renderKey = renderKey
        self.priority = priority
        self.fileURL = fileURL
        self.maximumPixelSize = maximumPixelSize
    }
}

public struct DecodedImage: Sendable {
    public let revision: FileRevision?
    public let formatIdentifier: String?
    public let image: CGImage
    public let sourcePixelSize: CGSize

    public init(image: CGImage, sourcePixelSize: CGSize, formatIdentifier: String? = nil, revision: FileRevision? = nil) {
        self.revision = revision
        self.formatIdentifier = formatIdentifier
        self.image = image
        self.sourcePixelSize = sourcePixelSize
    }
}

/// Request boundary: admission/cancellation policy can replace the first executor.
public protocol ImagePipeline: Sendable {
    func request(for fileURL: URL, maximumPixelSize: Int) async throws -> ImageDecodeRequest
    func image(for request: ImageDecodeRequest) async throws -> DecodedImage
}
