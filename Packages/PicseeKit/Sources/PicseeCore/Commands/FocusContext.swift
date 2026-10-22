public enum FocusContext: Sendable {
    case canvas, panel, textInput
}

public enum CommandEntry: CaseIterable, Sendable {
    case menu, button, key
}
