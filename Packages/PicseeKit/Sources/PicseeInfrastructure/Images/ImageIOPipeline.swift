import CoreGraphics
import Foundation
import ImageIO
import os
import PicseeCore
import UniformTypeIdentifiers

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
            // Preview first asks only for embedded pixels; the fallback below generates from the source.
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
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
        guard let image = thumbnail, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw ImageDecodeError.unreadableImage }
        let rotated = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
        return DecodedImage(image: image, sourcePixelSize: CGSize(width: rotated ? height : width, height: rotated ? width : height),
                            formatIdentifier: CGImageSourceGetType(source) as String?)
    }
}

public final class ImageIOPipeline: ImagePipeline, Sendable {
    private let configuration: DecodeConfiguration
    private let identityResolver: any ItemIdentityResolving
    private let executor: OperationDecodeExecutor
    private let admission: DecodeAdmission
    public init(decoder: any ImageDecoding = ImageIODecoder(), configuration: DecodeConfiguration = DecodeConfiguration(),
                identityResolver: any ItemIdentityResolving = FileItemIdentityResolver()) {
        self.configuration = configuration
        self.identityResolver = identityResolver
        let executor = OperationDecodeExecutor(workers: configuration.workers)
        self.executor = executor
        admission = DecodeAdmission(configuration: configuration, executor: executor, decoder: RevisionReportingDecoder(decoder: decoder))
    }
    private func header(_ request: ImageDecodeRequest) async throws -> ImageSourceHeader {
        guard request.fileURL.isFileURL, request.maximumPixelSize > 0 else {
            throw ImageLoadError(.sourceChanged, itemID: request.renderKey?.itemID, revision: request.renderKey?.revision)
        }
        let item = try await identityResolver.identity(for: request.fileURL)
        let budget = configuration.budget
        return try await withCheckedThrowingContinuation { continuation in
            executor.submit {
                continuation.resume(with: Result {
                    do { return try ImageSourceHeader.read(request, budget: budget, itemID: item) }
                    catch {
                        let revision = try? FileRevisionReader.read(request.fileURL)
                        let disappeared = request.renderKey != nil && revision == nil && error as? ImageDecodeError == .unreadableImage
                        let failure: any Error = disappeared ? ImageDecodeError.invalidRequest : error
                        throw loadFailure(failure, request: request, revision: revision, itemID: request.renderKey?.itemID ?? item,
                                          unreadableKind: failure as? ImageDecodeError == .unreadableImage
                                            ? imageFailureKind(request.fileURL) : .corruptImage)
                    }
                })
            }
        }
    }
    public func request(for fileURL: URL, maximumPixelSize: Int) async throws -> ImageDecodeRequest {
        if Task.isCancelled { throw ImageLoadError(.cancelled) }
        let header = try await header(ImageDecodeRequest(fileURL: fileURL, maximumPixelSize: maximumPixelSize))
        let key = await admission.key(for: header.itemID, revision: header.revision, maximumPixelSize: maximumPixelSize)
        return ImageDecodeRequest(fileURL: fileURL, maximumPixelSize: maximumPixelSize, renderKey: key)
    }
    public func image(for request: ImageDecodeRequest) async throws -> DecodedImage {
        if Task.isCancelled { throw ImageLoadError(.cancelled, itemID: request.renderKey?.itemID, revision: request.renderKey?.revision) }
        let header = try await header(request)
        let key = await admission.key(for: header.itemID, revision: header.revision, maximumPixelSize: request.maximumPixelSize, isPreview: request.isPreview)
        // An explicit request revision must still match at the last predecode check.
        if let requested = request.renderKey, requested != key {
            throw ImageLoadError(.sourceChanged, itemID: requested.itemID, revision: header.revision)
        }
        let cost = try DecodeBudget.sourceCost(width: header.width, height: header.height, budget: configuration.budget)
        let admittedRequest = ImageDecodeRequest(fileURL: request.fileURL, maximumPixelSize: request.maximumPixelSize,
            renderKey: key, priority: request.priority, sourceByteBudget: cost, isPreview: request.isPreview)
        do {
            return try await admission.image(admittedRequest, key: key, cost: cost,
                heavy: DecodeBudget.isHeavy(width: header.width, height: header.height), priority: request.priority)
        } catch { throw loadFailure(error, request: admittedRequest, revision: header.revision, unreadableKind: .corruptImage) }
    }
}

/// Runs inside the bounded executor, including the post-decode filesystem read.
private struct RevisionReportingDecoder: ImageDecoding {
    let decoder: any ImageDecoding
    func decode(_ request: ImageDecodeRequest) throws -> DecodedImage {
        let decoded = try decoder.decode(request)
        return DecodedImage(image: decoded.image, sourcePixelSize: decoded.sourcePixelSize,
            formatIdentifier: decoded.formatIdentifier, revision: try FileRevisionReader.read(request.fileURL),
            itemID: request.renderKey?.itemID)
    }
}

/// Called only on the bounded executor. Extensions are not evidence of an image format.
private func imageFailureKind(_ url: URL) -> ImageLoadError.Kind {
    if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetType(source) != nil {
        return .corruptImage
    }
    // A recognised signature identifies damaged PNG data even if ImageIO cannot construct a source.
    let file = try? FileHandle(forReadingFrom: url)
    let prefix = try? file?.read(upToCount: 512)
    try? file?.close()
    if prefix?.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) == true { return .corruptImage }
    // With no decoder signature, binary data advertised as an image is treated as corrupt.
    // Plain text remains unsupported regardless of its suffix (including a misleading .jpg).
    if prefix?.contains(0) == true, UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
        return .corruptImage
    }
    return .unsupportedFormat
}

private func loadFailure(_ error: Error, request: ImageDecodeRequest, revision: FileRevision?, itemID: ItemID? = nil,
                         unreadableKind: ImageLoadError.Kind) -> Error {
    let kind: ImageLoadError.Kind
    switch error {
    case ImageDecodeError.budgetExceeded: kind = .resourceLimit
    case ImageDecodeError.invalidRequest: kind = .sourceChanged
    case ImageDecodeError.unreadableImage: kind = unreadableKind
    case is CancellationError: kind = .cancelled
    default: return error // Includes FileAccess errors; never reinterpret permission failures.
    }
    return ImageLoadError(kind, itemID: itemID ?? request.renderKey?.itemID, revision: revision ?? request.renderKey?.revision)
}
