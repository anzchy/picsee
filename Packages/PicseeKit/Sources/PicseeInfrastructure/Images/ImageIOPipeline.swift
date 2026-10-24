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
        _ = try DecodeBudget.outputCost(width: width, height: height, maximumPixelSize: request.maximumPixelSize,
            bytesPerPixel: ImageSourceHeader.pixelBytes(properties), budget: request.sourceByteBudget ?? DecodeConfiguration().budget)
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

public final class ImageIOPipeline: ImagePipeline, ImagePresentationPinning, ThumbnailCacheProviding, Sendable {
    private let configuration: DecodeConfiguration
    private let rootResolvers = RootIdentityResolvers()
    private let identityResolver: any ItemIdentityResolving
    private let executor: OperationDecodeExecutor
    private let admission: DecodeAdmission
    private let cache: ImageMemoryCache
    private let cacheTrace: (any ResourceSnapshotTracing)?
    package let thumbnailCache: (any ThumbnailCaching)?
    public init(decoder: any ImageDecoding = ImageIODecoder(), configuration: DecodeConfiguration = DecodeConfiguration(),
                identityResolver: any ItemIdentityResolving = FileItemIdentityResolver(),
                cache: ImageMemoryCache? = nil, cacheTrace: (any ResourceSnapshotTracing)? = nil,
                thumbnailCache: (any ThumbnailCaching)? = nil,
                pressureClock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.configuration = configuration
        self.cache = cache ?? ImageMemoryCache(capacity: configuration.cacheCapacity,
            pressureRecoveryDelay: configuration.pressureRecoveryDelay, pressureClock: pressureClock)
        self.cacheTrace = cacheTrace
        self.thumbnailCache = thumbnailCache
        self.identityResolver = identityResolver
        let executor = OperationDecodeExecutor(workers: configuration.workers)
        self.executor = executor
        admission = DecodeAdmission(configuration: configuration, executor: executor, decoder: RevisionReportingDecoder(decoder: decoder))
    }
    private func snapshotContext() async -> ResourceSnapshotContext? {
        guard let cacheTrace else { return nil }
        return ResourceSnapshotContext(tracer: cacheTrace, activity: await admission.activity())
    }
    public func pin(_ key: RenderKey, image: DecodedImage) async {
        let context = await snapshotContext()
        await cache.pin(key, image: image, context: context)
    }
    public func unpin(_ key: RenderKey) async {
        let context = await snapshotContext()
        await cache.unpin(key, context: context)
    }
    public func memoryPressure(_ level: MemoryPressureLevel) async {
        let context = await snapshotContext()
        await cache.pressure(level, context: context)
    }
    private func header(_ request: ImageDecodeRequest) async throws -> ImageSourceHeader {
        guard request.fileURL.isFileURL, request.maximumPixelSize > 0 else {
            throw ImageLoadError(.sourceChanged, itemID: request.renderKey?.itemID, revision: request.renderKey?.revision)
        }
        let item: ItemID
        do {
            let resolver: any ItemIdentityResolving
            if let root = request.identityRoot { resolver = await rootResolvers.resolver(for: root) }
            else { resolver = identityResolver }
            item = try await resolver.identity(for: request.fileURL)
        }
        catch { throw loadFailure(error, request: request, revision: request.renderKey?.revision, unreadableKind: .corruptImage) }
        let budget = configuration.budget
        return try await withCheckedThrowingContinuation { continuation in
            executor.submit {
                continuation.resume(with: Result {
                    do { return try ImageSourceHeader.read(request, budget: budget, itemID: item) }
                    catch {
                        let revision: FileRevision
                        do { revision = try FileRevisionReader.read(request.fileURL) }
                        catch {
                            throw loadFailure(error, request: request, revision: request.renderKey?.revision,
                                              itemID: request.renderKey?.itemID ?? item, unreadableKind: .corruptImage)
                        }
                        throw loadFailure(error, request: request, revision: revision, itemID: request.renderKey?.itemID ?? item,
                                          unreadableKind: error as? ImageDecodeError == .unreadableImage
                                            ? imageFailureKind(request.fileURL) : .corruptImage)
                    }
                })
            }
        }
    }
    public func request(for fileURL: URL, maximumPixelSize: Int) async throws -> ImageDecodeRequest {
        try await request(for: fileURL, maximumPixelSize: maximumPixelSize, identityRoot: nil)
    }
    public func request(for fileURL: URL, maximumPixelSize: Int, identityRoot: ItemIdentityRoot?) async throws -> ImageDecodeRequest {
        if Task.isCancelled { throw ImageLoadError(.cancelled) }
        let header = try await header(ImageDecodeRequest(fileURL: fileURL, maximumPixelSize: maximumPixelSize, identityRoot: identityRoot))
        let key = await admission.key(for: header.itemID, revision: header.revision, maximumPixelSize: maximumPixelSize)
        return ImageDecodeRequest(fileURL: fileURL, maximumPixelSize: maximumPixelSize, renderKey: key, identityRoot: identityRoot)
    }
    public func image(for request: ImageDecodeRequest) async throws -> DecodedImage {
        try await cache.withObservation(itemID: request.renderKey?.itemID) { observation in
            try await self.image(for: request, observation: observation)
        }
    }
    private func lookup(_ request: ImageDecodeRequest, key: RenderKey, observation: UUID) async throws -> ImageCacheRequest {
        let context = await snapshotContext()
        let result = await cache.lookup(key, observation: observation, context: context)
        guard result.requiresSourceValidation else { return result }
        // One bounded reread, inside the caller's existing lease. Observe BEFORE reading so a
        // conflicting lookup during this validation still rejects us, including after eviction.
        return try await cache.withObservation(itemID: key.itemID) { freshObservation in
            let fresh = try await self.header(request)
            let freshKey = await self.admission.key(for: fresh.itemID, revision: fresh.revision,
                maximumPixelSize: request.maximumPixelSize, isPreview: request.isPreview)
            guard freshKey == key else {
                throw ImageLoadError(.sourceChanged, itemID: key.itemID, revision: fresh.revision)
            }
            if Task.isCancelled { throw ImageLoadError(.cancelled, itemID: key.itemID, revision: key.revision) }
            let context = await self.snapshotContext()
            return await self.cache.lookup(key, observation: freshObservation, context: context)
        }
    }
    private func image(for request: ImageDecodeRequest, observation: UUID) async throws -> DecodedImage {
        if Task.isCancelled { throw ImageLoadError(.cancelled, itemID: request.renderKey?.itemID, revision: request.renderKey?.revision) }
        let header = try await header(request)
        let key = await admission.key(for: header.itemID, revision: header.revision, maximumPixelSize: request.maximumPixelSize, isPreview: request.isPreview)
        // An explicit request revision must still match at the last predecode check.
        if let requested = request.renderKey, requested != key {
            throw ImageLoadError(.sourceChanged, itemID: requested.itemID, revision: header.revision)
        }
        guard await cache.permits(request.priority) else {
            throw ImageLoadError(.cancelled, itemID: key.itemID, revision: key.revision)
        }
        let cached = try await lookup(request, key: key, observation: observation)
        if cached.sourceChanged { throw ImageLoadError(.sourceChanged, itemID: key.itemID, revision: key.revision) }
        if let image = cached.image {
            if Task.isCancelled { throw ImageLoadError(.cancelled, itemID: key.itemID, revision: key.revision) }
            return image
        }
        let cost = try DecodeBudget.outputCost(width: header.width, height: header.height, maximumPixelSize: request.maximumPixelSize, bytesPerPixel: header.bytesPerPixel, budget: configuration.budget)
        let admittedRequest = ImageDecodeRequest(fileURL: request.fileURL, maximumPixelSize: request.maximumPixelSize,
            renderKey: key, priority: request.priority, sourceByteBudget: cost, isPreview: request.isPreview, identityRoot: request.identityRoot)
        do {
            let image = try await admission.image(admittedRequest, key: key, cost: cost,
                heavy: DecodeBudget.isHeavy(width: header.width, height: header.height), priority: request.priority)
            let context = await snapshotContext()
            let retained = await cache.finish(cached, image: image, context: context)
            try Task.checkCancellation()
            if retained == nil, image.itemID == key.itemID, image.revision == key.revision {
                throw ImageLoadError(.sourceChanged, itemID: key.itemID, revision: image.revision)
            }
            return retained ?? image
        } catch {
            let context = await snapshotContext()
            _ = await cache.finish(cached, image: nil, context: context)
            throw loadFailure(error, request: admittedRequest, revision: header.revision, unreadableKind: .corruptImage)
        }
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
    default:
        let sourceError = error as NSError
        let missing = (sourceError.domain == NSCocoaErrorDomain &&
            [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(sourceError.code)) ||
            (sourceError.domain == NSPOSIXErrorDomain && sourceError.code == Int(ENOENT))
        guard missing else { return error } // Includes permission and FileAccess errors, unchanged.
        kind = .sourceChanged
    }
    return ImageLoadError(kind, itemID: itemID ?? request.renderKey?.itemID, revision: revision ?? request.renderKey?.revision)
}
