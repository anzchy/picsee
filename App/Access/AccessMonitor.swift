import AppKit
import Foundation
import PicseeCore
import PicseeApplication
import PicseeInfrastructure

private final class AccessMonitorNotification: @unchecked Sendable {
    let center: NotificationCenter
    let token: any NSObjectProtocol
    init(center: NotificationCenter, name: Notification.Name,
         handler: @escaping @Sendable (Notification) -> Void) {
        self.center = center
        token = center.addObserver(forName: name, object: nil, queue: nil, using: handler)
    }
    deinit { center.removeObserver(token) }
}

/// One application-wide bridge from disk events and real root reads to access state.
@MainActor final class AccessMonitor {
    struct ReadContext: Sendable {
        let permit: AccessWorkPermit
        let stamp: AccessWorkStamp
    }
    let state: AccessState
    let files: FileAccess
    let mounts: (any DiskMountPort)?
    private var port: (any DiskMountPort)?
    private var startup: Task<Void, Never>?
    private var events: Task<Void, Never>?
    private var notifications: [AccessMonitorNotification] = []
    private var mountEventRevision: UInt64 = 0
    private var latestMountEvents: [String: (revision: UInt64, mounted: Bool)] = [:]
    private var recoveryObservers: [UUID: @MainActor (AccessRecoveryAttempt) -> Void] = [:]
    private var reauthorizationRequests: [AccessRootID: UUID] = [:]

    nonisolated init(files: FileAccess, mounts: (any DiskMountPort)? = nil) {
        self.files = files
        self.mounts = mounts
        self.state = AccessState()
    }
    deinit { events?.cancel() }

    func start() async {
        if let startup { await startup.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let port = mounts ?? SystemDiskMountPort()
            self.port = port
            let stream = await port.events()
            events = Task { @MainActor [weak self] in
                defer { (port as? SystemDiskMountPort)?.stop() }
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    self?.receive(event)
                }
            }
            // Subscribe before enumerating roots. The latest event map also covers
            // an unmount delivered while a root's metadata is being queried.
            for record in await files.records() { await registerEntry(record.id) }
            notifications = [
                AccessMonitorNotification(center: .default, name: NSApplication.didBecomeActiveNotification) { [weak self] _ in
                    Task { @MainActor [weak self] in await self?.recheckRoots() }
                },
                AccessMonitorNotification(center: NSWorkspace.shared.notificationCenter, name: NSWorkspace.didWakeNotification) { [weak self] _ in
                    Task { @MainActor [weak self] in await self?.recheckRoots() }
                }
            ]
        }
        startup = task
        await task.value
    }

    private func receive(_ event: DiskMountEvent) {
        switch event {
        case .unmounted(let volume):
            guard let uuid = volume.uuid else { return }
            mountEventRevision &+= 1
            latestMountEvents[uuid] = (mountEventRevision, false)
            state.diskUnmounted(volumeUUID: uuid)
        case .mounted(let volume):
            guard let uuid = volume.uuid else { return }
            mountEventRevision &+= 1
            latestMountEvents[uuid] = (mountEventRevision, true)
            for attempt in state.diskMounted(volumeUUID: uuid) { publishRecovery(attempt) }
        }
    }
    func register(_ id: AccessRootID) async {
        await start()
        await registerEntry(id)
    }
    private func registerEntry(_ id: AccessRootID) async {
        guard state.snapshot(for: id) == nil else { return }
        let volume = await files.savedVolume(id)
        let root = await files.rootURL(id)
        let mounted: Bool
        if let uuid = volume?.uuid { mounted = await isMounted(uuid) }
        else { mounted = true }
        guard state.snapshot(for: id) == nil else { return }
        state.register(id, volumeUUID: volume?.uuid)
        if let uuid = volume?.uuid, !mounted {
            state.diskUnmounted(volumeUUID: uuid)
        } else if root == nil {
            _ = state.reportRootFailure(id, cause: .unknown, from: state.stamp(for: id))
        }
    }
    func reauthorize(_ id: AccessRootID) async {
        let request = UUID()
        reauthorizationRequests[id] = request
        defer {
            if reauthorizationRequests[id] == request { reauthorizationRequests.removeValue(forKey: id) }
        }
        await start()
        guard reauthorizationRequests[id] == request else { return }
        guard let grant = await files.savedGrantSnapshot(id) else {
            guard reauthorizationRequests[id] == request else { return }
            if let current = state.snapshot(for: id) {
                markUnavailable(id, volumeUUID: current.volumeUUID, cause: .unknown)
            }
            return
        }
        guard reauthorizationRequests[id] == request else { return }
        let volume = grant.bookmarkVolume
        let counter = state.snapshot(for: id)?.counter
        let verificationRevision = volume.uuid.flatMap { latestMountEvents[$0]?.revision }
        let failure: AccessLossCause?
        if volume.uuid != nil, let port, let root = grant.rootURL {
            let result = await files.verifySavedRootForRecovery(id, folder: root, mounts: port)
            guard ownsReauthorization(id, request: request, counter: counter) else { return }
            guard result.bookmarkVolume.uuid == volume.uuid else {
                markUnavailable(id, volumeUUID: volume.uuid, cause: .unknown)
                return
            }
            failure = result.classification.cause == .readable ? nil
                : result.classification.cause == .diskNotConnected ? .diskNotConnected : .unknown
        } else {
            // The persistent grant is already app-wide. Cancellation of the
            // initiating UI task must not turn a skipped check into success.
            let verification = Task { @MainActor [self] in await rootReadFailure(id) }
            failure = await verification.value
            guard ownsReauthorization(id, request: request, counter: counter) else { return }
        }
        if let uuid = volume.uuid {
            let revision = latestMountEvents[uuid]?.revision
            let mounted = await port?.mountedVolumes() ?? []
            guard ownsReauthorization(id, request: request, counter: counter) else { return }
            let latest = latestMountEvents[uuid]
            let connected = latest?.revision != revision ? latest?.mounted == true
                : mounted.contains { $0.uuid == uuid }
            guard connected else { markUnavailable(id, volumeUUID: uuid, cause: .diskNotConnected); return }
            guard latest?.revision == verificationRevision else {
                markUnavailable(id, volumeUUID: uuid, cause: .unknown); return
            }
        }
        if let failure { markUnavailable(id, volumeUUID: volume.uuid, cause: failure); return }
        do {
            // No suspension separates this generation proof from the state
            // mutation. State observers run after the grant fence is released.
            try state.reauthorize(id, volumeUUID: volume.uuid, admitting: { update in
                try grant.admitting(update)
            })
        } catch {
            guard ownsReauthorization(id, request: request, counter: counter) else { return }
            markUnavailable(id, volumeUUID: volume.uuid, cause: .unknown)
        }
    }
    private func ownsReauthorization(_ id: AccessRootID, request: UUID, counter: UInt64?) -> Bool {
        reauthorizationRequests[id] == request && state.snapshot(for: id)?.counter == counter
    }
    private func markUnavailable(_ id: AccessRootID, volumeUUID: String?, cause: AccessLossCause) {
        if state.snapshot(for: id)?.volumeUUID != volumeUUID || state.snapshot(for: id) == nil {
            state.register(id, volumeUUID: volumeUUID)
        }
        if state.snapshot(for: id)?.availability == .readable {
            _ = state.reportRootFailure(id, cause: cause, from: state.stamp(for: id))
        } else if cause == .diskNotConnected, let volumeUUID {
            state.diskUnmounted(volumeUUID: volumeUUID)
        }
    }
    func readContext(for id: AccessRootID) async throws -> ReadContext {
        await register(id)
        try Task.checkCancellation()
        guard let permit = state.permit(for: id) else { throw FileAccessError.needsReconnection(id) }
        return ReadContext(permit: permit, stamp: state.stamp(for: id))
    }

    /// A descendant's failure is only evidence to check the root, never proof
    /// that the whole root lost access. The captured counter survives every await.
    func reportReadFailure(_ id: AccessRootID, from stamp: AccessWorkStamp) async {
        guard stamp.rootID == id, !Task.isCancelled else { return }
        await start()
        guard !Task.isCancelled, state.mayDeliver(stamp) else { return }
        let cause = await rootReadFailure(id)
        guard !Task.isCancelled, let cause, state.mayDeliver(stamp) else { return }
        _ = state.reportRootFailure(id, cause: cause, from: stamp)
    }
    private func rootReadFailure(_ id: AccessRootID) async -> AccessLossCause? {
        guard !Task.isCancelled else { return nil }
        let volume = await files.savedVolume(id)
        if let uuid = volume?.uuid, !(await isMounted(uuid)) {
            return .diskNotConnected
        }
        do {
            let root = try await files.probeRootURL(id)
            _ = try await files.withLease(.root(id, file: root)) { lease in
                try FileManager.default.contentsOfDirectory(at: lease.url, includingPropertiesForKeys: nil).count
            }
            return nil
        } catch is CancellationError { return nil }
        catch { return Task.isCancelled ? nil : .unknown }
    }
    private func isMounted(_ uuid: String) async -> Bool {
        let revision = latestMountEvents[uuid]?.revision
        let mounted = await port?.mountedVolumes() ?? []
        // Only an event delivered during enumeration may override its snapshot.
        // A remembered mount must not mask a later missed unmount on foreground.
        if let latest = latestMountEvents[uuid], latest.revision != revision { return latest.mounted }
        return mounted.contains { $0.uuid == uuid }
    }
    private func recheckRoots() async {
        for record in await files.records() {
            if state.snapshot(for: record.id)?.availability == .readable {
                await reportReadFailure(record.id, from: state.stamp(for: record.id))
            } else if let attempt = state.recoveryAttempt(for: record.id) {
                publishRecovery(attempt)
            }
        }
    }
    @discardableResult func observeRecovery(_ observer: @escaping @MainActor (AccessRecoveryAttempt) -> Void) -> UUID {
        let id = UUID(); recoveryObservers[id] = observer; return id
    }
    func removeRecoveryObserver(_ id: UUID) { recoveryObservers.removeValue(forKey: id) }
    private func publishRecovery(_ attempt: AccessRecoveryAttempt) {
        for observer in Array(recoveryObservers.values) { observer(attempt) }
    }
}
