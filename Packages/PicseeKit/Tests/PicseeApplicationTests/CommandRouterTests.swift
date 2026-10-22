import Testing
import PicseeCore
import PicseeApplication

@MainActor private final class FakeWindow: WindowCommandTarget {
    var hasImage = true
    var zoom = 1
    var inspector = false
    func isEnabled(_ command: CommandID) -> Bool { hasImage || command == .inspector }
    func perform(_ command: CommandID) {
        if command == .zoomIn { zoom += 1 }
        if command == .inspector { inspector.toggle() }
    }
}

@Test @MainActor func commandRouting() {
    let router = CommandRouter()
    let first = FakeWindow()
    let second = FakeWindow()
    for entry in CommandEntry.allCases {
        first.zoom = 1
        #expect(router.route(.zoomIn, from: entry, focus: .canvas, to: first))
        #expect(first.zoom == 2)
        #expect(second.zoom == 1)
        first.hasImage = false
        #expect(!router.route(.zoomIn, from: entry, focus: .canvas, to: first))
        #expect(first.zoom == 2)
        first.hasImage = true
        #expect(!router.route(.preview, from: entry, focus: .canvas, to: first))
    }
    #expect(router.route(.zoomIn, from: .key, focus: .canvas, to: second))
    #expect(second.zoom == 2)
    #expect(first.zoom == 2)
    for id: CommandID in [.preview, .previous, .next, .enter, .fit, .actualPixels, .zoomIn, .zoomOut] {
        #expect(!router.route(id, from: .key, focus: .textInput, to: first))
    }
    #expect(first.zoom == 2)
    #expect(router.route(.inspector, from: .key, focus: .textInput, to: first))
    #expect(first.inspector)
    #expect(router.route(.zoomIn, from: .button, focus: .textInput, to: first))
    #expect(first.zoom == 3)
    #expect(router.route(.zoomIn, from: .menu, focus: .panel, to: first))
    #expect(first.zoom == 4)
    #expect(!router.route(.escape, from: .key, focus: .panel, menuTracking: true, to: first))
    #expect(!router.route(.zoomIn, from: .key, focus: .canvas, menuTracking: true, to: first))
    #expect(first.zoom == 4)
    #expect(router.route(.escape, from: .key, focus: .panel, to: first))
}
