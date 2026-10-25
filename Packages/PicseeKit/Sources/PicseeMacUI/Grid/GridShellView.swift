import AppKit
import PicseeApplication

@MainActor private final class GridSidebarToggleButton: NSButton {
    override var acceptsFirstResponder: Bool { !isHiddenOrHasHiddenAncestor && isEnabled }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }
}

@MainActor private final class GridSidebarDivider: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onFinish: (() -> Void)?
    var onAdjust: ((CGFloat) -> Void)?
    private var startX: CGFloat = 0
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
    override func mouseDown(with event: NSEvent) { startX = event.locationInWindow.x }
    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.locationInWindow.x - startX)
    }
    override func mouseUp(with event: NSEvent) { onFinish?() }
    override var acceptsFirstResponder: Bool { !isHiddenOrHasHiddenAncestor }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onAdjust?(-8)
        case 124: onAdjust?(8)
        default: super.keyDown(with: event)
        }
    }
    override func accessibilityPerformIncrement() -> Bool { onAdjust?(8); return true }
    override func accessibilityPerformDecrement() -> Bool { onAdjust?(-8); return true }
}

/// Page 11/12/24/29 frame shared by the grid and folder-reading state.
@MainActor public final class GridShellView: NSView {
    public let mainContent = NSView()
    public let sidebar = NSView()
    public let footer = NSView()
    public let toggleButton: NSButton = GridSidebarToggleButton()
    public var onMainFrameChange: ((NSRect) -> Void)?
    private let preferencesStore: any DisplayPreferencesStore
    private let divider = GridSidebarDivider()
    private let folderName = NSTextField(labelWithString: "")
    private let footerRule = NSView()
    private var lastMainFrame: NSRect?
    private var dragStartWidth: CGFloat?
    private var liveSidebarWidth: CGFloat?
    private weak var focusAnchor: NSView?

    public init(frame: NSRect, preferencesStore: any DisplayPreferencesStore) {
        self.preferencesStore = preferencesStore
        super.init(frame: frame)
        addSubview(sidebar)
        addSubview(mainContent)
        addSubview(footer)
        footer.addSubview(toggleButton)
        footer.addSubview(footerRule)
        sidebar.addSubview(folderName)
        sidebar.addSubview(divider)
        sidebar.setAccessibilityIdentifier("grid.sidebar")
        footer.setAccessibilityIdentifier("grid.footer")
        mainContent.setAccessibilityIdentifier("grid.main")
        divider.setAccessibilityIdentifier("grid.sidebar.resize")
        divider.setAccessibilityElement(true)
        divider.setAccessibilityRole(.splitter)
        divider.setAccessibilityLabel(String(localized: "Resize sidebar"))
        divider.setAccessibilityMinValue(NSNumber(value: 160))
        divider.setAccessibilityMaxValue(NSNumber(value: 320))
        divider.onDrag = { [weak self] totalOffset in
            guard let self else { return }
            let start = dragStartWidth ?? CGFloat(preferencesStore.value.gridSidebarWidth)
            dragStartWidth = start
            setLiveSidebarWidth(start + totalOffset)
        }
        divider.onFinish = { [weak self] in self?.finishSidebarDrag() }
        divider.onAdjust = { [weak self] delta in
            guard let self else { return }
            resizeSidebar(to: CGFloat(preferencesStore.value.gridSidebarWidth) + delta)
        }
        folderName.lineBreakMode = .byTruncatingTail
        folderName.maximumNumberOfLines = 1
        folderName.isHidden = true
        folderName.font = .systemFont(ofSize: 12, weight: .medium)
        folderName.setAccessibilityIdentifier("grid.sidebar.folder")
        toggleButton.bezelStyle = .texturedRounded
        toggleButton.isBordered = false
        toggleButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
        toggleButton.target = self
        toggleButton.action = #selector(toggleFromButton)
        toggleButton.setAccessibilityIdentifier("grid.sidebar.toggle")
        wantsLayer = true
        sidebar.wantsLayer = true
        footer.wantsLayer = true
        footerRule.wantsLayer = true
        refreshAppearance()
        refreshToggleLabel()
        needsLayout = true
    }
    public required init?(coder: NSCoder) { nil }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            sidebar.layer?.backgroundColor = DesignColor.sidebarBackground.nsColor.cgColor
            footer.layer?.backgroundColor = DesignColor.sidebarBackground.nsColor.cgColor
            footerRule.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }
    public func showFolder(_ name: String?) {
        folderName.stringValue = name ?? ""
        folderName.isHidden = name == nil
        folderName.setAccessibilityLabel(name ?? "")
    }
    public var mainFrame: NSRect {
        let visible = preferencesStore.value.gridSidebarVisible
        let sidebarWidth = visible ? (liveSidebarWidth ?? CGFloat(preferencesStore.value.gridSidebarWidth)) : 0
        return NSRect(x: sidebarWidth, y: 40, width: max(0, bounds.width - sidebarWidth),
                      height: max(0, bounds.height - 40))
    }
    public override func layout() {
        super.layout()
        let main = mainFrame
        sidebar.isHidden = !preferencesStore.value.gridSidebarVisible
        sidebar.frame = NSRect(x: 0, y: 40, width: main.minX, height: main.height)
        mainContent.frame = main
        for content in mainContent.subviews { content.frame = mainContent.bounds }
        footer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 40)
        toggleButton.frame = NSRect(x: 8, y: 4, width: 32, height: 32)
        footerRule.frame = NSRect(x: 0, y: 39, width: bounds.width, height: 1)
        folderName.frame = NSRect(x: 14, y: max(0, sidebar.bounds.height - 53),
                                  width: max(0, sidebar.bounds.width - 28), height: 20)
        divider.frame = NSRect(x: max(0, sidebar.bounds.width - 5), y: 0, width: 5,
                               height: sidebar.bounds.height)
        divider.setAccessibilityValue(NSNumber(value: Double(main.minX)))
        if lastMainFrame != main {
            lastMainFrame = main
            onMainFrameChange?(main)
        }
    }
    @objc private func toggleFromButton() { toggleSidebar() }
    public func toggleSidebar() {
        var value = preferencesStore.value
        if value.gridSidebarVisible && window?.firstResponder === divider { window?.makeFirstResponder(toggleButton) }
        value.gridSidebarVisible.toggle()
        preferencesStore.value = value
        refreshToggleLabel()
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateKeyViewLoop()
    }
    public func resizeSidebar(to width: CGFloat) {
        guard width.isFinite else { return }
        var value = preferencesStore.value
        value.gridSidebarWidth = Double(min(320, max(160, width)))
        preferencesStore.value = value
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    private func setLiveSidebarWidth(_ width: CGFloat) {
        guard width.isFinite else { return }
        liveSidebarWidth = min(320, max(160, width))
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    private func finishSidebarDrag() {
        defer { dragStartWidth = nil; liveSidebarWidth = nil }
        if let liveSidebarWidth { resizeSidebar(to: liveSidebarWidth) }
    }
    public func linkKeyViews(from anchor: NSView) {
        focusAnchor = anchor
        updateKeyViewLoop()
    }
    private func updateKeyViewLoop() {
        guard let focusAnchor else { return }
        focusAnchor.nextKeyView = toggleButton
        toggleButton.nextKeyView = preferencesStore.value.gridSidebarVisible ? divider : focusAnchor
        divider.nextKeyView = focusAnchor
    }
    private func refreshToggleLabel() {
        let label = String(localized: preferencesStore.value.gridSidebarVisible ? "Hide sidebar" : "Show sidebar")
        toggleButton.toolTip = label
        toggleButton.setAccessibilityLabel(label)
    }
}
