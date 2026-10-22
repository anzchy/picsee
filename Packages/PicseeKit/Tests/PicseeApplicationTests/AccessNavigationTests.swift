import Foundation
import Testing
import PicseeCore
import PicseeApplication

@Test func accessNavigationAsksForGrantAndStepsInFinderOrderWithoutWrapping() {
    let folder = URL(fileURLWithPath: "/photos")
    let a = folder.appendingPathComponent("image1.jpg")
    let b = folder.appendingPathComponent("image2.jpg")
    let c = folder.appendingPathComponent("image10.jpg")
    let navigation = FolderNavigation(images: [c, a, b])
    #expect(navigation.images == [a, b, c])
    #expect(navigation.step(from: a, direction: .next, covered: false) == .needsGrant(folder))
    #expect(navigation.step(from: b, direction: .previous, covered: false) == .needsGrant(folder))
    #expect(navigation.step(from: a, direction: .next, covered: true) == .move(b))
    #expect(navigation.step(from: c, direction: .previous, covered: true) == .move(b))
    #expect(navigation.step(from: a, direction: .previous, covered: true) == .end)
    #expect(navigation.step(from: c, direction: .next, covered: true) == .end)
    #expect(navigation.step(from: folder.appendingPathComponent("missing.jpg"), direction: .next, covered: true) == .end)
    #expect(FolderNavigation(images: []).step(from: a, direction: .next, covered: true) == .end)
}
