import AppKit

/// Preserve panel focus when the pre-session open path requests canvas focus.
final class CommandWindow: NSWindow {
    var preserveResponder: ((NSResponder?) -> Bool)?
    var didChangeResponder: (() -> Void)?
    var consumeKey: ((NSEvent) -> Bool)?
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if preserveResponder?(responder) == true { return false }
        let accepted = super.makeFirstResponder(responder)
        if accepted { didChangeResponder?() }
        return accepted
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, consumeKey?(event) == true { return }
        super.sendEvent(event)
    }
}
