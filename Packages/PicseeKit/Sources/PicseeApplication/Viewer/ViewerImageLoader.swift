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
    private var revisionRetryUsed = false
    private var desiredMaximum = 0
    private var progress = CanvasDecodeProgress()
    private var loading = false
    private var fileURL: URL?
    private var opener: Opener?
    public func open(_ fileURL: URL, maximumPixelSize: Int, opener: @escaping Opener) {
        retire()
        generation = UUID()
        loading = false; revisionRetryUsed = false
        phase = .opening; presented = nil; failure = nil; preparedKey = nil
        source = nil
        self.fileURL = fileURL; self.opener = opener
        desiredMaximum = max(1, maximumPixelSize); progress = CanvasDecodeProgress()
        host?.beginImageOpening()
        schedule()
    }
    private func schedule() {
        guard let fileURL, let opener else { return }
        loading = true
        let token = PresentationToken(binding: binding, generation: generation)
        loadTask = Task { await load(fileURL, opener: opener, token: token) }
    }
    private func load(_ fileURL: URL, opener: Opener, token: PresentationToken) async {
        while true {
        do {
            let source: AccessImageSource
            if let existing = self.source { source = existing }
            else {
                source = try await opener()
                guard token.generation == generation else { await source.close(); return }
                self.source = source
            }
            while let maximum = progress.nextMaximum(desired: desiredMaximum),
                  !progress.previewCompleted || maximum > progress.completedMaximum {
                let preview = !progress.previewCompleted
                let (request, image) = try await source.image(maximumPixelSize: maximum, isPreview: preview)
                guard token == PresentationToken(binding: binding, generation: generation) else { return }
                preparedKey = request.renderKey
                guard let key = preparedKey, image.itemID == key.itemID, image.revision == key.revision else {
                    throw ImageLoadError(.sourceChanged, itemID: preparedKey?.itemID, revision: image.revision)
                }
                progress.completed(image, isPreview: preview)
                presented = PresentedImage(fileURL: fileURL, key: key)
                host?.installImage(image, fileURL: fileURL)
                phase = .refining
            }
            phase = .settled
            break
        } catch {
            guard token.generation == generation else { return }
            if (error as? ImageLoadError)?.kind == .sourceChanged, !revisionRetryUsed {
                revisionRetryUsed = true
                preparedKey = nil; presented = nil; progress = CanvasDecodeProgress()
                host?.beginImageOpening()
                let old = source; source = nil
                await old?.close()
                guard token.generation == generation else { return }
                continue
            }
            if (error as? ImageLoadError)?.kind == .resourceLimit, presented != nil {
                failure = error; phase = .detailLimited
                // AccessImageSource closes on an error. Renew the display lease without decoding again.
                do {
                    let replacement = try await opener()
                    guard token.generation == generation else { await replacement.close(); return }
                    self.source = replacement
                } catch {
                    guard token.generation == generation else { return }
                    failure = error; presented = nil; phase = .failed
                    host?.imageLoadFailed(error)
                }
                break
            }
            failure = error; phase = .failed
            host?.imageLoadFailed(error)
            break
        }
        }
        if token.generation == generation { loading = false }
    }
    public func requireResolution(_ maximum: Int) {
        guard phase != .failed, phase != .detailLimited else { return }
        desiredMaximum = max(1, maximum)
        guard progress.previewCompleted, desiredMaximum > progress.completedMaximum else { return }
        phase = .refining
        if !loading { schedule() }
    }
    private func retire() {
        loadTask?.cancel()
        let old = source; source = nil
        Task { await old?.close() }
    }
    public func close() {
        retire()
        generation = UUID(); loading = false
        desiredMaximum = 0; fileURL = nil; opener = nil
        presented = nil; preparedKey = nil; failure = nil; phase = .idle
    }

}

extension ViewerSession {
    public func openImage(_ fileURL: URL, maximumPixelSize: Int, opener: @escaping ViewerImageLoader.Opener) {
        imageLoader.open(fileURL, maximumPixelSize: maximumPixelSize, opener: opener)
    }
    public func requireImageResolution(_ maximum: Int) { imageLoader.requireResolution(maximum) }
    public func closeImage() { imageLoader.close() }
}
