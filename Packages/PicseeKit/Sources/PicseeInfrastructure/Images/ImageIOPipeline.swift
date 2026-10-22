import CoreGraphics
import Foundation
import ImageIO
import os
import PicseeCore

public enum ImageDecodeError: Error, Equatable {
    case budgetExceeded
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
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: !request.isPreview,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: request.maximumPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(request.fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageDecodeError.unreadableImage
        }
        _ = try DecodeBudget.sourceCost(width: width, height: height,
            budget: request.sourceByteBudget ?? DecodeConfiguration().budget)
        var thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        if thumbnail == nil {
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
            thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        guard let image = thumbnail else { throw ImageDecodeError.unreadableImage }
        let rotated = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
        return DecodedImage(image: image, sourcePixelSize: CGSize(width: rotated ? height : width, height: rotated ? width : height),
                            formatIdentifier: CGImageSourceGetType(source) as String?)
    }
}

public final class ImageIOPipeline: ImagePipeline, Sendable {
    private let configuration: DecodeConfiguration
    private let executor: OperationDecodeExecutor
    private let admission: DecodeAdmission
    public init(decoder: any ImageDecoding = ImageIODecoder(), configuration: DecodeConfiguration = DecodeConfiguration()) {
        self.configuration = configuration
        let executor = OperationDecodeExecutor(workers: configuration.workers)
        self.executor = executor
        admission = DecodeAdmission(configuration: configuration, executor: executor, decoder: RevisionReportingDecoder(decoder: decoder))
    }
    private func header(_ request: ImageDecodeRequest) async throws -> ImageSourceHeader {
        let budget = configuration.budget
        return try await withCheckedThrowingContinuation { continuation in
            executor.submit {
                continuation.resume(with: Result { try ImageSourceHeader.read(request, budget: budget) })
            }
        }
    }
    public func request(for fileURL: URL, maximumPixelSize: Int) async throws -> ImageDecodeRequest {
        try Task.checkCancellation()
        let header = try await header(ImageDecodeRequest(fileURL: fileURL, maximumPixelSize: maximumPixelSize))
        let key = await admission.key(for: fileURL, revision: header.revision, maximumPixelSize: maximumPixelSize)
        return ImageDecodeRequest(fileURL: fileURL, maximumPixelSize: maximumPixelSize, renderKey: key)
    }
    public func image(for request: ImageDecodeRequest) async throws -> DecodedImage {
        try Task.checkCancellation()
        let header = try await header(request)
        let key = await admission.key(for: request.fileURL, revision: header.revision, maximumPixelSize: request.maximumPixelSize, isPreview: request.isPreview)
        // An explicit request revision must still match at the last predecode check.
        if let requested = request.renderKey, requested != key { throw ImageDecodeError.invalidRequest }
        let cost = try DecodeBudget.sourceCost(width: header.width, height: header.height, budget: configuration.budget)
        let admittedRequest = ImageDecodeRequest(fileURL: request.fileURL, maximumPixelSize: request.maximumPixelSize,
            renderKey: key, priority: request.priority, sourceByteBudget: cost, isPreview: request.isPreview)
        return try await admission.image(admittedRequest, key: key, cost: cost,
            heavy: DecodeBudget.isHeavy(width: header.width, height: header.height), priority: request.priority)
    }
}

/// Runs inside the bounded executor, including the post-decode filesystem read.
private struct RevisionReportingDecoder: ImageDecoding {
    let decoder: any ImageDecoding
    func decode(_ request: ImageDecodeRequest) throws -> DecodedImage {
        let decoded = try decoder.decode(request)
        let attributes = try FileManager.default.attributesOfItem(atPath: request.fileURL.path)
        guard let size = attributes[.size] as? NSNumber else { throw ImageDecodeError.unreadableImage }
        return DecodedImage(image: decoded.image, sourcePixelSize: decoded.sourcePixelSize,
            formatIdentifier: decoded.formatIdentifier,
            revision: FileRevision(byteCount: size.intValue, modificationDate: attributes[.modificationDate] as? Date))
    }
}
