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
    private var scanTask: Task<Void, any Error>?
    private var activeGeneration: UInt64?
    public init(access: any AccessLeasing, scanner: any FolderScanning) {
        self.access = access; self.scanner = scanner
    }
    @discardableResult public func begin(folder: URL, rootID: AccessRootID, input: URL? = nil,
        pending: NavigationDirection? = nil, canPresent: @escaping @MainActor () -> Bool = { true }) -> Task<Void, any Error> {
        end()
        generation &+= 1
        let token = generation
        activeGeneration = token
        inputURL = input
        currentURL = input
        pendingDirection = pending
        automaticPresentationAllowed = canPresent
        isReadingFolder = input == nil
        let task = Task { [self] in
            do {
                try await Self.scanLeased(folder: folder, rootID: rootID, generation: token, input: input,
                    access: access, scanner: scanner, ready: { [self] version, itemID in
                        guard activeGeneration == token else { return }
                        snapshot = FolderSnapshot(version: version, entries: [], isComplete: false)
                        currentItemID = itemID
                    }, emit: { [self] batch in
                        guard activeGeneration == token, let snapshot else { return }
                        self.snapshot = snapshot.appending(batch, isComplete: false)
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
                guard activeGeneration == token else { return }
                let showEmpty = input == nil && snapshot?.entries.isEmpty == true && automaticPresentationAllowed?() != false
                activeGeneration = nil
                snapshot = snapshot?.appending([], isComplete: true)
                pendingDirection = nil
                isReadingFolder = false
                scanTask = nil
                if showEmpty { host?.showEmptyFolder() }
            } catch {
                guard activeGeneration == token else { return }
                activeGeneration = nil
                isReadingFolder = false
                scanTask = nil
                if error is CancellationError {
                    snapshot = nil; inputURL = nil; currentItemID = nil; currentURL = nil; pendingDirection = nil
                    return
                }
                failure = error
                throw error
            }
        }
        scanTask = task
        return task
    }
    public func cancel() { end() }
    public func end() {
        activeGeneration = nil
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
