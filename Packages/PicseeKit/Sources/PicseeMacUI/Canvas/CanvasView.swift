import AppKit
import PicseeCore
import PicseeApplication

/// P0 native adapter. Math lives in CanvasTransform; command routing is P0-09.
@MainActor
final class CanvasView: NSView {
    private var transform = CanvasTransform(backingScale: 1)
    private var image: NSImage?
    private var sourceSize = CGSize.zero
    private var message: String? = nil
    var onResolutionNeeded: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "canvas.image", defaultValue: "Image"))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func beginOpening() {
        image = nil
        sourceSize = .zero
        message = String(localized: "canvas.opening", defaultValue: "Opening image…")
        needsDisplay = true
    }

    func showFailure() {
        image = nil
        sourceSize = .zero
        message = String(localized: "canvas.failure", defaultValue: "Unable to read this image. Open another image from Finder.")
        needsDisplay = true
    }

    func install(_ result: DecodedImage) {
        let first = image == nil
        sourceSize = result.sourcePixelSize
        image = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
        message = nil
        if first {
            let backing = window?.backingScaleFactor ?? 1
            let fit = min(1, min(max(1, bounds.width - 32) * backing / sourceSize.width,
                                 max(1, bounds.height - 32) * backing / sourceSize.height))
            let zoom = max(CanvasTransform.zoomLimits.lowerBound, fit)
            let origin = CGPoint(x: bounds.midX - sourceSize.width * zoom / backing / 2,
                                 y: bounds.midY - sourceSize.height * zoom / backing / 2)
            transform = CanvasTransform(backingScale: backing, zoom: zoom, origin: origin)
            if zoom == 1 { transform.actualPixels(about: centre) }
        }
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        transform.setBackingScale(Double(window?.backingScaleFactor ?? 1), about: centre)
        if transform.zoom == 1 { transform.actualPixels(about: centre) }
        needsDisplay = true
        requestDetail()
    }

    var onCommand: ((CommandID) -> Bool)?
    var pointerIsOverPanel: (() -> Bool)?
    var onCanvasFocus: (() -> Void)?
    var onTab: ((Bool) -> Void)?
    var hasImage: Bool { image != nil }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 3, dy: 3) }
    override func drawFocusRingMask() { NSBezierPath(rect: focusRingMaskBounds).fill() }

    override func mouseDown(with event: NSEvent) {
        onCanvasFocus?()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 { onTab?(event.modifierFlags.contains(.shift)); return }
        if event.modifierFlags.intersection([.control, .option]).isEmpty,
           let key = event.charactersIgnoringModifiers,
           let id = CommandID.matching(key: key, command: event.modifierFlags.contains(.command)),
           onCommand?(id) == true { return }
        super.keyDown(with: event)
    }

    func apply(_ command: CommandID, from entry: CommandEntry) {
        guard image != nil else { return }
        switch command {
        case .fit: fit()
        case .actualPixels: transform.actualPixels(about: centre)
        case .zoomIn: transform.zoom(to: transform.zoom * 1.25, about: commandAnchor(from: entry))
        case .zoomOut: transform.zoom(to: transform.zoom / 1.25, about: commandAnchor(from: entry))
        default: return
        }
        needsDisplay = true
        requestDetail()
    }

    private func fit() {
        let backing = window?.backingScaleFactor ?? 1
        let zoom = min(1, min(max(1, bounds.width - 32) * backing / sourceSize.width,
                              max(1, bounds.height - 32) * backing / sourceSize.height))
        let clamped = max(CanvasTransform.zoomLimits.lowerBound, zoom)
        transform = CanvasTransform(backingScale: backing, zoom: clamped,
            origin: CGPoint(x: bounds.midX - sourceSize.width * clamped / backing / 2,
                            y: bounds.midY - sourceSize.height * clamped / backing / 2))
    }

    override func magnify(with event: NSEvent) {
        guard image != nil else { return }
        transform.zoom(to: transform.zoom * exp(Double(event.magnification)),
                       about: convert(event.locationInWindow, from: nil))
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
        guard sourceSize.width > 0 else { return }
        let backing = window?.backingScaleFactor ?? 1
        let viewport = CGSize(width: max(1, bounds.width - 32) * backing,
                              height: max(1, bounds.height - 32) * backing)
        onResolutionNeeded?(CanvasDecodePolicy.maximumPixelSize(source: sourceSize, viewport: viewport,
                                                                zoom: transform.zoom))
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor(srgbRed: 15 / 255, green: 17 / 255, blue: 21 / 255, alpha: 1) : .white).setFill()
        bounds.fill()
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
