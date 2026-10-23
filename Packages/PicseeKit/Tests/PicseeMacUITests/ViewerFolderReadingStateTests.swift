import AppKit
import Testing
import PicseeCore
@testable import PicseeApplication
@testable import PicseeMacUI

private actor FolderReadingNativeLeases: AccessLeasing {
    var acquired = 0
    var released = 0
    func acquire(_ request: AccessRequest) -> AccessLease {
        acquired += 1
        return AccessLease(url: URL(fileURLWithPath: "/native-folder"), rootID: nil)
    }
    func release(_ lease: AccessLease) { released += 1 }
    var balance: [Int] { [acquired, released] }
}
private actor FolderReadingNativeScanner: FolderScanning {
    private var ending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func scan(in folder: URL, root: ItemIdentityRoot,
        emit: @Sendable ([FolderEntry]) async throws -> Void) async {
        await withCheckedContinuation {
            ending = $0; waiter?.resume(); waiter = nil
        }
    }
    func waitForStart() async {
        if ending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish() { ending?.resume(); ending = nil }
}

@Test @MainActor func viewerFolderReadingStateRendersAndCancels() async throws {
    let scene = StatesScene(), leases = FolderReadingNativeLeases(), scanner = FolderReadingNativeScanner()
    defer { scene.window.close() }
    let coordinator = FolderScanCoordinator(access: leases, scanner: scanner)
    defer { coordinator.cancel(); Task { await scanner.finish() } }
    scene.session.folderScan = coordinator
    let task = coordinator.begin(folder: URL(fileURLWithPath: "/native-folder/A"), rootID: AccessRootID())
    await scanner.waitForStart()
    scene.state.refresh(); scene.state.linkKeyViews(to: scene.canvas, chrome: scene.chrome)
    #expect(scene.session.imageStatus == .readingFolder)
    #expect(scene.state.showsProgress)
    #expect(scene.state.textLines == ["Reading Folder…", "Looking for images to browse. Please wait."])
    #expect(scene.state.buttons.map { $0.identifier?.rawValue } == ["state.cancel-folder"])
    let title = scene.state.subviews.first { $0.accessibilityIdentifier() == "state.folder-title" }
    let subtitle = scene.state.subviews.compactMap { $0 as? NSTextField }.first
    #expect(title?.accessibilityLabel() == "Reading Folder…")
    #expect(subtitle?.stringValue == "Looking for images to browse. Please wait.")
    let children = scene.state.accessibilityChildren() ?? []
    #expect(children.count == 3)
    let cancel = try #require(scene.state.buttons.first)
    #expect(cancel.title == "Cancel Reading")
    #expect(cancel.acceptsFirstResponder && scene.canvas.nextKeyView === cancel)
    cancel.performClick(nil); scene.state.refresh()
    #expect(scene.session.imageStatus == .empty)
    #expect(!scene.state.showsProgress)
    #expect(scene.state.buttons.first?.identifier?.rawValue == "state.open")
    #expect(await leases.balance == [1, 0])
    await scanner.finish(); try await task.value
    #expect(await leases.balance == [1, 1])
}

@Test func viewerFolderReadingLocalizationExactValues() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/Localizable.xcstrings"))
    let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(catalog["strings"] as? [String: Any])
    for (key, chinese) in [("Reading Folder…", "正在读取文件夹…"),
        ("Looking for images to browse. Please wait.", "正在查找可浏览的图片，请稍候。"), ("Cancel Reading", "取消读取")] {
        let entry = strings[key] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]
        for (language, expected) in [("en", key), ("zh-Hans", chinese)] {
            let localized = localizations?[language] as? [String: Any]
            let unit = localized?["stringUnit"] as? [String: Any]
            #expect(unit?["value"] as? String == expected)
        }
    }
}
