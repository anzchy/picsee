import CoreGraphics
import Foundation

/// Image pixels ↔ top-left view points. Zoom is backing pixels per image pixel.
public struct CanvasTransform: Sendable {
    public private(set) var backingScale: Double
    public private(set) var zoom: Double
    public private(set) var origin: CGPoint
    public static let zoomLimits = (1.0 / 64.0)...64.0

    public init(backingScale: Double, zoom: Double = 1, origin: CGPoint = .zero) {
        precondition(backingScale.isFinite && backingScale > 0)
        self.backingScale = backingScale
        self.zoom = min(max(zoom, Self.zoomLimits.lowerBound), Self.zoomLimits.upperBound)
        self.origin = origin
    }

    public func imageToView(_ pixel: CGPoint) -> CGPoint {
        let ratio = CGFloat(zoom / backingScale)
        return CGPoint(x: origin.x + pixel.x * ratio, y: origin.y + pixel.y * ratio)
    }

    public func viewToImage(_ point: CGPoint) -> CGPoint {
        let ratio = CGFloat(zoom / backingScale)
        return CGPoint(x: (point.x - origin.x) / ratio, y: (point.y - origin.y) / ratio)
    }

    public func imageToBacking(_ pixel: CGPoint) -> CGPoint {
        let point = imageToView(pixel)
        return CGPoint(x: point.x * backingScale, y: point.y * backingScale)
    }

    public mutating func zoom(to proposed: Double, about anchor: CGPoint) {
        let pixel = viewToImage(anchor)
        zoom = proposed.isNaN ? zoom : min(max(proposed, Self.zoomLimits.lowerBound), Self.zoomLimits.upperBound)
        pin(pixel, to: anchor)
    }

    public mutating func actualPixels(about anchor: CGPoint) {
        zoom(to: 1, about: anchor)
        // Actual-pixel mode prefers the backing grid over a subpixel anchor:
        // at most half a backing pixel of movement on each axis.
        origin = CGPoint(x: (origin.x * backingScale).rounded() / backingScale,
                         y: (origin.y * backingScale).rounded() / backingScale)
    }

    public mutating func setBackingScale(_ scale: Double, about anchor: CGPoint) {
        precondition(scale.isFinite && scale > 0)
        let pixel = viewToImage(anchor)
        backingScale = scale
        pin(pixel, to: anchor)
    }

    private mutating func pin(_ pixel: CGPoint, to anchor: CGPoint) {
        let ratio = CGFloat(zoom / backingScale)
        origin = CGPoint(x: anchor.x - pixel.x * ratio, y: anchor.y - pixel.y * ratio)
    }
}
