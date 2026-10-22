import AppKit
import PicseeCore

/// P0 native adapter. Math lives in CanvasTransform; command routing is P0-09.
@MainActor
final class CanvasView: NSView {
    private var transform = CanvasTransform(backingScale: 1)
    private var image: NSImage?
    private var sourceSize = CGSize.zero
    private var message: String? = nil
    var onResolutionNeeded: ((Int) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func beginOpening() {
        image = nil
        sourceSize = .zero
        message = "正在打开图片…"
        needsDisplay = true
    }

    func showFailure() {
        image = nil
        sourceSize = .zero
        message = "无法读取这张图片。请从访达打开另一张图片。"
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
        }
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        transform.setBackingScale(Double(window?.backingScaleFactor ?? 1), about: centre)
        needsDisplay = true
        requestDetail()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard image != nil, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.charactersIgnoringModifiers {
        case "1": transform.actualPixels(about: centre)
        case "+", "=": transform.zoom(to: transform.zoom * 1.25, about: cursorAnchor)
        case "-", "−": transform.zoom(to: transform.zoom / 1.25, about: cursorAnchor)
        default:
            super.keyDown(with: event)
            return
        }
        needsDisplay = true
        requestDetail()
    }

    override func magnify(with event: NSEvent) {
        guard image != nil else { return }
        transform.zoom(to: transform.zoom * exp(Double(event.magnification)),
                       about: convert(event.locationInWindow, from: nil))
        needsDisplay = true
        requestDetail()
    }

    private var centre: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private var cursorAnchor: CGPoint {
        guard let window, window.isVisible else { return centre }
        let anchor = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(anchor) ? anchor : centre
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
