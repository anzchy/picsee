import CoreGraphics
import Foundation
import ImageIO
import PicseeCore

public enum ImageDecodeError: Error, Equatable {
    case invalidRequest
    case unreadableImage
}

/// Synchronous decoding boundary; scheduling belongs to the pipeline executor.
public protocol ImageDecoding: Sendable {
    func decode(_ request: ImageDecodeRequest) throws -> DecodedImage
}

public struct ImageIODecoder: ImageDecoding {
    public init() { }
    public func decode(_ request: ImageDecodeRequest) throws -> DecodedImage {
        guard request.fileURL.isFileURL && request.maximumPixelSize > 0 else {
            throw ImageDecodeError.invalidRequest
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: request.maximumPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(request.fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageDecodeError.unreadableImage
        }
        let rotated = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
        return DecodedImage(image: image, sourcePixelSize: CGSize(width: rotated ? height : width, height: rotated ? width : height))
    }
}

public final class ImageIOPipeline: ImagePipeline, Sendable {
    private let decoder: any ImageDecoding
    private let queue: OperationQueue

    public init(decoder: any ImageDecoding = ImageIODecoder()) {
        self.decoder = decoder
        queue = OperationQueue()
        queue.name = "io.github.anzchy.picsee.first-image-decode"
        queue.maxConcurrentOperationCount = 1
    }
    public func image(for request: ImageDecodeRequest) async throws -> DecodedImage {
        let decoder = decoder
        return try await withCheckedThrowingContinuation { continuation in
            queue.addOperation {
                continuation.resume(with: Result { try decoder.decode(request) })
            }
        }
    }
}
