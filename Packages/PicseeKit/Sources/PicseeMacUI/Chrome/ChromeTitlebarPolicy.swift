import AppKit

public final class ChromeDragStrip: NSView {
    public override var mouseDownCanMoveWindow: Bool { true }
}

public enum ChromeTitlebarPolicy {
    public static func apply(to window: NSWindow, visible: Bool, fullScreen: Bool) {
        // Restore native controls in full screen; the system controls their titlebar's reveal.
        let show = visible || fullScreen
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = !show
        }
        window.titleVisibility = show ? .visible : .hidden
    }
}
