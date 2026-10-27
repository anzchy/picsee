import Foundation
import AppKit
import Testing
import PicseeCore
@testable import PicseeApplication
@testable import PicseeInfrastructure

@Test @MainActor func issue140RenameKeepsCurrentIdentityAndReplacementChangesRevision() async throws {
    let f = try WatchFixture(folders: ["root/F"]); defer { f.remove() }
    let root = f.url("root"), folder = f.url("root/F")
    let old = f.url("root/F/a.png"), renamed = f.url("root/F/z.png")
    do {
    let renamed = URL(fileURLWithPath: renamed.path.hasPrefix("/var/") ? "/private" + renamed.path : renamed.path)
    try Data(repeating: 1, count: 20).write(to: old)
    let rootID = try await f.access.grant(folder: root)
    let scanner = FolderBrowser()
    let coordinator = FolderScanCoordinator(access: f.access, scanner: scanner, watcher: f.hub)
    try await coordinator.begin(folder: folder, rootID: rootID).value
    let original = try #require(coordinator.currentItemID)
    try FileManager.default.moveItem(at: old, to: renamed)
    try await #require(coordinator.refresh()).value
    #expect(coordinator.currentItemID == original)
    #expect(coordinator.currentURL == renamed)

    try issue140PNG(red: 80).write(to: renamed)
    let pipeline = ImageIOPipeline()
    let rootIdentity = ItemIdentityRoot(id: rootID, url: root)
    let first = try await pipeline.request(for: renamed, maximumPixelSize: 64, identityRoot: rootIdentity)
    let before = try #require(first.renderKey)
    #expect(before.itemID == original)
    let replacement = f.url("root/F/new.png")
    try Data(repeating: 2, count: 20).write(to: replacement)
    try FileManager.default.removeItem(at: renamed)
    try FileManager.default.moveItem(at: replacement, to: renamed)
    try issue140PNG(red: 180).write(to: renamed)
    if let date = before.revision.modificationDate {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: renamed.path)
    }
    let after = try #require((try await pipeline.request(for: renamed, maximumPixelSize: 64,
        identityRoot: rootIdentity)).renderKey)
    #expect(after.itemID == before.itemID)
    #expect(after.revision != before.revision)
    let presentationBeforeRefresh = coordinator.presentationRevision
    try await #require(coordinator.refresh()).value
    #expect(coordinator.sourceSnapshot?.entries.first?.url == renamed)
    #expect(coordinator.presentationRevision > presentationBeforeRefresh)
    coordinator.end()
    }
}

private func issue140PNG(red: UInt8) throws -> Data {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32))
    bitmap.setColor(NSColor(srgbRed: CGFloat(red) / 255, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
    return try #require(bitmap.representation(using: .png, properties: [:]))
}
