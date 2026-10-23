import AppKit
import SwiftUI
import PicseeCore
import PicseeApplication

struct ChromeToolFace: View {
    let session: ViewerSession
    let id: CommandID
    @Environment(\.colorScheme) private var scheme
    var command: CommandID { id == .actualPixels && session.zoomMode == .actualPixels ? .fit : id }
    var customZoom: Double? { if case .custom(let value) = session.zoomMode { value } else { nil } }
    func activate() { CommandRouter().route(command, from: .button, to: session) }
    var body: some View {
        if id == .actualPixels {
            ScaleIndicator(actualPixels: session.zoomMode == .actualPixels, customZoom: customZoom, input: .live, action: activate)
                .disabled(!session.isEnabled(command))
        } else {
            IconCommandButton(symbol: Self.symbol(id), state: session.isEnabled(command) ? [] : .disabled,
                theme: scheme == .dark ? .dark : .light, input: .live, action: activate)
        }
    }
    static func symbol(_ id: CommandID) -> DesignSymbol {
        switch id {
        case .open: .folder
        case .inspector: .info
        case .previous: .previous
        case .next: .next
        case .zoomOut: .zoomOut
        default: .zoomIn
        }
    }
}

/// Native input/focus shell around the shared live design component.
public final class ChromeToolView: NSView {
    private var session: ViewerSession?
    private var id: CommandID = .open
    private var face: NSHostingView<ChromeToolFace>?
    public var command: CommandID { id == .actualPixels && session?.zoomMode == .actualPixels ? .fit : id }
    convenience init(frame: NSRect, session: ViewerSession, command: CommandID) {
        self.init(frame: frame)
        self.session = session; id = command
        let face = NSHostingView(rootView: ChromeToolFace(session: session, id: command))
        face.frame = bounds; face.autoresizingMask = [.width, .height]
        addSubview(face); self.face = face
        face.setAccessibilityHidden(true)
        focusRingType = .exterior
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityIdentifier("command.\(command.rawValue).button")
        setAccessibilityLabel(command == .actualPixels ? "Zoom mode" : ChromeToolFace.symbol(command).label)
        toolTip = command.shortcutHint
    }
    public override var acceptsFirstResponder: Bool { !isHiddenOrHasHiddenAncestor && session?.isEnabled(command) == true }
    public override func hitTest(_ point: NSPoint) -> NSView? {
        !isHiddenOrHasHiddenAncestor && frame.contains(point) ? self : nil
    }
    public override func becomeFirstResponder() -> Bool {
        guard acceptsFirstResponder else { return false }
        session?.updateFocus(.tools); needsDisplay = true
        return true
    }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    public override var focusRingMaskBounds: NSRect { bounds }
    public override func drawFocusRingMask() { bounds.fill() }
    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48: session?.tab(reverse: event.modifierFlags.contains(.shift))
        case 49: activate()
        case 53:
            if let session { CommandRouter().route(.escape, from: .key, to: session) }
        default: break
        }
    }
    public func activate() {
        face?.rootView.activate()
    }
    func refresh() {
        if let session { face?.rootView = ChromeToolFace(session: session, id: id) }
        setAccessibilityEnabled(session?.isEnabled(command) == true)
    }
}

public final class ViewerChromeOverlay: NSView {
    private var session: ViewerSession?
    public private(set) var tools: [ChromeToolView] = []
    public private(set) var groups: [NSView] = []
    public private(set) var filename: String?
    public private(set) var position: String?
    private let fileLabel = NSTextField(labelWithString: "")
    public convenience init(frame: NSRect, session: ViewerSession) {
        self.init(frame: frame)
        self.session = session
        let commands: [[CommandID]] = [[.open, .inspector], [.previous, .next], [.zoomOut, .actualPixels, .zoomIn]]
        let frames = [NSRect(x: 16, y: 16, width: 80, height: 40),
            NSRect(x: bounds.midX - 130, y: 16, width: 260, height: 40),
            NSRect(x: bounds.width - 222, y: 16, width: 206, height: 40)]
        let positions: [[CGFloat]] = [[8, 42], [8, 222], [8, 42, 168]]
        for index in 0..<3 {
            let group = NSView(frame: frames[index])
            group.autoresizingMask = index == 0 ? [.maxXMargin, .maxYMargin] : index == 1 ? [.minXMargin, .maxXMargin, .maxYMargin] : [.minXMargin, .maxYMargin]
            group.wantsLayer = true; group.layer?.cornerRadius = DesignMetrics.radii["popover"]!
            group.layer?.backgroundColor = DesignColor.sidebarBackground.nsColor.cgColor
            addSubview(group); groups.append(group)
            for (offset, command) in commands[index].enumerated() {
                let tool = ChromeToolView(frame: NSRect(x: positions[index][offset], y: 6,
                    width: command == .actualPixels ? 122 : 30, height: 28), session: session, command: command)
                group.addSubview(tool); tools.append(tool)
            }
        }
        fileLabel.frame = NSRect(x: 44, y: 11, width: 172, height: 18)
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.font = DesignMetrics.font("uiSmall")
        groups[1].addSubview(fileLabel)
        refresh()
    }
    public static let edgeBandHeight: CGFloat = 32
    public func pointerMoved(_ point: NSPoint) {
        let region: ChromePointerRegion = !bounds.contains(point) ? .outside : point.y < Self.edgeBandHeight ? .bottom : point.y >= bounds.height - Self.edgeBandHeight ? .top : .canvas
        session?.pointerMoved(in: region)
        for tool in tools { tool.toolTip = tool.command.shortcutHint }
    }
    public func focusTool(reverse: Bool, entering: Bool) -> Bool {
        let enabled = tools.filter(\.acceptsFirstResponder)
        let target: ChromeToolView?
        if entering { target = reverse ? enabled.last : enabled.first }
        else if let index = enabled.firstIndex(where: { $0 === window?.firstResponder }) {
            let next = index + (reverse ? -1 : 1)
            target = enabled.indices.contains(next) ? enabled[next] : nil
        } else { target = nil }
        guard let target else { return false }
        return window?.makeFirstResponder(target) == true
    }
    private weak var canvas: NSView?
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for group in groups.reversed() where !group.isHidden && group.frame.contains(local) {
            return group.hitTest(local)
        }
        return nil
    }
    public func setToolsVisible(_ visible: Bool) {
        for view in groups + tools { view.isHidden = !visible }
        setAccessibilityChildren(visible ? tools : [])
        if let canvas { linkKeyViews(to: canvas) }
    }
    public func linkKeyViews(to canvas: NSView) {
        self.canvas = canvas
        let enabled = tools.filter(\.acceptsFirstResponder)
        let loop: [NSView] = [canvas] + enabled
        for index in loop.indices { loop[index].nextKeyView = loop[(index + 1) % loop.count] }
    }
    public func refresh(filename: String? = nil, position: String? = nil) {
        self.filename = filename; self.position = position
        fileLabel.stringValue = [filename, position].compactMap { $0 }.joined(separator: " · ")
        for tool in tools { tool.refresh() }
        if let canvas { linkKeyViews(to: canvas) }
    }
}
