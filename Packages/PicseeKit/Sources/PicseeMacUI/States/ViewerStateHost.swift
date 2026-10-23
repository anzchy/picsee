import AppKit
import SwiftUI
import Observation
import PicseeCore
import PicseeApplication

private struct StateText: View {
    let lines: [String]
    let isLoading: Bool
    var body: some View {
        VStack(spacing: 12) {
            if isLoading { IndeterminateProgressRow(label: lines.first ?? "") }
            else {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line).font(Font(DesignMetrics.font(index == 0 ? "title" : "ui")))
                        .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Native state surface; decisions arrive as Application-owned image status.
public final class ViewerStateHost: NSView {
    public private(set) var buttons: [NSButton] = []
    public private(set) var textLines: [String] = []
    public private(set) var showsProgress = false
    private var session: ViewerSession?
    private var tracking = false

    public convenience init(frame: NSRect, session: ViewerSession) {
        self.init(frame: frame)
        self.session = session
        refresh()
    }
    public func refresh() {
        guard let session else { return }
        if !tracking {
            tracking = true
            withObservationTracking {
                display(session.imageStatus, nextEnabled: session.isEnabled(.next))
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in self?.tracking = false; self?.refresh() }
            }
        } else { display(session.imageStatus, nextEnabled: session.isEnabled(.next)) }
    }
    public func display(_ status: ViewerImageStatus, nextEnabled: Bool = false) {
        subviews.forEach { $0.removeFromSuperview() }
        buttons = []; textLines = []; showsProgress = false
        switch status {
        case .empty:
            textLines = [String(localized: "Open a folder to start browsing"),
                         String(localized: "Images stay on your Mac. Browse by folder.")]
        case .loading(let name):
            showsProgress = true
            textLines = [String(format: String(localized: "Opening %@…"), name)]
        default: return
        }
        let text = NSHostingView(rootView: StateText(lines: textLines, isLoading: showsProgress))
        let center = max(160, bounds.midY)
        text.frame = NSRect(x: 16, y: center, width: max(0, bounds.width - 32), height: 80)
        text.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        addSubview(text)
        let title = showsProgress ? String(localized: "Cancel") : String(localized: "Choose Folder…")
        let button = NSButton(title: title, target: self, action: #selector(activate(_:)))
        button.bezelStyle = .rounded
        button.focusRingType = .exterior
        let id = showsProgress ? "state.cancel" : "state.open"
        button.identifier = NSUserInterfaceItemIdentifier(id)
        button.setAccessibilityIdentifier(id)
        button.frame = NSRect(x: bounds.midX - 90, y: center - 44, width: 180, height: 32)
        button.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(button); buttons = [button]
    }
    @objc private func activate(_ sender: NSButton) {
        guard let session else { return }
        if sender.identifier?.rawValue == "state.cancel" { session.cancelImageOpening(); refresh() }
        else { CommandRouter().route(.open, from: .button, to: session) }
    }
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return buttons.first { !$0.isHidden && $0.frame.contains(local) }
    }
}
