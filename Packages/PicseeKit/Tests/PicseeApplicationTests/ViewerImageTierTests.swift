import Foundation
import Testing
import PicseeCore
@testable import PicseeApplication

@MainActor @Test func loadTiersPreviewViewportGrowThenSourceWithoutDowngrade() async {
    let session = ViewerSession(), host = LoadHost(), pipeline = LoadPipeline(), access = LoadLeases()
    session.imageLoader.host = host
    let url = URL(fileURLWithPath: "/tiers.png")
    session.openImage(url, maximumPixelSize: 1000) {
        try await AccessImageSource.open(.fileGrant(url), access: access, pipeline: pipeline)
    }
    await session.imageLoader.loadTask?.value
    #expect(await pipeline.edges == [512, 1000])
    session.requireImageResolution(1500)
    #expect(session.imageLoader.phase == .refining)
    #expect(host.images.last?.image.width == 1000)
    await session.imageLoader.loadTask?.value
    #expect(await pipeline.edges == [512, 1000, 1500])
    session.requireImageResolution(4000)
    await session.imageLoader.loadTask?.value
    #expect(await pipeline.edges == [512, 1000, 1500, 4000])
    session.requireImageResolution(1000)
    await session.imageLoader.loadTask?.value
    #expect(await pipeline.edges == [512, 1000, 1500, 4000])
    #expect(host.images.last?.image.width == 4000)
    #expect(session.imageLoader.phase == .settled)
}
