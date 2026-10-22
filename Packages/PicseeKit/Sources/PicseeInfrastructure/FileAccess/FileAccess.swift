import Foundation
import PicseeCore
import os

/// Shared by the application, never by a single window.
public actor FileAccess: AccessLeasing {
    private let scope: any SecurityScope
    private var roots: [AccessRootID: URL] = [:]
    private struct Active {
        let url: URL
        let trace: OSSignpostID
        var tokens: Set<UUID>
    }
    private var active: [AccessRequest: Active] = [:]
    private var requests: [UUID: AccessRequest] = [:]
    private static let log = OSLog(subsystem: "io.github.anzchy.picsee", category: "access")
    private let logger = Logger(subsystem: "io.github.anzchy.picsee", category: "access")
    public init(scope: any SecurityScope) { self.scope = scope }
    public func grant(folder: URL) throws -> AccessRootID {
        let id = AccessRootID()
        roots[id] = folder
        return id
    }
    public func acquire(_ request: AccessRequest) throws -> AccessLease {
        let key: AccessRequest
        let url: URL
        let rootID: AccessRootID?
        switch request {
        case .root(let id, let file):
            guard let root = roots[id] else { throw FileAccessError.needsReconnection(id) }
            guard AccessBoundary.contains(file, in: root) else { throw FileAccessError.outsideRoot }
            key = .root(id, file: root); url = root; rootID = id
        case .fileGrant(let file):
            key = .fileGrant(file.standardizedFileURL); url = file; rootID = nil
        }
        let lease = AccessLease(url: url, rootID: rootID)
        if var entry = active[key] {
            entry.tokens.insert(lease.token)
            active[key] = entry
        } else {
            guard scope.start(url) else { throw FileAccessError.startFailed }
            let trace = OSSignpostID(log: Self.log)
            os_signpost(.begin, log: Self.log, name: "AccessLease", signpostID: trace, "outcome=started")
            active[key] = Active(url: url, trace: trace, tokens: [lease.token])
        }
        requests[lease.token] = key
        return lease
    }
    public func release(_ lease: AccessLease) {
        guard let key = requests.removeValue(forKey: lease.token), var entry = active[key] else { return }
        entry.tokens.remove(lease.token)
        if entry.tokens.isEmpty {
            scope.stop(entry.url)
            os_signpost(.end, log: Self.log, name: "AccessLease", signpostID: entry.trace, "outcome=released")
            logger.notice("AccessLease root=\(lease.rootID?.rawValue.uuidString ?? "file", privacy: .public) remaining=0 outcome=released path=\(entry.url.path, privacy: .private)")
            active.removeValue(forKey: key)
        } else { active[key] = entry }
    }
}
