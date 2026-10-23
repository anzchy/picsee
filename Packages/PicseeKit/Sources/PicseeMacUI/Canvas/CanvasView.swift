import AppKit
import PicseeCore
import PicseeApplication

/// Reusable renderer and input adapter. Geometry is pure; zoom intent belongs to the Session.
@MainActor
open class CanvasView: NSView {
    public let session: ViewerSession
    /// The host distinguishes a new input from a retry of the same item. No file access occurs here.
    public var openingChangesItem: (() -> Bool)?
    private var transform = CanvasTransform(backingScale: 1)
    private var image: NSImage?
    private var sourceSize = CGSize.zero
    private var message: String?
    private var dragPoint: CGPoint?
    private var previousViewport = CGSize.zero
    public var onResolutionNeeded: ((Int) -> Void)?

    public init(frame frameRect: NSRect, session: ViewerSession) {
        self.session = session
        super.init(frame: frameRect)
        previousViewport = frameRect.size
        clipsToBounds = true
        setAccessibilityIdentifier("viewer.canvas")
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "canvas.image", defaultValue: "Image"))
    }

    required public init?(coder: NSCoder) { nil }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    public func beginOpening() {
        image = nil
        dragPoint = nil
        if openingChangesItem?() ?? true {
            sourceSize = .zero
            session.beginCanvasImage()
        }
        message = String(localized: "canvas.opening", defaultValue: "Opening image…")
        needsDisplay = true
    }

    public func showFailure() {
        dragPoint = nil
        image = nil
        sourceSize = .zero
        message = String(localized: "canvas.failure", defaultValue: "Unable to read this image. Open another image from Finder.")
        needsDisplay = true
    }

    public func install(_ result: DecodedImage) {
        let changedSize = sourceSize != result.sourcePixelSize
        sourceSize = result.sourcePixelSize
        image = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
        message = nil
        if changedSize {
            session.beginCanvasImage()
            fit()
        }
        previousViewport = bounds.size
        needsDisplay = true
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        synchronizeViewport()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeViewport()
    }

    /// Also used by the App's full-screen handoff; all viewport changes use the same rule.
    public func synchronizeViewport() {
        defer { previousViewport = bounds.size }
        guard sourceSize.width > 0 else { return }
        transform.viewportChanged(source: sourceSize, from: previousViewport, to: bounds.size,
            backingScale: Double(window?.backingScaleFactor ?? 1), mode: session.zoomMode)
        needsDisplay = true
        requestDetail()
    }

    public var onCommand: ((CommandID) -> Bool)?
    public var pointerIsOverPanel: (() -> Bool)?
    public var onCanvasFocus: (() -> Void)?
    public var onTab: ((Bool) -> Void)?
    public var hasImage: Bool { image != nil }

    public override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    public override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    public override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 3, dy: 3) }
    public override func drawFocusRingMask() { NSBezierPath(rect: focusRingMaskBounds).fill() }

    public override func mouseDown(with event: NSEvent) {
        onCanvasFocus?()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let end = transform.imageToView(CGPoint(x: sourceSize.width, y: sourceSize.height))
        let rectangle = CGRect(origin: transform.origin,
            size: CGSize(width: end.x - transform.origin.x, height: end.y - transform.origin.y))
        dragPoint = image != nil && rectangle.contains(point) ? point : nil
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let previous = dragPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        transform.pan(by: CGPoint(x: point.x - previous.x, y: point.y - previous.y),
            source: sourceSize, viewport: bounds.size, snap: session.zoomMode == .actualPixels)
        dragPoint = point
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) { dragPoint = nil }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 { onTab?(event.modifierFlags.contains(.shift)); return }
        if event.modifierFlags.intersection([.control, .option]).isEmpty,
           let key = event.charactersIgnoringModifiers,
           let id = CommandID.matching(key: key, command: event.modifierFlags.contains(.command)),
           onCommand?(id) == true { return }
        super.keyDown(with: event)
    }

    public func apply(_ command: CommandID, from entry: CommandEntry) -> Double? {
        guard image != nil else { return nil }
        switch command {
        case .fit: fit()
        case .actualPixels:
            transform.actualPixels(about: centre)
            transform.bound(source: sourceSize, viewport: bounds.size, snap: true)
        case .zoomIn: transform.zoom(to: transform.zoom * 1.25, about: commandAnchor(from: entry), source: sourceSize, viewport: bounds.size)
        case .zoomOut: transform.zoom(to: transform.zoom / 1.25, about: commandAnchor(from: entry), source: sourceSize, viewport: bounds.size)
        default: return nil
        }
        needsDisplay = true
        requestDetail()
        return transform.zoom
    }

    private func fit() {
        transform = .fitted(source: sourceSize, viewport: bounds.size,
                            backingScale: Double(window?.backingScaleFactor ?? 1))
    }

    /// Gesture values are testable independently of AppKit's non-constructible magnify event.
    public func magnify(by magnification: Double, at point: CGPoint) {
        guard image != nil else { return }
        transform.zoom(to: transform.zoom * exp(magnification), about: point,
                       source: sourceSize, viewport: bounds.size)
        session.reportCanvasZoom(transform.zoom)
        needsDisplay = true
        requestDetail()
    }

    private var centre: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func commandAnchor(from entry: CommandEntry) -> CGPoint {
        let pointer = window.flatMap { window -> CGPoint? in
            guard window.isVisible else { return nil }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            return bounds.contains(point) ? point : nil
        }
        return CommandZoomAnchor.resolve(entry: entry, pointer: pointer,
            pointerOverPanel: pointerIsOverPanel?() ?? false, centre: centre)
    }

    private func requestDetail() {
        guard image != nil, sourceSize.width > 0 else { return }
        let backing = window?.backingScaleFactor ?? 1
        let viewport = CGSize(width: max(1, bounds.width - 32) * backing,
                              height: max(1, bounds.height - 32) * backing)
        onResolutionNeeded?(CanvasDecodePolicy.maximumPixelSize(source: sourceSize, viewport: viewport,
                                                                zoom: transform.zoom))
    }

    public override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            DesignColor.canvasBackground.nsColor.setFill()
            bounds.fill()
        }
        if let image {
            let origin = transform.imageToView(.zero)
            let end = transform.imageToView(CGPoint(x: sourceSize.width, y: sourceSize.height))
            let rectangle = NSRect(x: origin.x, y: origin.y, width: end.x - origin.x, height: end.y - origin.y)
            image.draw(in: rectangle, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        } else if let message {
            let text = NSAttributedString(string: message, attributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor
            ])
            let size = text.size()
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        }
    }
}
