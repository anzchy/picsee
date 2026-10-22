import Foundation

/// Two tiers per source and viewport: preview, then source resolution beyond fit.
/// P0 sizing only; admission, memory budgets and cancellation belong to P0-05/06.
public enum CanvasDecodePolicy {
    public static func maximumPixelSize(source: CGSize, viewport: CGSize, zoom: Double) -> Int {
        precondition(source.width > 0 && source.height > 0 && viewport.width > 0 && viewport.height > 0)
        let sourceEdge = max(source.width, source.height)
        let fit = min(1, min(viewport.width / source.width, viewport.height / source.height))
        let maximum = zoom > fit ? sourceEdge : min(sourceEdge, max(viewport.width, viewport.height))
        return max(1, Int(ceil(maximum)))
    }
}
