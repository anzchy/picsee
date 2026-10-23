import Foundation
import Observation
import PicseeCore

public enum ViewerImagePhase: Sendable { case idle, opening, refining, settled, detailLimited, failed }
public struct PresentedImage: Sendable {
    public let fileURL: URL
    public let key: RenderKey
    public var name: String { fileURL.lastPathComponent }
}

/// One per Session; shared decoding and lease services arrive through the opener.
@MainActor @Observable public final class ViewerImageLoader {
    public typealias Opener = @MainActor @Sendable () async throws -> AccessImageSource
    public weak var host: (any ViewerImageHost)?
    public private(set) var generation = UUID()
    public private(set) var phase: ViewerImagePhase = .idle
    public private(set) var presented: PresentedImage?
    public private(set) var failure: (any Error)?
    public private(set) var preparedKey: RenderKey?
    private let binding = UUID()
    private var source: AccessImageSource?
    var loadTask: Task<Void, Never>?
    public init() { }
    public func open(_ fileURL: URL, maximumPixelSize: Int, opener: @escaping Opener) {
        generation = UUID()
        phase = .opening; presented = nil; failure = nil; preparedKey = nil
        host?.beginImageOpening()
        let token = PresentationToken(binding: binding, generation: generation)
        loadTask = Task {
            do {
                let source = try await opener()
                guard token.generation == generation else { await source.close(); return }
                self.source = source
                let (request, image) = try await source.image(
                    maximumPixelSize: min(CanvasDecodePolicy.previewMaximumPixelSize, maximumPixelSize), isPreview: true)
                guard token == PresentationToken(binding: binding, generation: generation) else { return }
                preparedKey = request.renderKey
                guard let key = preparedKey, image.itemID == key.itemID, image.revision == key.revision else {
                    throw ImageLoadError(.sourceChanged, itemID: preparedKey?.itemID, revision: image.revision)
                }
                presented = PresentedImage(fileURL: fileURL, key: key)
                host?.installImage(image, fileURL: fileURL)
                phase = .settled
            } catch {
                guard token.generation == generation else { return }
                failure = error; phase = .failed
                host?.imageLoadFailed(error)
            }
        }
    }
    public func requireResolution(_ maximum: Int) { }
    public func close() { }
}

extension ViewerSession {
    public func openImage(_ fileURL: URL, maximumPixelSize: Int, opener: @escaping ViewerImageLoader.Opener) {
        imageLoader.open(fileURL, maximumPixelSize: maximumPixelSize, opener: opener)
    }
    public func requireImageResolution(_ maximum: Int) { imageLoader.requireResolution(maximum) }
    public func closeImage() { imageLoader.close() }
}
