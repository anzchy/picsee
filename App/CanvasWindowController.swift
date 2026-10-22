import AppKit
import os
import PicseeCore

/// One P0 window and one in-flight request. New intent coalesces behind it.
/// The admission actor, shared budgets and full cancellation belong to P0-05/06.
@MainActor
final class CanvasWindowController: NSWindowController, NSWindowDelegate {
    private let canvas = CanvasView(frame: .zero)
    private let filesystemLogger = Logger(subsystem: "io.github.anzchy.picsee", category: "filesystem")
    private let pipeline: any ImagePipeline
    private var fileURL: URL?
    private var generation = UUID()
    private var desiredMaximum = 0
    private var completedMaximum = 0
    private var decoding = false

    init(pipeline: any ImagePipeline) {
        self.pipeline = pipeline
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Picsee"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        canvas.frame = window.contentView!.bounds
        canvas.autoresizingMask = [.width, .height]
        window.contentView = canvas
        window.makeFirstResponder(canvas)
        canvas.onResolutionNeeded = { [weak self] maximum in
            self?.desiredMaximum = maximum
            self?.decodeIfNeeded()
        }
    }

    required init?(coder: NSCoder) { nil }

    func open(_ url: URL) {
        filesystemLogger.notice("Open file=\(url.lastPathComponent, privacy: .private)")
        generation = UUID()
        fileURL = url
        completedMaximum = 0
        let scale = window?.backingScaleFactor ?? 1
        desiredMaximum = max(1, Int(ceil(max(canvas.bounds.width, canvas.bounds.height) * scale)))
        canvas.beginOpening()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        decodeIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        generation = UUID()
        fileURL = nil
        // The running synchronous decode retains its File Grant until actual completion.
    }

    private func decodeIfNeeded() {
        guard !decoding, let url = fileURL, desiredMaximum > completedMaximum else { return }
        decoding = true
        let token = generation
        let maximum = desiredMaximum
        Task { [self] in
            let scoped = url.startAccessingSecurityScopedResource()
            let result: Result<DecodedImage, Error>
            do {
                result = .success(try await pipeline.image(for: ImageDecodeRequest(fileURL: url, maximumPixelSize: maximum)))
            } catch {
                result = .failure(error)
            }
            if scoped { url.stopAccessingSecurityScopedResource() }
            if token == generation {
                completedMaximum = maximum
                switch result {
                case .success(let image): canvas.install(image)
                case .failure: canvas.showFailure(); desiredMaximum = 0
                }
            }
            decoding = false
            decodeIfNeeded()
        }
    }
}
