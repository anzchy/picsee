import Foundation
import PicseeCore

/// App-wide registry. Leases supply scope; this registry never grants access.
actor RootIdentityResolvers {
    private var roots: [AccessRootID: (URL, FileItemIdentityResolver)] = [:]
    func resolver(for root: ItemIdentityRoot) -> FileItemIdentityResolver {
        if let existing = roots[root.id], existing.0 == root.url { return existing.1 }
        let resolver = FileItemIdentityResolver(root: root)
        roots[root.id] = (root.url, resolver)
        return resolver
    }
}
