import Foundation
import Observation
import PicseeCore

/// One scan owner per window. The scanning task retains its lease until enumeration really exits.
@MainActor @Observable public final class FolderScanCoordinator {
    public private(set) var snapshot: FolderSnapshot?
    public private(set) var generation: UInt64 = 0
    public private(set) var isReadingFolder = false
    public private(set) var failure: (any Error)?
    public private(set) var inputURL: URL?
    public internal(set) var currentItemID: ItemID?
    public internal(set) var currentURL: URL?
    public weak var host: (any FolderScanHost)?
    var pendingDirection: NavigationDirection?
    var automaticPresentationAllowed: (@MainActor () -> Bool)?
    private let access: any AccessLeasing
    private let scanner: any FolderScanning
    private let trace: (any FolderScanTracing)?
    private var firstBatchTraced = false
    private var scanTask: Task<Void, any Error>?
    private var activeGeneration: UInt64?
    private var activeFolder: (url: URL, rootID: AccessRootID)?
    public init(access: any AccessLeasing, scanner: any FolderScanning, trace: (any FolderScanTracing)? = nil) {
        self.access = access; self.scanner = scanner; self.trace = trace
    }
    @discardableResult public func begin(folder: URL, rootID: AccessRootID, input: URL? = nil,
        pending: NavigationDirection? = nil, canPresent: @escaping @MainActor () -> Bool = { true }) -> Task<Void, any Error> {
        stop(.replaced)
        generation &+= 1
        let token = generation
        activeGeneration = token
        activeFolder = (folder.standardizedFileURL, rootID)
        inputURL = input
        currentURL = input
        pendingDirection = pending
        automaticPresentationAllowed = canPresent
        isReadingFolder = input == nil
        firstBatchTraced = false
        trace?.begin(generation: token, folderURL: folder)
        let task = Task { [self] in
            do {
                try await Self.scanLeased(folder: folder, rootID: rootID, generation: token, input: input,
                    access: access, scanner: scanner, ready: { [self] version, itemID in
                        guard activeGeneration == token, !Task.isCancelled else { return }
                        snapshot = FolderSnapshot(version: version, entries: [], isComplete: false)
                        currentItemID = itemID
                    }, emit: { [self] batch in
                        guard activeGeneration == token, !Task.isCancelled, let snapshot else { return }
                        self.snapshot = snapshot.appending(batch, isComplete: false)
                        if !batch.isEmpty, !firstBatchTraced {
                            firstBatchTraced = true
                            trace?.firstBatch(count: batch.count, generation: token)
                        }
                        if isReadingFolder, let first = self.snapshot?.entries.first,
                           automaticPresentationAllowed?() != false {
                            isReadingFolder = false
                            currentItemID = first.itemID; currentURL = first.url
                            try await host?.rememberFolder(folder, rootID: rootID)
                            guard activeGeneration == token, automaticPresentationAllowed?() != false,
                                  !Task.isCancelled else { return }
                            host?.openFolderImage(first.url, rootID: rootID)
                        }
                        advancePending()
                    })
                try Task.checkCancellation()
                guard activeGeneration == token, let completed = snapshot else { return }
                let showEmpty = input == nil && completed.entries.isEmpty && automaticPresentationAllowed?() != false
                activeGeneration = nil
                activeFolder = nil
                snapshot = completed.appending([], isComplete: true)
                pendingDirection = nil
                isReadingFolder = false
                scanTask = nil
                trace?.complete(count: completed.entries.count, generation: token)
                trace?.end(outcome: .complete, generation: token)
                if showEmpty { host?.showEmptyFolder() }
            } catch {
                guard activeGeneration == token else { return }
                activeGeneration = nil
                activeFolder = nil
                isReadingFolder = false
                scanTask = nil
                if error is CancellationError || Task.isCancelled {
                    snapshot = nil; inputURL = nil; currentItemID = nil; currentURL = nil; pendingDirection = nil
                    trace?.end(outcome: .cancelled, generation: token)
                    return
                }
                snapshot = snapshot?.appending([], isComplete: true)
                pendingDirection = nil
                failure = error
                trace?.end(outcome: .failed, generation: token)
                throw error
            }
        }
        scanTask = task
        return task
    }
    /// Coalesce arrows while the current input has not reached the admitted batches yet.
    public func queueNavigation(_ direction: NavigationDirection, folder: URL, input: URL, rootID: AccessRootID? = nil) -> Bool {
        guard activeGeneration != nil, scanTask?.isCancelled != true, let activeFolder,
              activeFolder.url.path == folder.standardizedFileURL.path,
              rootID == nil || rootID == activeFolder.rootID,
              input.standardizedFileURL == inputURL?.standardizedFileURL,
              currentURL?.standardizedFileURL == input.standardizedFileURL else { return false }
        pendingDirection = direction
        advancePending()
        return true
    }
    public func cancel() { end() }
    public func end() { stop(.cancelled) }
    private func stop(_ outcome: FolderScanOutcome) {
        let ending = activeGeneration
        activeGeneration = nil
        activeFolder = nil
        scanTask?.cancel()
        scanTask = nil
        snapshot = nil
        inputURL = nil
        currentItemID = nil
        currentURL = nil
        pendingDirection = nil
        automaticPresentationAllowed = nil
        isReadingFolder = false
        failure = nil
        if let ending { trace?.end(outcome: outcome, generation: ending) }
    }
    /// Explicitly nonisolated: path canonicalization and scanning begin only inside the acquired lease.
    private nonisolated static func scanLeased(folder: URL, rootID: AccessRootID, generation: UInt64, input: URL?,
        access: any AccessLeasing, scanner: any FolderScanning,
        ready: @MainActor @Sendable (SnapshotVersion, ItemID?) -> Void,
        emit: @MainActor @Sendable ([FolderEntry]) async throws -> Void) async throws {
        try await access.withLease(.root(rootID, file: folder)) { lease in
            let version = SnapshotVersion(rootID: rootID, folder: folder, generation: generation)
            let root = ItemIdentityRoot(id: rootID, url: lease.url)
            let itemID = input.flatMap { AccessBoundary.contains($0, in: lease.url) ? FolderEntry(url: $0, root: root).itemID : nil }
            await ready(version, itemID)
            try Task.checkCancellation()
            try await scanner.scan(in: folder, root: root) { batch in
                try await emit(batch)
            }
        }
    }
}
