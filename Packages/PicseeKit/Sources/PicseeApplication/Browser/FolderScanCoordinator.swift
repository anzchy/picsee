import Foundation
import Observation
import PicseeCore

struct FolderScanRestorePoint {
    let source: FolderSnapshot
    let conditions: FolderViewConditions
    let loopEnabled: Bool
    let inputURL: URL?
    let currentItemID: ItemID?
    let currentURL: URL?
}

/// One scan owner per window. The scanning task retains its lease until enumeration really exits.
@MainActor @Observable public final class FolderScanCoordinator {
    public private(set) var snapshot: FolderSnapshot?
    public private(set) var sourceSnapshot: FolderSnapshot?
    public private(set) var conditions = FolderViewConditions()
    public private(set) var loopEnabled = false
    public private(set) var recursiveEnabled = false
    public var hasNoMatches: Bool {
        sourceSnapshot?.entries.isEmpty == false && snapshot?.entries.isEmpty == true
    }
    public var availableExtensions: [String] {
        Array(Set(sourceSnapshot?.entries.map(\.normalizedExtension) ?? [])).sorted()
    }
    public func preservesPresentationAuthorityForRetry(_ url: URL, accessRequest: AccessRequest?) -> Bool {
        guard case .root(let requestRoot, let file)? = accessRequest,
              let rootID = activeFolder?.rootID ?? sourceSnapshot?.version.rootID,
              requestRoot == rootID,
              file.standardizedFileURL == url.standardizedFileURL,
              inputURL?.standardizedFileURL == url.standardizedFileURL,
              currentURL?.standardizedFileURL == url.standardizedFileURL,
              automaticPresentationAllowed?() != false else { return false }
        return true
    }
    public func setConditions(_ value: FolderViewConditions) {
        conditions = value
        projectSource()
    }
    public func setLoopEnabled(_ value: Bool) { loopEnabled = value }
    @discardableResult public func setRecursiveEnabled(_ value: Bool) -> Task<Void, any Error>? {
        guard recursiveEnabled != value else { return nil }
        recursiveEnabled = value
        guard let folder = activeFolder ?? sourceSnapshot.map({ ($0.version.folder, $0.version.rootID) }),
            let canPresent = automaticPresentationAllowed else { return nil }
        let shown = currentURL
        let staysInFlatFolder = shown?.deletingLastPathComponent().standardizedFileURL == folder.url.standardizedFileURL
        let retainedInput = value || staysInFlatFolder ? shown : nil
        return start(folder: folder.url, rootID: folder.rootID, input: retainedInput,
            canPresent: canPresent, preserveConditions: true,
            clearExcludedOnEmpty: !value && shown != nil && !staysInFlatFolder)
    }
    public private(set) var generation: UInt64 = 0
    public var isScanning: Bool { activeGeneration != nil }
    public private(set) var isReadingFolder = false
    public private(set) var failure: (any Error)?
    public var completedImageCount: Int? {
        guard failure == nil, sourceSnapshot?.isComplete == true else { return nil }
        return sourceSnapshot?.navigationEntries.count
    }
    public var failureReason: String? {
        guard let failure else { return nil }
        if failure is FolderScanLimitError { return "Scan limit reached" }
        if failure is FileAccessError { return "Folder access denied" }
        let error = failure as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return "Folder access denied" }
        if error.domain == NSPOSIXErrorDomain {
            if error.code == Int(POSIXError.Code.EACCES.rawValue) { return "Folder access denied" }
            if error.code == Int(POSIXError.Code.EPERM.rawValue) { return "Folder access denied" }
        }
        return "Folder scan failed"
    }
    @discardableResult public func retry() -> Task<Void, any Error>? {
        guard failure != nil, let activeFolder, let canPresent = automaticPresentationAllowed else { return nil }
        return start(folder: activeFolder.url, rootID: activeFolder.rootID,
            canPresent: canPresent, preserveConditions: true)
    }
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
    private var noMatchesPresented = false
    var presentationRevision: UInt64 = 0
    private var scanTask: Task<Void, any Error>?
    private var activeGeneration: UInt64?
    private var activeFolder: (url: URL, rootID: AccessRootID)?
    public init(access: any AccessLeasing, scanner: any FolderScanning, trace: (any FolderScanTracing)? = nil) {
        self.access = access; self.scanner = scanner; self.trace = trace
    }
    @discardableResult public func begin(folder: URL, rootID: AccessRootID, input: URL? = nil,
        pending: NavigationDirection? = nil, canPresent: @escaping @MainActor () -> Bool = { true }) -> Task<Void, any Error> {
        start(folder: folder, rootID: rootID, input: input, pending: pending, canPresent: canPresent,
            preserveConditions: false)
    }
    @discardableResult private func start(folder: URL, rootID: AccessRootID, input: URL? = nil,
        pending: NavigationDirection? = nil, canPresent: @escaping @MainActor () -> Bool,
        preserveConditions: Bool, clearExcludedOnEmpty: Bool = false) -> Task<Void, any Error> {
        let previousConditions = conditions
        stop(.replaced)
        conditions = preserveConditions ? previousConditions : FolderViewConditions()
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
                    options: FolderScanOptions(recursive: recursiveEnabled),
                    access: access, scanner: scanner, ready: { [self] version, itemID in
                        guard activeGeneration == token, !Task.isCancelled else { return }
                        sourceSnapshot = FolderSnapshot(version: version, entries: [], isComplete: false)
                        snapshot = sourceSnapshot?.applying(conditions)
                        currentItemID = itemID
                    }, emit: { [self] batch in
                        guard activeGeneration == token, !Task.isCancelled, retainReadingAuthority(), let sourceSnapshot else { return }
                        self.sourceSnapshot = sourceSnapshot.appending(batch, isComplete: false)
                        projectSource()
                        if !batch.isEmpty, !firstBatchTraced {
                            firstBatchTraced = true
                            trace?.firstBatch(count: batch.count, generation: token)
                        }
                        advancePending()
                    })
                try Task.checkCancellation()
                guard activeGeneration == token, retainReadingAuthority(), let completed = sourceSnapshot else { return }
                let showEmpty = input == nil && completed.entries.isEmpty && automaticPresentationAllowed?() != false
                sourceSnapshot = completed.appending([], isComplete: true)
                projectSource()
                let first = input == nil ? snapshot?.entries.first : nil
                pendingDirection = nil
                isReadingFolder = false
                scanTask = nil
                presentNoMatchesIfNeeded()
                if clearExcludedOnEmpty, !hasNoMatches, snapshot?.navigationEntries.isEmpty == true {
                    currentItemID = nil; currentURL = nil; inputURL = nil
                    presentationRevision &+= 1
                    host?.clearFolderImageForNoMatches()
                }
                if let first, automaticPresentationAllowed?() != false {
                    currentItemID = first.itemID; currentURL = first.url
                    let initialPresentationRevision = presentationRevision
                    try await host?.rememberFolder(folder, rootID: rootID)
                    guard activeGeneration == token else { return }
                    guard automaticPresentationAllowed?() != false else {
                        stop(.replaced)
                        return
                    }
                    try Task.checkCancellation()
                    // Only a newer host presentation or clear supersedes this pending first image.
                    if presentationRevision == initialPresentationRevision,
                       currentItemID == first.itemID,
                       currentURL?.standardizedFileURL == first.url.standardizedFileURL,
                       snapshot?.entries.contains(where: {
                           $0.itemID == first.itemID && $0.url.standardizedFileURL == first.url.standardizedFileURL
                       }) == true {
                        host?.openFolderImage(first.url, rootID: rootID)
                    }
                }
                guard activeGeneration == token, !Task.isCancelled else { return }
                activeGeneration = nil
                activeFolder = nil
                trace?.complete(count: completed.navigationEntries.count, generation: token)
                trace?.end(outcome: .complete, generation: token)
                host?.folderScanDidComplete(count: completed.navigationEntries.count)
                if showEmpty { host?.showEmptyFolder() }
            } catch {
                guard activeGeneration == token else { return }
                if !Task.isCancelled, !retainReadingAuthority() { return }
                activeGeneration = nil
                isReadingFolder = false
                scanTask = nil
                if error is CancellationError || Task.isCancelled {
                    activeFolder = nil
                    snapshot = nil; inputURL = nil; currentItemID = nil; currentURL = nil; pendingDirection = nil
                    trace?.end(outcome: .cancelled, generation: token)
                    return
                }
                snapshot = sourceSnapshot?.applying(conditions)
                pendingDirection = nil
                failure = error
                trace?.failure(error, generation: token)
                trace?.end(outcome: .failed, generation: token)
                host?.folderScanDidEnd()
                throw error
            }
        }
        scanTask = task
        host?.folderScanDidStart()
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
    /// A complete folder source Cancel Reading can put back; nil while scanning or after a cancel.
    var restorePoint: FolderScanRestorePoint? {
        guard let sourceSnapshot, sourceSnapshot.isComplete else { return nil }
        return FolderScanRestorePoint(source: sourceSnapshot, conditions: conditions, loopEnabled: loopEnabled,
            inputURL: inputURL, currentItemID: currentItemID, currentURL: currentURL)
    }
    /// Restores without scanning and without an active generation, so a cancelled scan's late events stay ignored.
    func restore(_ point: FolderScanRestorePoint) {
        stop(.cancelled)
        conditions = point.conditions
        loopEnabled = point.loopEnabled
        inputURL = point.inputURL
        currentItemID = point.currentItemID
        currentURL = point.currentURL
        sourceSnapshot = point.source
        snapshot = point.source.applying(point.conditions)
    }
    public func cancel() { end() }
    public func end() { stop(.cancelled) }
    private func projectSource() {
        guard let sourceSnapshot else { return }
        snapshot = sourceSnapshot.applying(conditions)
        guard let snapshot, !isReadingFolder, automaticPresentationAllowed?() != false else { return }
        if snapshot.entries.isEmpty {
            presentNoMatchesIfNeeded()
            return
        }
        noMatchesPresented = false
        if let currentItemID, let index = snapshot.navigationIndex(for: currentItemID) {
            let visibleURL = currentURL?.standardizedFileURL
            if snapshot.entries.contains(where: {
                $0.itemID == currentItemID && $0.url.standardizedFileURL == visibleURL
            }) { return }
            // Aliases can share identity while exposing different extensions. Use an eligible URL.
            let replacement = snapshot.navigationEntries[index]
            currentURL = replacement.url
            presentationRevision &+= 1
            host?.openFolderImage(replacement.url, rootID: snapshot.version.rootID)
            return
        }
        // An eligible explicit input may still be in a later batch. An excluded input cannot remain visible.
        let inputMayBeEligible = conditions.selectedExtensions?.contains {
            $0.caseInsensitiveCompare(currentURL?.pathExtension ?? "") == .orderedSame
        } ?? true
        if let currentItemID, sourceSnapshot.navigationIndex(for: currentItemID) == nil,
           inputMayBeEligible { return }
        guard let first = snapshot.navigationEntries.first else { return }
        currentItemID = first.itemID; currentURL = first.url
        presentationRevision &+= 1
        host?.openFolderImage(first.url, rootID: snapshot.version.rootID)
    }
    private func presentNoMatchesIfNeeded() {
        guard hasNoMatches, !noMatchesPresented else { return }
        noMatchesPresented = true
        currentItemID = nil; currentURL = nil; pendingDirection = nil
        presentationRevision &+= 1
        host?.clearFolderImageForNoMatches()
    }
    private func retainReadingAuthority() -> Bool {
        guard isReadingFolder, automaticPresentationAllowed?() == false else { return true }
        stop(.replaced)
        return false
    }
    private func stop(_ outcome: FolderScanOutcome) {
        let ending = activeGeneration
        activeGeneration = nil
        activeFolder = nil
        scanTask?.cancel()
        scanTask = nil
        snapshot = nil
        sourceSnapshot = nil
        inputURL = nil
        currentItemID = nil
        currentURL = nil
        pendingDirection = nil
        automaticPresentationAllowed = nil
        isReadingFolder = false
        failure = nil
        noMatchesPresented = false
        if let ending { trace?.end(outcome: outcome, generation: ending) }
        host?.folderScanDidEnd()
    }
    /// Explicitly nonisolated: path canonicalization and scanning begin only inside the acquired lease.
    private nonisolated static func scanLeased(folder: URL, rootID: AccessRootID, generation: UInt64, input: URL?,
        options: FolderScanOptions,
        access: any AccessLeasing, scanner: any FolderScanning,
        ready: @MainActor @Sendable (SnapshotVersion, ItemID?) -> Void,
        emit: @MainActor @Sendable ([FolderEntry]) async throws -> Void) async throws {
        try await access.withLease(.root(rootID, file: folder)) { lease in
            let version = SnapshotVersion(rootID: rootID, folder: folder, generation: generation)
            let root = ItemIdentityRoot(id: rootID, url: lease.url)
            let itemID = input.flatMap { AccessBoundary.contains($0, in: lease.url) ? FolderEntry(url: $0, root: root).itemID : nil }
            await ready(version, itemID)
            try Task.checkCancellation()
            try await scanner.scan(in: folder, root: root, options: options) { batch in
                try await emit(batch)
            }
        }
    }
}
