import AppKit
import SwiftUI
import Observation
import PicseeCore
import PicseeApplication

private struct StateText: View {
    let lines: [String]
    let isLoading: Bool
    let isFailure: Bool
    let isNotice: Bool
    private struct DropHint: NSViewRepresentable {
        let line: String
        func makeNSView(context: Context) -> NSTextField {
            let field = NSTextField(labelWithString: line)
            field.font = DesignMetrics.font("uiSmall")
            field.textColor = DesignColor.textSecondary.nsColor
            field.alignment = .center
            field.setAccessibilityIdentifier("state.drop-hint")
            field.setAccessibilityRole(.staticText)
            return field
        }
        func updateNSView(_ field: NSTextField, context: Context) {
            field.stringValue = line
            field.setAccessibilityLabel(line)
        }
    }
    var body: some View {
        VStack(spacing: 12) {
            if isLoading { IndeterminateProgressRow(label: lines[0]) }
            else {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if !isFailure && index == 2 {
                        DropHint(line: line).fixedSize().offset(y: 80)
                    } else {
                        Text(line).font(Font(DesignMetrics.font(isNotice ? "uiSmall" : index == 0 ? "title" : "ui")))
                            .foregroundStyle(isFailure && index == 2 ? DesignColor.errorText.color :
                                index == 0 ? DesignColor.textPrimary.color : DesignColor.textSecondary.color)
                    }
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
    public var onRetry: (() -> Void)?
    private weak var keyCanvas: NSView?
    private weak var keyChrome: ViewerChromeOverlay?
    private var displayedStatus: ViewerImageStatus?
    private var displayedNextEnabled = false
    public func linkKeyViews(to canvas: NSView, chrome: ViewerChromeOverlay) {
        keyCanvas = canvas; keyChrome = chrome
        ViewerStateFocus.link(canvas: canvas, state: self, chrome: chrome)
    }
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
        guard displayedStatus != status || displayedNextEnabled != nextEnabled else { return }
        displayedStatus = status; displayedNextEnabled = nextEnabled
        if let focused = window?.firstResponder as? NSView,
           buttons.contains(where: { focused === $0 || focused.isDescendant(of: $0) }), let keyCanvas {
            session?.updateFocus(.canvas)
            window?.makeFirstResponder(keyCanvas)
        }
        defer {
            if let keyCanvas, let keyChrome { ViewerStateFocus.link(canvas: keyCanvas, state: self, chrome: keyChrome) }
        }
        setAccessibilityChildren([])
        isHidden = status == .showing
        setAccessibilityHidden(isHidden)
        subviews.forEach {
            $0.isHidden = true; $0.setAccessibilityHidden(true); $0.nextKeyView = nil
            if let button = $0 as? NSButton { button.isEnabled = false; button.setAccessibilityEnabled(false) }
            $0.removeFromSuperview()
        }
        buttons = []; textLines = []; showsProgress = false
        var actions: [(String, String)] = []
        var failure = false
        let notice = status == .detailLimited
        switch status {
        case .empty:
            textLines = [String(localized: "Open a folder to start browsing"),
                         String(localized: "Images stay on your Mac. Browse by folder."),
                         String(localized: "You can also drop images or folders here.")]
            actions = [(String(localized: "Choose Folder…"), "state.open")]
        case .loading(let name):
            showsProgress = true
            textLines = [String(format: String(localized: "Opening %@…"), name)]
            actions = [(String(localized: "Cancel"), "state.cancel")]
        case .failed(let kind, let name):
            failure = true
            textLines = [String(localized: "Unable to read this image"), name,
                String(localized: String.LocalizationValue(kind.messageKey))]
            actions = [(String(localized: "Retry"), "state.retry")]
            if nextEnabled { actions.append((String(localized: "Next"), "state.next")) }
        case .detailLimited: textLines = [String(localized: "Showing reduced detail")]
        case .showing: return
        }
        let text = NSHostingView(rootView: StateText(lines: textLines, isLoading: showsProgress,
            isFailure: failure, isNotice: notice))
        let center = max(160, bounds.midY)
        text.frame = NSRect(x: 16, y: notice ? bounds.height - 84 : center,
            width: max(0, bounds.width - 32), height: notice ? 32 : failure ? 160 : 80)
        text.autoresizingMask = notice ? [.width, .minYMargin] : [.width, .minYMargin, .maxYMargin]
        addSubview(text)
        let width: CGFloat = actions.count > 1 ? 80 : 180
        let total = CGFloat(actions.count) * width + CGFloat(max(0, actions.count - 1)) * 12
        for (index, action) in actions.enumerated() {
            let button = ViewerStateButton(title: action.0, target: self, action: #selector(activate(_:)))
            button.session = session
            button.bezelStyle = .rounded; button.focusRingType = .exterior
            button.identifier = NSUserInterfaceItemIdentifier(action.1)
            button.setAccessibilityIdentifier(action.1)
            button.frame = NSRect(x: (bounds.width - total) / 2 + CGFloat(index) * (width + 12),
                y: center - 44, width: width, height: 32)
            button.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            addSubview(button); buttons.append(button)
        }
        setAccessibilityChildren([text as NSView] + buttons)
    }
    @objc private func activate(_ sender: NSButton) {
        guard !isHiddenOrHasHiddenAncestor, sender.isEnabled, !sender.isHiddenOrHasHiddenAncestor,
              buttons.contains(where: { $0 === sender }), let session else { return }
        switch sender.identifier?.rawValue {
        case "state.cancel": session.cancelImageOpening(); refresh()
        case "state.retry": onRetry?()
        case "state.next": CommandRouter().route(.next, from: .button, to: session)
        default: CommandRouter().route(.open, from: .button, to: session)
        }
    }
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHiddenOrHasHiddenAncestor else { return nil }
        let local = convert(point, from: superview)
        return buttons.first { !$0.isHidden && $0.frame.contains(local) }
    }
}
