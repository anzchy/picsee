import Foundation
import Testing
import PicseeCore
import PicseeInfrastructure

@Test func identityScopeSharesRootResolverAcrossRequests() async throws {
    let file = fixture("coordinate-grid.png")
    let root = ItemIdentityRoot(id: AccessRootID(), url: file.deletingLastPathComponent())
    let pipeline = ImageIOPipeline()
    let first = try await pipeline.request(for: file, maximumPixelSize: 512, identityRoot: root)
    let second = try await pipeline.request(for: file, maximumPixelSize: 512, identityRoot: root)
    #expect(first.renderKey?.itemID == .rootRelative(rootID: root.id, relativePath: "coordinate-grid.png"))
    #expect(first.renderKey == second.renderKey)
    let image = try await pipeline.image(for: first)
    #expect(image.itemID == first.renderKey?.itemID)
    let grant = try await pipeline.request(for: file, maximumPixelSize: 512)
    #expect(grant.renderKey?.itemID != first.renderKey?.itemID)
}
