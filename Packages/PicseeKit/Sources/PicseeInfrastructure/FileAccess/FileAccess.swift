import Foundation
import PicseeCore
import os

/// One actual start/stop pair, including temporary bookmark refresh/grant work.
private struct ScopeSession {
    static let log = OSLog(subsystem: "io.github.anzchy.picsee", category: "access")
    let scope: any SecurityScope
    let url: URL
    let rootID: AccessRootID?
    let trace: OSSignpostID
    init(scope: any SecurityScope, url: URL, rootID: AccessRootID?) throws {
        guard scope.start(url) else { throw FileAccessError.startFailed }
        self.scope = scope; self.url = url; self.rootID = rootID
        trace = OSSignpostID(log: Self.log)
        os_signpost(.begin, log: Self.log, name: "AccessLease", signpostID: trace, "outcome=started")
    }
    func stop() {
        scope.stop(url)
        os_signpost(.end, log: Self.log, name: "AccessLease", signpostID: trace, "outcome=released")
        Logger(subsystem: "io.github.anzchy.picsee", category: "access").notice("AccessLease root=\(rootID?.rawValue.uuidString ?? "file", privacy: .public) remaining=0 outcome=released path=\(url.path, privacy: .private)")
    }
}

/// Shared by the application. All persisted-grant I/O runs on this actor's executor.
public actor FileAccess: AccessLeasing {
    private let scope: any SecurityScope
    private let bookmarks: any BookmarkCoding
    private let store: BookmarkStore
    private let buildSHA: String
    private var saved: [AccessRootRecord]
    private var roots: [AccessRootID: URL] = [:]
    private var outcomes: [AccessRootID: String] = [:]
    private struct Active { let session: ScopeSession; var tokens: Set<UUID> }
    private var active: [AccessRequest: Active] = [:]
    private var requests: [UUID: AccessRequest] = [:]

    public init(scope: any SecurityScope, bookmarks: any BookmarkCoding, store: BookmarkStore, buildSHA: String) throws {
        self.scope = scope; self.bookmarks = bookmarks; self.store = store; self.buildSHA = buildSHA
        saved = try store.load()
        let logger = Logger(subsystem: "io.github.anzchy.picsee", category: "access")
        for index in saved.indices {
            let record = saved[index]
            var outcome = "failed"
            do {
                let resolution = try bookmarks.resolve(record.bookmark)
                if resolution.stale {
                    let session = try ScopeSession(scope: scope, url: resolution.url, rootID: record.id)
                    defer { session.stop() }
                    var refreshed = saved
                    refreshed[index].bookmark = try bookmarks.create(for: resolution.url)
                    try store.save(refreshed)
                    saved = refreshed
                    outcome = "stale"
                } else { outcome = "resolved" }
                roots[record.id] = resolution.url
            } catch { outcome = "failed" }
            outcomes[record.id] = outcome
            logger.notice("AccessRoot root=\(record.id.rawValue.uuidString, privacy: .public) outcome=\(outcome, privacy: .public) creating=\(record.creatingBuildSHA, privacy: .public) current=\(buildSHA, privacy: .public)")
        }
    }
    public func records() -> [AccessRootRecord] { saved }
    public func launchOutcomes() -> [AccessRootID: String] { outcomes }
    public func rootCovering(_ file: URL) -> AccessRootID? {
        saved.first { roots[$0.id].map { AccessBoundary.contains(file, in: $0) } ?? false }?.id
    }
    /// Only the composition root's successful system panel invokes this operation.
    public func grant(folder: URL) throws -> AccessRootID {
        let id = AccessRootID()
        let session = try ScopeSession(scope: scope, url: folder, rootID: id)
        defer { session.stop() }
        guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw FileAccessError.invalidFolder
        }
        let bookmark = try bookmarks.create(for: folder)
        let record = AccessRootRecord(id: id, bookmark: bookmark, displayName: folder.lastPathComponent,
                                      creatingBuildSHA: buildSHA, createdAt: Date())
        try store.save(saved + [record])
        saved.append(record); roots[id] = folder
        return id
    }
    public func acquire(_ request: AccessRequest) throws -> AccessLease {
        let key: AccessRequest
        let url: URL
        let rootID: AccessRootID?
        var staleRecord: AccessRootRecord?
        switch request {
        case .root(let id, let file):
            guard let record = saved.first(where: { $0.id == id }), let root = roots[id] else {
                throw FileAccessError.needsReconnection(id)
            }
            key = .root(id, file: root); rootID = id
            if active[key] != nil { url = root }
            else {
                do {
                    let resolution = try bookmarks.resolve(record.bookmark)
                    url = resolution.url
                    if resolution.stale { staleRecord = record }
                }
                catch { roots.removeValue(forKey: id); throw FileAccessError.needsReconnection(id) }
            }
            guard AccessBoundary.contains(file, in: url) else { throw FileAccessError.outsideRoot }
        case .fileGrant(let file):
            key = .fileGrant(file.standardizedFileURL); url = file; rootID = nil
        }
        let lease = AccessLease(url: url, rootID: rootID)
        if var entry = active[key] {
            entry.tokens.insert(lease.token); active[key] = entry
        } else {
            let session = try ScopeSession(scope: scope, url: url, rootID: rootID)
            if var record = staleRecord {
                do {
                    record.bookmark = try bookmarks.create(for: url)
                    let refreshed = saved.map { $0.id == record.id ? record : $0 }
                    try store.save(refreshed)
                    saved = refreshed
                } catch {
                    session.stop()
                    roots.removeValue(forKey: record.id)
                    throw FileAccessError.needsReconnection(record.id)
                }
            }
            active[key] = Active(session: session, tokens: [lease.token])
        }
        requests[lease.token] = key
        return lease
    }
    public func release(_ lease: AccessLease) {
        guard let key = requests.removeValue(forKey: lease.token), var entry = active[key] else { return }
        entry.tokens.remove(lease.token)
        if entry.tokens.isEmpty {
            entry.session.stop(); active.removeValue(forKey: key)
        } else { active[key] = entry }
    }
}
