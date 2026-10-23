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

@MainActor private final class AccessNavigationTarget: WindowCommandTarget {
    var commands: [CommandID] = []
    func isEnabled(_ command: CommandID) -> Bool { true }
    func perform(_ command: CommandID) { commands.append(command) }
}

@Test @MainActor func accessArrowCommandsRouteFromAllEntriesAndRespectTextInput() {
    let target = AccessNavigationTarget()
    for entry in CommandEntry.allCases {
        #expect(CommandRouter().route(.next, from: entry, focus: .canvas, to: target))
        #expect(CommandRouter().route(.previous, from: entry, focus: .panel, to: target))
    }
    #expect(target.commands == [.next, .previous, .next, .previous, .next, .previous])
    #expect(!CommandRouter().route(.next, from: .key, focus: .textInput, to: target))
    #expect(!CommandRouter().route(.previous, from: .key, focus: .canvas, menuTracking: true, to: target))
    #expect(CommandID.menuCommands.contains(.next) && CommandID.menuCommands.contains(.previous))
    #expect(CommandID.next.shortcutHint != nil && CommandID.previous.shortcutHint != nil)
}

@Test func accessNavigationMatchesCanonicalFileRepresentations() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    let first = base.appendingPathComponent("a space.jpg")
    let second = base.appendingPathComponent("b.jpg")
    try Data().write(to: first)
    let alias = base.appendingPathComponent("alias.jpg")
    try fm.createSymbolicLink(at: alias, withDestinationURL: first)
    let navigation = FolderNavigation(images: [first, second])
    #expect(navigation.step(from: alias, direction: .next, covered: true) == .move(second))
    let directoryHint = URL(fileURLWithPath: first.path, isDirectory: true)
    #expect(navigation.step(from: directoryHint, direction: .next, covered: true) == .move(second))
    let escaped = try #require(URL(string: first.absoluteString.replacingOccurrences(of: "a%20", with: "%61%20")))
    #expect(navigation.step(from: escaped, direction: .next, covered: true) == .move(second))
}
