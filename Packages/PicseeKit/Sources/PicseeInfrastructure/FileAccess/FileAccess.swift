import Foundation
import PicseeCore
import os

/// One lease lifetime; only a successfully started security scope requires a stop.
private struct ScopeSession {
    static let log = OSLog(subsystem: "io.github.anzchy.picsee", category: "access")
    let scope: any SecurityScope
    let url: URL
    let rootID: AccessRootID?
    let trace: OSSignpostID
    let scopeStarted: Bool
    init(scope: any SecurityScope, url: URL, rootID: AccessRootID?) throws {
        let started = scope.start(url)
        // Finder drops/open events may already carry sandbox read access without
        // a startable URL scope. Bookmark roots still require their own scope.
        guard started || (rootID == nil && scope.isReadable(url)) else { throw FileAccessError.startFailed }
        scopeStarted = started
        self.scope = scope; self.url = url; self.rootID = rootID
        trace = OSSignpostID(log: Self.log)
        os_signpost(.begin, log: Self.log, name: "AccessLease", signpostID: trace, "outcome=leased scopeStarted=%{public}d", started ? 1 : 0)
    }
    func stop() {
        if scopeStarted { scope.stop(url) }
        os_signpost(.end, log: Self.log, name: "AccessLease", signpostID: trace, "outcome=released")
        Logger(subsystem: "io.github.anzchy.picsee", category: "access").notice("AccessLease root=\(rootID?.rawValue.uuidString ?? "file", privacy: .public) remaining=0 outcome=released scopeStarted=\(scopeStarted, privacy: .public) path=\(url.path, privacy: .private)")
    }
}

/// Shared by the application. All persisted-grant I/O runs on this actor's executor.
public actor FileAccess: AccessLeasing {
    private let scope: any SecurityScope
    private let bookmarks: any BookmarkCoding
    private let store: BookmarkStore
    private let boundary: @Sendable (URL, URL) -> Bool
    private let buildSHA: String
    public let storeCorrupt: Bool
    private var saved: [AccessRootRecord]
    private var roots: [AccessRootID: URL] = [:]
    private var previousRoots: [AccessRootID: [URL]] = [:]
    private var outcomes: [AccessRootID: String] = [:]
    private struct Active { let session: ScopeSession; var tokens: Set<UUID> }
    private enum SessionKey: Hashable { case root(AccessRootID, URL), file(URL, URL) }
    private var active: [SessionKey: Active] = [:]
    private var requests: [UUID: SessionKey] = [:]
    /// Session-only: File Grants never become persisted Access Roots.
    private struct FileGrantBookmark { var data: Data; var resource: FileResourceIdentity? }
    private var fileBookmarks: [URL: FileGrantBookmark] = [:]

    public init(scope: any SecurityScope, bookmarks: any BookmarkCoding, store: BookmarkStore, buildSHA: String,
                boundary: @escaping @Sendable (URL, URL) -> Bool = { AccessBoundary.contains($0, in: $1) }) throws {
        self.boundary = boundary
        self.scope = scope; self.bookmarks = bookmarks; self.buildSHA = buildSHA
        do {
            saved = try store.load()
            self.store = store; storeCorrupt = false
        } catch {
            // Preserve the damaged evidence; subsequent grants persist separately.
            let recovery = BookmarkStore(url: store.url.appendingPathExtension("recovered"))
            saved = (try? recovery.load()) ?? []
            self.store = recovery; storeCorrupt = true
            Logger(subsystem: "io.github.anzchy.picsee", category: "access").error("AccessStore kind=storeCorrupt")
        }
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
                    try self.store.save(refreshed)
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
    /// Published location only; Recent queries never create or refresh authority.
    public func rootURL(_ id: AccessRootID) -> URL? { roots[id] }
    private func publishRoot(_ id: AccessRootID, url: URL) {
        if let old = roots[id], old.standardizedFileURL != url.standardizedFileURL {
            var history = previousRoots[id] ?? []
            history.append(old)
            if history.count > 8 { history.removeFirst() }
            previousRoots[id] = history
        }
        roots[id] = url
    }
    public func resolveFileGrant(_ file: URL) throws -> URL {
        let key = file.standardizedFileURL
        guard let bookmark = fileBookmarks[key] else { return file }
        // A new inode at the old name could be a replacement or reuse after rename.
        if FileManager.default.fileExists(atPath: file.path) {
            let current = try? URLIdentityResourceReader().identity(for: file)
            if bookmark.resource == nil || current == bookmark.resource { return file }
            if let moved = try? resolveFileBookmark(bookmark, original: file), moved != file,
               FileManager.default.fileExists(atPath: moved.path) { return moved }
            let session = try ScopeSession(scope: scope, url: file, rootID: nil)
            defer { session.stop() }
            if let data = try? bookmarks.create(for: file) {
                fileBookmarks[key] = FileGrantBookmark(data: data, resource: current)
            }
            return file
        }
        return try resolveFileBookmark(bookmark, original: file)
    }
    private func resolveFileBookmark(_ bookmark: FileGrantBookmark, original: URL) throws -> URL {
        do {
            let resolved = try bookmarks.resolve(bookmark.data)
            if resolved.stale {
                let session = try ScopeSession(scope: scope, url: resolved.url, rootID: nil)
                defer { session.stop() }
                fileBookmarks[original.standardizedFileURL]?.data = try bookmarks.create(for: resolved.url)
            }
            return resolved.url
        } catch { throw FileAccessError.needsFileReconnection(original) }
    }
    /// A point-in-time access check for Recent, balanced before any UI decision.
    public func probeRootURL(_ id: AccessRootID) throws -> URL {
        guard let record = saved.first(where: { $0.id == id }), roots[id] != nil else {
            throw FileAccessError.needsReconnection(id)
        }
        let current: URL
        do { current = try bookmarks.resolve(record.bookmark).url }
        catch { roots.removeValue(forKey: id); throw FileAccessError.needsReconnection(id) }
        // A cached path may be obsolete after a move. Probe the resolved root itself;
        // acquire still validates scope and refreshes stale bookmarks as usual.
        let lease = try acquire(.root(id, file: current))
        release(lease)
        return lease.url
    }
    public func relocatedFolder(_ folder: URL, rootID id: AccessRootID) throws -> URL? {
        var candidates = previousRoots[id] ?? []
        if let currentRoot = roots[id] { candidates.append(currentRoot) }
        var oldRoot: URL?
        for candidate in candidates where folder.standardizedFileURL.pathComponents.starts(with: candidate.standardizedFileURL.pathComponents) {
            if let current = oldRoot, current.pathComponents.count >= candidate.pathComponents.count { continue }
            oldRoot = candidate
        }
        guard let oldRoot else { return nil }
        let newRoot = try probeRootURL(id)
        guard newRoot.standardizedFileURL != oldRoot.standardizedFileURL else { return nil }
        let suffix = folder.standardizedFileURL.pathComponents.dropFirst(oldRoot.standardizedFileURL.pathComponents.count)
        var rebased = newRoot
        for component in suffix { rebased.appendPathComponent(component) }
        return rebased
    }
    /// Only an explicit system-panel selection may replace a persisted root.
    public func reconnect(_ id: AccessRootID, folder: URL) throws -> URL {
        let logger = Logger(subsystem: "io.github.anzchy.picsee", category: "access")
        var phase = "scope"
        do {
            let session = try ScopeSession(scope: scope, url: folder, rootID: id)
            defer { session.stop() }
            phase = "directory"
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw FileAccessError.invalidFolder
            }
            phase = "collision"
            if let other = matchingRoot(canonical(folder), excluding: id) {
                throw FileAccessError.alreadyGranted(other)
            }
            phase = "bookmark"
            let bookmark = try bookmarks.create(for: folder)
            let previous = saved.first { $0.id == id }
            let record = AccessRootRecord(id: id, bookmark: bookmark, displayName: folder.lastPathComponent,
                creatingBuildSHA: previous?.creatingBuildSHA ?? buildSHA, createdAt: previous?.createdAt ?? Date())
            var replacement = saved.filter { $0.id != id }
            if let index = saved.firstIndex(where: { $0.id == id }) { replacement.insert(record, at: index) }
            else { replacement.append(record) }
            phase = "store"
            try store.save(replacement)
            saved = replacement; publishRoot(id, url: folder)
            logger.notice("AccessReconnect root=\(id.rawValue.uuidString, privacy: .public) outcome=reconnected error=none path=\(folder.path, privacy: .private)")
            return folder
        } catch {
            logger.notice("AccessReconnect root=\(id.rawValue.uuidString, privacy: .public) outcome=failed error=\(phase, privacy: .public) path=\(folder.path, privacy: .private)")
            throw error
        }
    }
    private func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }
    /// Canonicalizing another root may inspect metadata: hold its own scope too.
    private func matchingRoot(_ folder: URL, excluding id: AccessRootID? = nil) -> AccessRootID? {
        for record in saved where record.id != id {
            guard let url = roots[record.id] else { continue }
            if url.standardizedFileURL.pathComponents == folder.pathComponents { return record.id }
            guard let session = try? ScopeSession(scope: scope, url: url, rootID: record.id) else { continue }
            defer { session.stop() }
            if canonical(url).pathComponents == folder.pathComponents { return record.id }
        }
        return nil
    }
    public func rootCovering(_ file: URL) -> AccessRootID? {
        // Unscoped path resolution cannot establish authority. Confirm each
        // candidate using the same balanced, scoped check as an actual lease.
        for record in saved {
            if let lease = try? acquire(.root(record.id, file: file)) {
                release(lease)
                return record.id
            }
        }
        return nil
    }
    /// Only the composition root's successful system panel invokes this operation.
    public func grant(folder: URL) throws -> AccessRootID {
        let logger = Logger(subsystem: "io.github.anzchy.picsee", category: "access")
        var id = AccessRootID()
        var existing = false
        var started = false
        var phase = "scope"
        do {
            let session = try ScopeSession(scope: scope, url: folder, rootID: id)
            started = true
            defer { session.stop() }
            phase = "directory"
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw FileAccessError.invalidFolder
            }
            phase = "match"
            if let held = matchingRoot(canonical(folder)) { id = held; existing = true }
            phase = "bookmark"
            let bookmark = try bookmarks.create(for: folder)
            var replacement = saved
            if let index = replacement.firstIndex(where: { $0.id == id }) { replacement[index].bookmark = bookmark }
            else {
                replacement.append(AccessRootRecord(id: id, bookmark: bookmark, displayName: folder.lastPathComponent,
                    creatingBuildSHA: buildSHA, createdAt: Date()))
            }
            phase = "store"
            try store.save(replacement)
            saved = replacement; publishRoot(id, url: folder)
            logger.notice("AccessGrant kind=panelFolder scopeStarted=true root=\(id.rawValue.uuidString, privacy: .public) existing=\(existing, privacy: .public) outcome=granted path=\(folder.path, privacy: .private)")
            return id
        } catch {
            logger.notice("AccessGrant kind=panelFolder scopeStarted=\(started, privacy: .public) root=\(id.rawValue.uuidString, privacy: .public) existing=\(existing, privacy: .public) outcome=failed error=\(phase, privacy: .public) path=\(folder.path, privacy: .private)")
            throw error
        }
    }
    public func acquire(_ request: AccessRequest) throws -> AccessLease {
        let key: SessionKey
        let url: URL
        let rootID: AccessRootID?
        var staleRecord: AccessRootRecord?
        switch request {
        case .root(let id, let file):
            guard let record = saved.first(where: { $0.id == id }), roots[id] != nil else {
                throw FileAccessError.needsReconnection(id)
            }
            rootID = id
            do {
                // Resolution may follow a move even while older leases are held.
                let resolution = try bookmarks.resolve(record.bookmark)
                key = .root(id, resolution.url)
                url = active[key]?.session.url ?? resolution.url
                if resolution.stale { staleRecord = record }
            }
            catch { roots.removeValue(forKey: id); throw FileAccessError.needsReconnection(id) }
            if active[key] != nil, !boundary(file, url) { throw FileAccessError.outsideRoot }
        case .fileGrant(let file):
            url = try resolveFileGrant(file)
            key = .file(file.standardizedFileURL, url.standardizedFileURL); rootID = nil
        }
        let lease = AccessLease(url: url, rootID: rootID, resolvedFileURL: rootID == nil ? url : nil)
        if var entry = active[key] {
            if let record = staleRecord, roots[record.id] != url {
                do { try refreshBookmark(record, for: url) }
                catch {
                    roots.removeValue(forKey: record.id)
                    throw FileAccessError.needsReconnection(record.id)
                }
            }
            entry.tokens.insert(lease.token); active[key] = entry
        } else {
            let session: ScopeSession
            do { session = try ScopeSession(scope: scope, url: url, rootID: rootID) }
            catch {
                if case .fileGrant(let file) = request, fileBookmarks[file.standardizedFileURL] != nil {
                    throw FileAccessError.needsFileReconnection(file)
                }
                throw error
            }
            if case .root(_, let file) = request, !boundary(file, url) {
                session.stop()
                throw FileAccessError.outsideRoot
            }
            if let record = staleRecord {
                do { try refreshBookmark(record, for: url) }
                catch {
                    session.stop()
                    roots.removeValue(forKey: record.id)
                    throw FileAccessError.needsReconnection(record.id)
                }
            }
            active[key] = Active(session: session, tokens: [lease.token])
            if case .fileGrant(let file) = request, FileManager.default.fileExists(atPath: url.path),
               fileBookmarks[file.standardizedFileURL] == nil {
                if let data = try? bookmarks.create(for: url) {
                    fileBookmarks[file.standardizedFileURL] = FileGrantBookmark(data: data,
                        resource: try? URLIdentityResourceReader().identity(for: url))
                }
            }
        }
        if let rootID { publishRoot(rootID, url: url) }
        requests[lease.token] = key
        return lease
    }
    /// The caller holds either a newly started or an existing live session scope.
    private func refreshBookmark(_ record: AccessRootRecord, for url: URL) throws {
        var replacement = record
        replacement.bookmark = try bookmarks.create(for: url)
        let refreshed = saved.map { $0.id == record.id ? replacement : $0 }
        try store.save(refreshed)
        saved = refreshed
    }
    public func release(_ lease: AccessLease) {
        guard let key = requests.removeValue(forKey: lease.token), var entry = active[key] else { return }
        entry.tokens.remove(lease.token)
        if entry.tokens.isEmpty {
            entry.session.stop(); active.removeValue(forKey: key)
        } else { active[key] = entry }
    }
}
