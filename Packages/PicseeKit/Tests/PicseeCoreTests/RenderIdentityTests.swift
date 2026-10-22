import Foundation
import Testing
import PicseeCore

@Test func installationRequiresIdentityRevisionGenerationAndBinding() {
    let item = ItemID(rawValue: UUID())
    let revision = FileRevision(byteCount: 42, modificationDate: Date(timeIntervalSince1970: 100))
    let key = RenderKey(itemID: item, revision: revision, maximumPixelSize: 512)
    let token = PresentationToken(binding: UUID(), generation: UUID())
    #expect(token.accepts(key: key, expected: key, token: token))
    #expect(!token.accepts(key: key, expected: RenderKey(itemID: ItemID(rawValue: UUID()), revision: revision, maximumPixelSize: 512), token: token))
    for changed in [FileRevision(byteCount: 43, modificationDate: revision.modificationDate), FileRevision(byteCount: 42, modificationDate: nil)] {
        #expect(!token.accepts(key: key, expected: RenderKey(itemID: item, revision: changed, maximumPixelSize: 512), token: token))
    }
    #expect(!token.accepts(key: key, expected: key, token: PresentationToken(binding: UUID(), generation: token.generation)))
    #expect(!token.accepts(key: key, expected: key, token: PresentationToken(binding: token.binding, generation: UUID())))
}
