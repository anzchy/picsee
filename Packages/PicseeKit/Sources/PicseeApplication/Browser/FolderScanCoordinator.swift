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
    private let access: any AccessLeasing
    private let scanner: any FolderScanning
    private var scanTask: Task<Void, any Error>?
    private var activeGeneration: UInt64?
    public init(access: any AccessLeasing, scanner: any FolderScanning) {
        self.access = access; self.scanner = scanner
    }
    @discardableResult public func begin(folder: URL, rootID: AccessRootID, input: URL? = nil) -> Task<Void, any Error> {
        end()
        generation &+= 1
        let token = generation
        activeGeneration = token
        inputURL = input
        isReadingFolder = input == nil
        let task = Task { [self] in
            do {
                try await Self.scanLeased(folder: folder, rootID: rootID, generation: token,
                    access: access, scanner: scanner, ready: { [self] version in
                        guard activeGeneration == token else { return }
                        snapshot = FolderSnapshot(version: version, entries: [], isComplete: false)
                    }, emit: { [self] batch in
                        guard activeGeneration == token, let snapshot else { return }
                        self.snapshot = snapshot.appending(batch, isComplete: false)
                    })
                try Task.checkCancellation()
                guard activeGeneration == token else { return }
                activeGeneration = nil
                snapshot = snapshot?.appending([], isComplete: true)
                isReadingFolder = false
                scanTask = nil
            } catch {
                guard activeGeneration == token else { return }
                activeGeneration = nil
                isReadingFolder = false
                scanTask = nil
                if error is CancellationError { snapshot = nil; inputURL = nil; return }
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
        isReadingFolder = false
        failure = nil
    }
    /// Explicitly nonisolated: path canonicalization and scanning begin only inside the acquired lease.
    private nonisolated static func scanLeased(folder: URL, rootID: AccessRootID, generation: UInt64,
        access: any AccessLeasing, scanner: any FolderScanning,
        ready: @MainActor @Sendable (SnapshotVersion) -> Void,
        emit: @MainActor @Sendable ([FolderEntry]) -> Void) async throws {
        try await access.withLease(.root(rootID, file: folder)) { lease in
            let version = SnapshotVersion(rootID: rootID, folder: folder, generation: generation)
            await ready(version)
            try Task.checkCancellation()
            try await scanner.scan(in: folder, root: ItemIdentityRoot(id: rootID, url: lease.url)) { batch in
                await emit(batch)
            }
        }
    }
}
