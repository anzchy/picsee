import AppKit
import PicseeApplication

@MainActor private final class GridSidebarDivider: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var startX: CGFloat = 0
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
    override func mouseDown(with event: NSEvent) { startX = event.locationInWindow.x }
    override func mouseDragged(with event: NSEvent) {
        let delta = event.locationInWindow.x - startX
        startX = event.locationInWindow.x
        onDrag?(delta)
    }
}

/// Page 11/12/24/29 frame shared by the grid and folder-reading state.
@MainActor public final class GridShellView: NSView {
    public let mainContent = NSView()
    public let sidebar = NSView()
    public let footer = NSView()
    public let toggleButton = NSButton()
    public var onMainFrameChange: ((NSRect) -> Void)?
    private let preferencesStore: any DisplayPreferencesStore
    private let divider = GridSidebarDivider()
    private let folderName = NSTextField(labelWithString: "")
    private let footerRule = NSView()
    private var lastMainFrame: NSRect?

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
        divider.onDrag = { [weak self] delta in
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
        let sidebarWidth = visible ? min(320, max(160, CGFloat(preferencesStore.value.gridSidebarWidth))) : 0
        return NSRect(x: sidebarWidth, y: 40, width: max(0, bounds.width - sidebarWidth),
                      height: max(0, bounds.height - 40))
    }
    public override func layout() {
        super.layout()
        let main = mainFrame
        sidebar.isHidden = !preferencesStore.value.gridSidebarVisible
        sidebar.frame = NSRect(x: 0, y: 40, width: main.minX, height: main.height)
        mainContent.frame = main
        footer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 40)
        toggleButton.frame = NSRect(x: 8, y: 4, width: 32, height: 32)
        footerRule.frame = NSRect(x: 0, y: 39, width: bounds.width, height: 1)
        folderName.frame = NSRect(x: 14, y: max(0, sidebar.bounds.height - 53),
                                  width: max(0, sidebar.bounds.width - 28), height: 20)
        divider.frame = NSRect(x: max(0, sidebar.bounds.width - 5), y: 0, width: 5,
                               height: sidebar.bounds.height)
        if lastMainFrame != main {
            lastMainFrame = main
            onMainFrameChange?(main)
        }
    }
    @objc private func toggleFromButton() { toggleSidebar() }
    public func toggleSidebar() {
        var value = preferencesStore.value
        value.gridSidebarVisible.toggle()
        preferencesStore.value = value
        refreshToggleLabel()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    public func resizeSidebar(to width: CGFloat) {
        guard width.isFinite else { return }
        var value = preferencesStore.value
        value.gridSidebarWidth = Double(min(320, max(160, width)))
        preferencesStore.value = value
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    private func refreshToggleLabel() {
        let label = String(localized: preferencesStore.value.gridSidebarVisible ? "Hide sidebar" : "Show sidebar")
        toggleButton.toolTip = label
        toggleButton.setAccessibilityLabel(label)
    }
}
