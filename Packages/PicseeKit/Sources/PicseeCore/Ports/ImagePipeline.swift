import CoreGraphics
import Foundation

public struct ImageDecodeRequest: Sendable {
    public let fileURL: URL
    /// Longest edge in pixels; callers convert viewport points using backing scale.
    public let maximumPixelSize: Int

    public init(fileURL: URL, maximumPixelSize: Int) {
        self.fileURL = fileURL
        self.maximumPixelSize = maximumPixelSize
    }
}

public struct DecodedImage: Sendable {
    public let image: CGImage
    public let sourcePixelSize: CGSize

    public init(image: CGImage, sourcePixelSize: CGSize) {
        self.image = image
        self.sourcePixelSize = sourcePixelSize
    }
}

/// Request boundary: admission/cancellation policy can replace the first executor.
public protocol ImagePipeline: Sendable {
    func image(for request: ImageDecodeRequest) async throws -> DecodedImage
}
