import Foundation

/// Initial small preview, viewport detail, then source resolution beyond fit.
public enum CanvasDecodePolicy {
    public static let previewMaximumPixelSize = 512
    public static func maximumPixelSize(source: CGSize, viewport: CGSize, zoom: Double) -> Int {
        precondition(source.width > 0 && source.height > 0 && viewport.width > 0 && viewport.height > 0)
        let sourceEdge = max(source.width, source.height)
        let fit = min(1, min(viewport.width / source.width, viewport.height / source.height))
        let maximum = zoom > fit ? sourceEdge : min(sourceEdge, max(viewport.width, viewport.height))
        return max(1, Int(ceil(maximum)))
    }
}
