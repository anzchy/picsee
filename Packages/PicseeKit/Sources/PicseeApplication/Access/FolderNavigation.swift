import Foundation

public enum NavigationDirection: Sendable { case previous, next }
public enum NavigationDecision: Equatable, Sendable { case needsGrant(URL), move(URL), end }

/// P0 snapshot: non-recursive Finder order, no wrap. ViewerSession can adopt this value.
public struct FolderNavigation: Sendable {
    public let images: [URL]
    public init(images: [URL]) { self.images = images.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } }
    public func step(from current: URL, direction: NavigationDirection, covered: Bool) -> NavigationDecision {
        guard covered else { return .needsGrant(current.deletingLastPathComponent()) }
        guard let index = images.firstIndex(of: current) else { return .end }
        let next = index + (direction == .next ? 1 : -1)
        guard images.indices.contains(next) else { return .end }
        return .move(images[next])
    }
}
