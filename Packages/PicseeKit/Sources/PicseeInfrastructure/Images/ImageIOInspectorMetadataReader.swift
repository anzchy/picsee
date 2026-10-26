import Foundation
import ImageIO
import PicseeApplication
import PicseeCore
import UniformTypeIdentifiers

/// Header and file attributes are read under the same security scope used for image decoding.
public struct ImageIOInspectorMetadataReader: InspectorMetadataReading {
    private let access: any AccessLeasing
    private let workerStarted: (@Sendable () -> Void)?
    public init(access: any AccessLeasing) { self.access = access; self.workerStarted = nil }
    init(access: any AccessLeasing, workerStarted: @escaping @Sendable () -> Void) {
        self.access = access; self.workerStarted = workerStarted
    }
    public func read(_ url: URL, access request: AccessRequest) async throws -> InspectorMetadata {
        do {
            return try await access.withLease(request) { _ in
                let worker = Task.detached(priority: .utility) {
                    try Task.checkCancellation()
                    let attributes: URLResourceValues
                    do { attributes = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey]) }
                    catch {
                        let ns = error as NSError
                        throw ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError
                            ? InspectorReadError.noPermission : InspectorReadError.unreadable
                    }
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                          CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                        throw InspectorReadError.unreadable
                    }
                    let width = properties[kCGImagePropertyPixelWidth] as? Int
                    let height = properties[kCGImagePropertyPixelHeight] as? Int
                    let size = attributes.fileSize.map(Int64.init)
                    let thumbnail: Data?
                    try Task.checkCancellation()
                    if let width, let height, width > 0, height > 0,
                       Int64(width) <= 40_000_000 / Int64(height),
                       let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 240
                    ] as CFDictionary) {
                        let data = NSMutableData()
                        if let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) {
                            CGImageDestinationAddImage(destination, image, nil)
                            thumbnail = CGImageDestinationFinalize(destination) ? data as Data : nil
                        } else { thumbnail = nil }
                    } else { thumbnail = nil }
                    try Task.checkCancellation()
                    return InspectorMetadata(pixelWidth: width, pixelHeight: height,
                        typeIdentifier: CGImageSourceGetType(source) as String?, creationDate: attributes.creationDate,
                        modificationDate: attributes.contentModificationDate, byteSize: size, thumbnailData: thumbnail)
                }
                workerStarted?()
                return try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
            }
        } catch FileAccessError.needsReconnection, FileAccessError.outsideRoot, FileAccessError.startFailed {
            throw InspectorReadError.noPermission
        } catch let error as InspectorReadError {
            throw error
        } catch {
            throw InspectorReadError.unreadable
        }
    }
}
