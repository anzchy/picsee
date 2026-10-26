/// Frozen base commands. Raw values are stable identifiers, independent of UI titles.
public enum CommandID: String, CaseIterable, Sendable {
    case preview, previous, next, escape, enter, fit, actualPixels, zoomIn, zoomOut, search, open, inspector

    public var defaultKey: String {
        switch self {
        case .preview: " "
        case .previous: "\u{f702}"
        case .next: "\u{f703}"
        case .escape: "\u{1b}"
        case .enter: "\r"
        case .fit: "0"
        case .actualPixels: "1"
        case .zoomIn: "+"
        case .zoomOut: "-"
        case .search: "f"
        case .open: "o"
        case .inspector: "i"
        }
    }
    public var usesCommand: Bool { [.search, .open, .inspector].contains(self) }
    public var isImplemented: Bool { [.preview, .enter, .previous, .next, .escape, .fit, .actualPixels, .zoomIn, .zoomOut, .search, .open, .inspector].contains(self) }
    public var shortcutHint: String? { isImplemented ? (usesCommand ? "⌘" + defaultKey.uppercased() : defaultKey) : nil }
    public static var menuCommands: [Self] { allCases.filter { $0.isImplemented && $0 != .search } }
    public static func matching(key: String, command: Bool) -> Self? {
        let normalized = key == "=" ? "+" : (key == "−" ? "-" : key)
        return allCases.first { $0.defaultKey == normalized && $0.usesCommand == command }
    }
}
