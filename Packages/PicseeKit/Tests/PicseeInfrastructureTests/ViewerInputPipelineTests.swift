import Foundation
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure

@MainActor @Test func inputAdmissionRealFixtureProbeKinds() async throws {
    let scope = CountingScope()
    let store = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: store) }
    let access = try FileAccess(scope: scope, bookmarks: FakeBookmarks(), store: BookmarkStore(url: store), buildSHA: "input-test")
    let pipeline = ImageIOPipeline(), intent = AccessIntent()
    let admission = ViewerInputAdmission(access: access, pipeline: pipeline, maximumPixelSize: 64, rootCovering: { _ in nil })
    for name in ["not-an-image.jpg", "unsupported-container.zip"] {
        let url = fixture(name), bytes = try Data(contentsOf: url)
        #expect(await admission.probe(url, operation: intent.begin()) == .unsupported)
        await #expect(performing: {
            try await pipeline.request(for: url, maximumPixelSize: 64)
        }, throws: loadError(.unsupportedFormat))
        #expect(try Data(contentsOf: url) == bytes)
    }
    for name in ["corrupt.png", "truncated.png"] {
        let url = fixture(name)
        #expect(await admission.probe(url, operation: intent.begin()) == .open(.fileGrant(url)))
        do {
            let request = try await pipeline.request(for: url, maximumPixelSize: 64)
            await #expect(performing: { try await pipeline.image(for: request) }, throws: loadError(.corruptImage))
            print("inputFixture \(name) header=success decode=corruptImage")
        } catch {
            #expect((error as? ImageLoadError)?.kind == .corruptImage)
            print("inputFixture \(name) header=corruptImage")
        }
    }
    let valid = fixture("alpha-gradient.png")
    #expect(await admission.probe(valid, operation: intent.begin()) == .open(.fileGrant(valid)))
    let request = try await pipeline.request(for: valid, maximumPixelSize: 64)
    #expect(request.renderKey != nil)
    #expect(request.identityRoot == nil)
    #expect(scope.counts == [5, 5])
    #expect(await access.records().isEmpty == true)
}
