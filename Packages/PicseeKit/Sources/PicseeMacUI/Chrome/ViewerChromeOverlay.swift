import AppKit
import SwiftUI
import PicseeCore
import PicseeApplication

struct ChromeToolFace: View {
    let session: ViewerSession
    let id: CommandID
    let enabled: Bool
    let state: ComponentState
    init(session: ViewerSession, id: CommandID, interaction: ComponentState = []) {
        self.session = session; self.id = id; enabled = session.isEnabled(id)
        state = interaction.union(enabled ? [] : .disabled)
    }
    @Environment(\.colorScheme) private var scheme
    var command: CommandID { id == .actualPixels && session.zoomMode == .actualPixels ? .fit : id }
    var customZoom: Double? { if case .custom(let value) = session.zoomMode { value } else { nil } }
    func activate() { CommandRouter().route(command, from: .button, to: session) }
    var body: some View {
        if id == .actualPixels {
            ScaleIndicator(actualPixels: session.zoomMode == .actualPixels, customZoom: customZoom, state: state, theme: scheme == .dark ? .dark : .light, input: .live, action: activate)
                .disabled(!enabled)
        } else {
            IconCommandButton(symbol: Self.symbol(id), state: state,
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
        setAccessibilityChildren([])
        focusRingType = .exterior
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityIdentifier("command.\(command.rawValue).button")
        setAccessibilityLabel(command == .open ? String(localized: "Open…") : command == .actualPixels ? String(localized: "Zoom mode") : String(localized: String.LocalizationValue(ChromeToolFace.symbol(command).label)))
        toolTip = commandTooltip
    }
    var commandTooltip: String {
        let label = command == .open ? "Open…" : command == .fit ? "Fit window" : command == .actualPixels ? "Actual Pixels" : ChromeToolFace.symbol(command).label
        let hint = command == .previous ? "←" : command == .next ? "→" : command.shortcutHint ?? ""
        return String(localized: String.LocalizationValue(label)) + " (\(hint))"
    }
    public override var acceptsFirstResponder: Bool { !isHiddenOrHasHiddenAncestor && session?.isEnabled(command) == true }
    public override func hitTest(_ point: NSPoint) -> NSView? {
        !isHiddenOrHasHiddenAncestor && frame.contains(point) ? self : nil
    }
    weak var pointerCanvas: NSView?
    private var pressed = false
    private var focused = false
    public override var mouseDownCanMoveWindow: Bool { false }
    public override func mouseDown(with event: NSEvent) {
        guard acceptsFirstResponder else { return }
        pressed = true; refresh()
        session?.setChromeInteraction(.pointerPress, active: true)
    }
    public override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        pressed = false; refresh()
        if bounds.contains(convert(event.locationInWindow, from: nil)) { activate() }
        session?.setChromeInteraction(.pointerPress, active: false)
        if window?.firstResponder === self, let pointerCanvas {
            window?.makeFirstResponder(pointerCanvas)
            session?.updateFocus(.canvas)
        }
    }
    public override func becomeFirstResponder() -> Bool {
        guard acceptsFirstResponder else { return false }
        focused = true; refresh()
        session?.updateFocus(.tools); needsDisplay = true
        return true
    }
    public override func resignFirstResponder() -> Bool { focused = false; refresh(); needsDisplay = true; return true }
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
    public override func accessibilityPerformPress() -> Bool {
        guard acceptsFirstResponder else { return false }
        activate()
        return true
    }
    public func activate() {
        face?.rootView.activate()
    }
    func refresh() {
        toolTip = commandTooltip
        if let session { face?.rootView = ChromeToolFace(session: session, id: id,
            interaction: ComponentInput.live.state([], focused: focused, pressed: pressed)) }
        setAccessibilityEnabled(session?.isEnabled(command) == true)
        if id == .actualPixels, let session {
            setAccessibilityValue(ScaleIndicator(actualPixels: session.zoomMode == .actualPixels,
                customZoom: face?.rootView.customZoom, action: {}).label)
        }
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
            group.wantsLayer = true; group.layer?.cornerRadius = DesignMetrics.radii["popover"]!
            addSubview(group); groups.append(group)
            for (offset, command) in commands[index].enumerated() {
                let tool = ChromeToolView(frame: NSRect(x: positions[index][offset], y: 6,
                    width: command == .actualPixels ? 122 : 30, height: 28), session: session, command: command)
                group.addSubview(tool); tools.append(tool)
            }
        }
        fileLabel.frame = NSRect(x: 44, y: 11, width: 172, height: 18)
        fileLabel.setAccessibilityElement(true); fileLabel.setAccessibilityRole(.staticText)
        fileLabel.setAccessibilityIdentifier("chrome.filename")
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.font = DesignMetrics.font("uiSmall")
        groups[1].addSubview(fileLabel)
        arrangeGroups()
        updateGroupColors()
        refresh()
    }
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGroupColors()
    }
    private func updateGroupColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for group in groups { group.layer?.backgroundColor = DesignColor.sidebarBackground.nsColor.cgColor }
        }
    }
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        arrangeGroups()
    }
    private func arrangeGroups() {
        guard groups.count == 3 else { return }
        // Keep command hit areas intact; narrow windows wrap groups above one another.
        let width = min(260, bounds.width - 32)
        let singleRow = bounds.width >= 610
        groups[0].frame = NSRect(x: 16, y: bounds.width < 334 ? 112 : 16, width: 80, height: 40)
        groups[2].frame = NSRect(x: bounds.width - 222, y: 16, width: 206, height: 40)
        groups[1].frame = NSRect(x: singleRow ? min(bounds.midX - 130, bounds.width - 238 - width) : (bounds.width - width) / 2,
            y: singleRow ? 16 : 64, width: width, height: 40)
        tools[3].setFrameOrigin(NSPoint(x: width - 38, y: 6))
        fileLabel.frame = NSRect(x: 44, y: 11, width: width - 88, height: 18)
    }
    public static let edgeBandHeight: CGFloat = 32
    public func pointerMoved(_ point: NSPoint) {
        let region: ChromePointerRegion = !bounds.contains(point) ? .outside : point.y < Self.edgeBandHeight ? .bottom : point.y >= bounds.height - Self.edgeBandHeight ? .top : .canvas
        session?.pointerMoved(in: region)
        session?.setChromeInteraction(.pointerHover, active: groups.contains { !$0.isHidden && $0.frame.contains(point) })
        for tool in tools { tool.toolTip = tool.commandTooltip }
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
        updateAccessibilityChildren(visible: visible)
        if let canvas { linkKeyViews(to: canvas) }
    }
    private func updateAccessibilityChildren(visible: Bool) {
        setAccessibilityChildren(visible ? tools + (filename == nil ? [] : [fileLabel]) : [])
    }
    public func linkKeyViews(to canvas: NSView) {
        self.canvas = canvas
        for tool in tools { tool.pointerCanvas = canvas }
        let enabled = tools.filter(\.acceptsFirstResponder)
        let loop: [NSView] = [canvas] + enabled
        for index in loop.indices { loop[index].nextKeyView = loop[(index + 1) % loop.count] }
    }
    public func refresh(filename: String? = nil, position: String? = nil) {
        self.filename = filename; self.position = position
        fileLabel.stringValue = [filename, position].compactMap { $0 }.joined(separator: " · ")
        fileLabel.setAccessibilityValue(filename ?? "")
        for tool in tools { tool.refresh() }
        updateAccessibilityChildren(visible: groups.first?.isHidden == false)
        if let canvas { linkKeyViews(to: canvas) }
    }
}
