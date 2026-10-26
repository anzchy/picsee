import Testing
import PicseeCore

@Test func commandCatalog() {
    let expected: [(CommandID, String, Bool)] = [
        (.preview, " ", false), (.previous, "\u{f702}", false), (.next, "\u{f703}", false),
        (.escape, "\u{1b}", false), (.enter, "\r", false), (.fit, "0", false),
        (.actualPixels, "1", false), (.zoomIn, "+", false), (.zoomOut, "-", false),
        (.search, "f", true), (.open, "o", true), (.inspector, "i", true)
    ]
    let implemented: Set<CommandID> = [.preview, .enter, .previous, .next, .escape, .fit, .actualPixels, .zoomIn, .zoomOut, .search, .open, .inspector]
    #expect(CommandID.allCases.count == 12)
    #expect(Set(CommandID.allCases.map(\.rawValue)).count == 12)
    #expect(Set(CommandID.menuCommands) == implemented.subtracting([.search]))
    for (id, key, modifier) in expected {
        #expect(id.defaultKey == key)
        #expect(id.usesCommand == modifier)
        #expect(id.isImplemented == implemented.contains(id))
        #expect((id.shortcutHint != nil) == implemented.contains(id))
        #expect(CommandID.matching(key: key, command: modifier) == id)
        #expect(CommandID.matching(key: key, command: !modifier) == nil)
        #expect(CommandID.allCases.filter { $0.defaultKey == key && $0.usesCommand == modifier }.count == 1)
    }
    #expect(CommandID.fit.shortcutHint == "0")
    #expect(CommandID.open.shortcutHint == "⌘O")
    #expect(CommandID.matching(key: "=", command: false) == .zoomIn)
    #expect(CommandID.matching(key: "−", command: false) == .zoomOut)
    #expect(CommandID.matching(key: "z", command: false) == nil)
}
