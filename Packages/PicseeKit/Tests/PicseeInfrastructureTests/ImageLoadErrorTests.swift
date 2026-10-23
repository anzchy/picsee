import Foundation
import Testing
import PicseeCore
import PicseeInfrastructure

@Test func loadErrorsClassifyRealInputs() async throws {
    let text = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
    try Data("This is not an image".utf8).write(to: text)
    defer { try? FileManager.default.removeItem(at: text) }
    for (url, kind) in [(text, ImageLoadError.Kind.unsupportedFormat),
                        (fixture("truncated.png"), .corruptImage), (fixture("corrupt.png"), .corruptImage),
                        (fixture("oversize-header.png"), .resourceLimit)] {
        do {
            _ = try await ImageIOPipeline().image(for: ImageDecodeRequest(fileURL: url, maximumPixelSize: 512))
            Issue.record("Expected a typed failure")
        } catch {
            let failure = try #require(error as? ImageLoadError)
            #expect(failure.kind == kind)
            #expect(failure.revision?.byteCount == (try Data(contentsOf: url)).count)
        }
    }
}

@Test func loadErrorsCarryKnownIdentityAndRevision() async throws {
    let item = ItemID.ephemeral(UUID())
    let revision = FileRevision(byteCount: 123, modificationDate: nil)
    let key = RenderKey(itemID: item, revision: revision, maximumPixelSize: 128)
    do {
        _ = try await ImageIOPipeline().image(for: ImageDecodeRequest(fileURL: fixture("orientation-1.tiff"), maximumPixelSize: 128, renderKey: key))
        Issue.record("Expected changed source")
    } catch {
        let failure = try #require(error as? ImageLoadError)
        #expect(failure.kind == .sourceChanged)
        #expect(failure.itemID == item)
        #expect(failure.revision != nil)
    }
    for kind in ImageLoadError.Kind.allCases {
        let failure = ImageLoadError(kind, itemID: item, revision: revision)
        #expect(failure.kind == kind)
        #expect(failure.itemID == item)
        #expect(failure.revision == revision)
    }
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await ImageIOPipeline().request(for: fixture("orientation-1.tiff"), maximumPixelSize: 128)
    }
    do { _ = try await task.value; Issue.record("Expected cancellation") }
    catch { #expect((error as? ImageLoadError)?.kind == .cancelled) }
}

func loadError(_ kind: ImageLoadError.Kind) -> @Sendable (any Error) -> Bool {
    { ($0 as? ImageLoadError)?.kind == kind }
}

@Test func loadErrorsRejectPNGWithoutEndChunk() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: file) }
    // Complete IHDR, no image data or IEND. Independently truncate at PNG's first chunk boundary.
    try Data(contentsOf: fixture("alpha-gradient.png")).prefix(33).write(to: file)
    await #expect(performing: {
        try await ImageIOPipeline().image(for: ImageDecodeRequest(fileURL: file, maximumPixelSize: 128))
    }, throws: loadError(.corruptImage))
}
