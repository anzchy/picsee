import PicseeCore

/// The Inspector's Escape command takes precedence over grid-only text input handling.
public enum InspectorEscapePolicy {
    public static func handlesEscape(inspectorVisible: Bool, menuTracking: Bool,
                                     focus: FocusContext, keyCode: UInt16) -> Bool {
        keyCode == 53 && inspectorVisible && !menuTracking && focus != .canvas
    }
}
