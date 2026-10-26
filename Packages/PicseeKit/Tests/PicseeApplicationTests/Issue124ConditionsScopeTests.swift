import Foundation
import Testing
import PicseeCore
@testable import PicseeApplication

private final class Issue124MetadataReader: FolderMetadataReading, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    func read(_ url: URL) throws -> FolderImageMetadata {
        lock.lock(); recorded.append(url.lastPathComponent); lock.unlock()
        return .init(captureDate: Date(timeIntervalSince1970: 100), pixelWidth: 10, pixelHeight: 20)
    }
    var requested: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
}

@Test @MainActor func issue124SameFolderBeginKeepsFilterAndSortButDifferentFolderClearsFilter() async throws {
    let fixture = FolderScanFixture(), scan = fixture.coordinator
    let first = scan.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg", "b.png"])
    await fixture.scanner.finish(); try await first.value
    scan.setConditions(.init(sort: .size, direction: .descending, selectedExtensions: ["png"]))

    // Reopening the same root covers nonmember navigation and renewed grants.
    let same = scan.begin(folder: fixture.folder, rootID: fixture.id,
        input: fixture.folder.appendingPathComponent("outside.tiff"))
    await fixture.scanner.waitForStart(1)
    #expect(scan.conditions == .init(sort: .size, direction: .descending, selectedExtensions: ["png"]))
    try await fixture.scanner.deliver(["a.jpg", "b.png"], at: 1)
    await fixture.scanner.finish(1); try await same.value
    #expect(scan.snapshot?.entries.map(\.url.lastPathComponent) == ["b.png"])

    let other = fixture.root.appendingPathComponent("B")
    let next = scan.begin(folder: other, rootID: fixture.id)
    await fixture.scanner.waitForStart(2)
    #expect(scan.conditions == .init(sort: .size, direction: .descending))
    try await fixture.scanner.deliver(["c.jpg"], at: 2)
    await fixture.scanner.finish(2); try await next.value
}

@Test @MainActor func issue124RecursiveAndRetryKeepFilter() async throws {
    let fixture = FolderScanFixture(), scan = fixture.coordinator
    let first = scan.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg", "b.png"])
    await fixture.scanner.finish(); try await first.value
    scan.setConditions(.init(selectedExtensions: ["png"]))
    let recursive = try #require(scan.setRecursiveEnabled(true))
    await fixture.scanner.waitForStart(1)
    #expect(scan.conditions.selectedExtensions == ["png"])
    await fixture.scanner.finish(1, failing: true)
    _ = try? await recursive.value
    let retry = try #require(scan.retry())
    await fixture.scanner.waitForStart(2)
    #expect(scan.conditions.selectedExtensions == ["png"])
    try await fixture.scanner.deliver(["a.jpg", "b.png"], at: 2)
    await fixture.scanner.finish(2); try await retry.value
    #expect(scan.snapshot?.entries.map(\.url.lastPathComponent) == ["b.png"])
}

@Test @MainActor func issue124SortIsSharedAcrossWindowsAndSurvivesEncoding() throws {
    let store = InMemoryDisplayPreferencesStore()
    let first = ViewerSession(preferencesStore: store)
    let second = ViewerSession(preferencesStore: store)
    let firstScan = FolderScanFixture().coordinator
    let secondScan = FolderScanFixture().coordinator
    first.folderScan = firstScan
    second.folderScan = secondScan
    first.setFolderConditions(.init(sort: .captureDate, direction: .descending, selectedExtensions: ["png"]))
    #expect(store.value.folderSort == .captureDate)
    #expect(store.value.folderSortDirection == .descending)
    #expect(second.folderConditions.sort == .captureDate)
    #expect(second.folderConditions.direction == .descending)
    #expect(second.folderConditions.selectedExtensions == nil)
    let encoded = try JSONEncoder().encode(store.value)
    let decoded = try JSONDecoder().decode(DisplayPreferences.self, from: encoded)
    #expect(decoded.folderSort == .captureDate)
    #expect(decoded.folderSortDirection == .descending)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("selectedExtensions"))
}

@Test @MainActor func issue124MenuSelectionReflectsRetainedConditions() async throws {
    let fixture = FolderScanFixture(), scan = fixture.coordinator
    let first = scan.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg", "b.png"])
    await fixture.scanner.finish(); try await first.value
    scan.setConditions(.init(sort: .pixelDimensions, direction: .descending, selectedExtensions: ["png"]))
    let same = scan.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart(1)
    try await fixture.scanner.deliver(["a.jpg", "b.png"], at: 1)
    await fixture.scanner.finish(1); try await same.value
    let selection = FolderMenuSelection(conditions: scan.conditions, loopEnabled: scan.loopEnabled)
    for action in [FolderMenuAction.sort(.pixelDimensions), .direction(.descending), .extensionType("png")] {
        #expect(FolderMenuPolicy.state(for: action, selection: selection,
            hasFolderSource: true, previewActive: false).checked)
    }
    #expect(!FolderMenuPolicy.state(for: .clearFilter, selection: selection,
        hasFolderSource: true, previewActive: false).checked)
}

@Test @MainActor func issue124SameFolderRegrantKeepsExtensionFilterWithNewRootID() async throws {
    let fixture = FolderScanFixture(), scan = fixture.coordinator
    let first = scan.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    await fixture.scanner.finish(); try await first.value
    scan.setConditions(.init(selectedExtensions: ["png"]))
    let regranted = scan.begin(folder: fixture.folder, rootID: AccessRootID())
    await fixture.scanner.waitForStart(1)
    #expect(scan.conditions.selectedExtensions == ["png"])
    await fixture.scanner.finish(1); try await regranted.value
}

@Test(arguments: [FolderSortKey.captureDate, .pixelDimensions])
@MainActor func issue124RestoredMetadataSortStartsOnDemandReads(key: FolderSortKey) async throws {
    let fixture = FolderScanFixture(), reader = Issue124MetadataReader()
    let preferences = InMemoryDisplayPreferencesStore()
    preferences.value.folderSort = key
    let scan = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
    let session = ViewerSession(preferencesStore: preferences)
    session.folderScan = scan
    let task = scan.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg"])
    await fixture.scanner.finish(); try await task.value
    for _ in 0..<100 where reader.requested.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    #expect(reader.requested == ["a.jpg"])
    #expect(scan.conditions.sort == key)
}

@Test @MainActor func issue124EndedScanReopensSameFolderWithFilter() async throws {
    let fixture = FolderScanFixture(), scan = fixture.coordinator
    let first = scan.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg", "b.png"])
    await fixture.scanner.finish(); try await first.value
    scan.setConditions(.init(selectedExtensions: ["png"]))
    scan.end() // App's single-image admission ends the current scan before opening its folder.
    let same = scan.begin(folder: fixture.folder, rootID: fixture.id, input: fixture.folder.appendingPathComponent("a.jpg"))
    await fixture.scanner.waitForStart(1)
    #expect(scan.conditions.selectedExtensions == ["png"])
    try await fixture.scanner.deliver(["a.jpg", "b.png"], at: 1)
    await fixture.scanner.finish(1); try await same.value
    #expect(scan.snapshot?.entries.map(\.url.lastPathComponent) == ["b.png"])
    scan.end()
    let other = scan.begin(folder: fixture.root.appendingPathComponent("B"), rootID: fixture.id)
    await fixture.scanner.waitForStart(2)
    #expect(scan.conditions.selectedExtensions == nil)
    await fixture.scanner.finish(2); try await other.value
}

@Test @MainActor func issue124ResolvedSymlinkFolderKeepsFilter() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let real = root.appendingPathComponent("real"), link = root.appendingPathComponent("link")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    let fixture = FolderScanFixture(), scan = fixture.coordinator
    let first = scan.begin(folder: real, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    await fixture.scanner.finish(); try await first.value
    scan.setConditions(.init(selectedExtensions: ["png"]))
    scan.end()
    let same = scan.begin(folder: link, rootID: fixture.id)
    await fixture.scanner.waitForStart(1)
    #expect(scan.conditions.selectedExtensions == ["png"])
    await fixture.scanner.finish(1); try await same.value
}

@Test @MainActor func issue124CorruptSortFieldsKeepOtherPreferences() throws {
    let json = #"{"alwaysShowTools":true,"filmstripExpanded":true,"appearance":"dark","gridSidebarWidth":240,"gridSidebarVisible":false,"folderSort":"unknown","folderSortDirection":42}"#
    let decoded = try JSONDecoder().decode(DisplayPreferences.self, from: Data(json.utf8))
    #expect(decoded.folderSort == .name && decoded.folderSortDirection == .ascending)
    #expect(decoded.alwaysShowTools && decoded.filmstripExpanded)
    #expect(decoded.appearance == .dark && decoded.gridSidebarWidth == 240 && !decoded.gridSidebarVisible)
}

@Test @MainActor func issue124CancelReadingRestoresFilterWithCurrentAppSort() async throws {
    let fixture = FolderScanFixture(), scan = fixture.coordinator
    let store = InMemoryDisplayPreferencesStore(), session = ViewerSession(preferencesStore: store)
    session.folderScan = scan
    let first = scan.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg", "b.png"])
    await fixture.scanner.finish(); try await first.value
    session.setFolderConditions(.init(selectedExtensions: ["png"]))
    session.beginFolderEntry(shownImage: nil, hasCompleteGrid: true)
    let reading = scan.begin(folder: fixture.root.appendingPathComponent("B"), rootID: fixture.id)
    await fixture.scanner.waitForStart(1)
    var changed = store.value
    changed.folderSort = .size; changed.folderSortDirection = .descending
    store.value = changed
    #expect(session.cancelFolderEntry() == .grid)
    #expect(scan.conditions == .init(sort: .size, direction: .descending, selectedExtensions: ["png"]))
    #expect(scan.snapshot?.entries.map(\.url.lastPathComponent) == ["b.png"])
    await fixture.scanner.finish(1); try await reading.value
}

@Test @MainActor func issue124SharedSortDoesNotReorderFrozenPreview() async throws {
    let fixture = FolderScanFixture(), scan = fixture.coordinator
    let store = InMemoryDisplayPreferencesStore(), session = ViewerSession(preferencesStore: store)
    session.folderScan = scan
    let task = scan.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg", "b.png"])
    await fixture.scanner.finish(); try await task.value
    let ids = try #require(scan.snapshot?.navigationEntries.map(\.itemID))
    session.beginBrowsing(items: ids, sourceVersion: .init(1), scrollAnchor: nil)
    session.select(ids[0])
    #expect(CommandRouter().route(.preview, from: .key, to: session))
    let frozen = scan.snapshot
    var changed = store.value
    changed.folderSort = .size
    store.value = changed
    #expect(scan.snapshot == frozen)
    #expect(scan.conditions.sort == .name)
}
