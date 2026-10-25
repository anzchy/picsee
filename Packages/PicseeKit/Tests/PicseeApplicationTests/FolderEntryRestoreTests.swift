import Foundation
import Testing
import PicseeCore
@testable import PicseeApplication

@Test @MainActor func cancelReadingTargetsFolderNavigatedViewerImageOnce() async throws {
    let fixture = FolderScanFixture(), host = FolderNavigationHost()
    let session = ViewerSession(host: host)
    session.folderScan = fixture.coordinator; fixture.coordinator.host = host
    let a = fixture.folder.appendingPathComponent("a.png"), b = fixture.folder.appendingPathComponent("b.png")
    let task = fixture.coordinator.begin(folder: fixture.folder, rootID: fixture.id, input: a)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.png", "b.png", "c.png"])
    await fixture.scanner.finish(); try await task.value
    #expect(fixture.coordinator.move(.next))
    #expect(host.visible == b)
    #expect(session.cancelFolderEntry() == nil)

    session.beginFolderEntry(shownImage: b, hasCompleteGrid: false)
    session.enterFolderGrid(items: [], sourceVersion: .init(0))
    let reading = fixture.coordinator.begin(folder: fixture.root.appendingPathComponent("B"), rootID: fixture.id)
    await fixture.scanner.waitForStart(1)
    session.beginFolderEntry(shownImage: nil, hasCompleteGrid: false)
    #expect(session.cancelFolderEntry() == .viewer(b))
    #expect(session.mode == .viewing)
    #expect(!fixture.coordinator.isReadingFolder)
    #expect(session.cancelFolderEntry() == nil)
    await fixture.scanner.finish(1); try await reading.value

    session.beginFolderEntry(shownImage: nil, hasCompleteGrid: false)
    session.completeFolderEntry()
    #expect(session.cancelFolderEntry() == nil)
    session.beginFolderEntry(shownImage: nil, hasCompleteGrid: false)
    #expect(session.cancelFolderEntry() == .empty)
}
