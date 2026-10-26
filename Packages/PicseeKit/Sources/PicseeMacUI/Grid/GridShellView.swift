import AppKit
import PicseeApplication
import PicseeCore

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
@MainActor public final class GridShellView: NSView, NSSearchFieldDelegate {
    public let mainContent = NSView()
    public let sidebar = NSView()
    public let footer = NSView()
    public let toggleButton: NSButton = GridSidebarToggleButton()
    public let searchField = NSSearchField()
    public let sortButton: NSButton = GridSidebarToggleButton()
    public var onSearchChange: ((String) -> Void)?
    public var onClearSearch: (() -> Void)?
    public var onSort: ((FolderMenuAction) -> Void)?
    public var onOpenSortMenu: ((NSButton, NSMenu) -> Void)?
    public var sortConditions: (() -> FolderViewConditions)?
    public var onMainFrameChange: ((NSRect) -> Void)?
    private let preferencesStore: any DisplayPreferencesStore
    private let divider = GridSidebarDivider()
    private let folderName = NSTextField(labelWithString: "")
    private let footerRule = NSView()
    private let emptyState = NSView()
    private let emptyIcon = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: String(localized: "No matching images"))
    private let emptyDetail = NSTextField(labelWithString: String(localized: "Try another filename or clear the search."))
    public let clearSearchButton: NSButton = GridSidebarToggleButton()
    private var lastMainFrame: NSRect?
    private var dragStartWidth: CGFloat?
    private var liveSidebarWidth: CGFloat?
    private weak var focusAnchor: NSView?
    private var footerActionsEnabled = true

    public init(frame: NSRect, preferencesStore: any DisplayPreferencesStore) {
        self.preferencesStore = preferencesStore
        super.init(frame: frame)
        addSubview(sidebar)
        addSubview(mainContent)
        addSubview(footer)
        footer.addSubview(toggleButton)
        footer.addSubview(searchField)
        footer.addSubview(sortButton)
        footer.addSubview(footerRule)
        mainContent.addSubview(emptyState)
        emptyState.addSubview(emptyTitle)
        emptyState.addSubview(emptyIcon)
        emptyState.addSubview(emptyDetail)
        emptyState.addSubview(clearSearchButton)
        emptyState.isHidden = true
        emptyState.setAccessibilityIdentifier("grid.search.empty")
        emptyTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        emptyIcon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        emptyIcon.contentTintColor = .secondaryLabelColor
        emptyDetail.textColor = .secondaryLabelColor
        emptyTitle.alignment = .center
        emptyDetail.alignment = .center
        clearSearchButton.title = String(localized: "Clear Search")
        clearSearchButton.target = self
        clearSearchButton.action = #selector(clearFromButton)
        clearSearchButton.setAccessibilityIdentifier("grid.search.clear")
        searchField.placeholderString = String(localized: "Search current folder")
        searchField.setAccessibilityLabel(String(localized: "Search current folder"))
        searchField.setAccessibilityIdentifier("grid.search.field")
        searchField.delegate = self
        sortButton.isBordered = false
        sortButton.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
        sortButton.target = self
        sortButton.action = #selector(showSortMenu)
        sortButton.toolTip = String(localized: "Sort images")
        sortButton.setAccessibilityLabel(String(localized: "Sort images"))
        sortButton.setAccessibilityIdentifier("grid.sort.button")
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
        sortButton.frame = NSRect(x: max(48, footer.bounds.width - 40), y: 4, width: 32, height: 32)
        let searchWidth = min(190, max(0, sortButton.frame.minX - 56))
        searchField.frame = NSRect(x: sortButton.frame.minX - searchWidth - 8, y: 6,
                                   width: searchWidth, height: 28)
        emptyState.frame = mainContent.bounds
        let centerX = emptyState.bounds.midX
        let centerY = emptyState.bounds.midY
        emptyIcon.frame = NSRect(x: centerX - 16, y: centerY + 56, width: 32, height: 32)
        emptyTitle.frame = NSRect(x: max(0, centerX - 180), y: centerY + 20, width: 360, height: 25)
        emptyDetail.frame = NSRect(x: max(0, centerX - 180), y: centerY - 12, width: 360, height: 20)
        clearSearchButton.frame = NSRect(x: max(0, centerX - 65), y: centerY - 56, width: 130, height: 30)
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
        let nextAction: NSView = footerActionsEnabled ? searchField : focusAnchor
        toggleButton.nextKeyView = preferencesStore.value.gridSidebarVisible ? divider : nextAction
        divider.nextKeyView = nextAction
        searchField.nextKeyView = sortButton
        sortButton.nextKeyView = emptyState.isHidden ? focusAnchor : clearSearchButton
        clearSearchButton.nextKeyView = focusAnchor
    }
    public func focusSearch() { window?.makeFirstResponder(searchField) }
    public func setFooterActionsEnabled(_ enabled: Bool) {
        footerActionsEnabled = enabled
        searchField.isEnabled = enabled
        sortButton.isEnabled = enabled
        updateKeyViewLoop()
    }
    public func setSearchTerm(_ term: String) { searchField.stringValue = term }
    public func showSearchEmpty(_ visible: Bool, term: String = "") {
        if visible { mainContent.addSubview(emptyState, positioned: .above, relativeTo: nil) }
        if visible { emptyDetail.stringValue = String(format: String(localized: "No images with “%@” in their filename."), term) }
        emptyState.isHidden = !visible
        updateKeyViewLoop()
    }
    public var searchEmptyVisible: Bool { !emptyState.isHidden }
    public func controlTextDidChange(_ obj: Notification) { onSearchChange?(searchField.stringValue) }
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchField, selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        clearSearch()
        return true
    }
    @objc private func clearFromButton() { clearSearch() }
    private func clearSearch() {
        searchField.stringValue = ""
        onClearSearch?()
    }
    @objc private func showSortMenu() {
        onOpenSortMenu?(sortButton, makeSortMenu())
    }
    public func makeSortMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Sort By"))
        for key in FolderSortKey.allCases { addSortItem(.sort(key), to: menu) }
        menu.addItem(.separator())
        for direction in FolderSortDirection.allCases { addSortItem(.direction(direction), to: menu) }
        return menu
    }
    private func addSortItem(_ action: FolderMenuAction, to menu: NSMenu) {
        let item = menu.addItem(withTitle: String(localized: String.LocalizationValue(action.titleKey)),
                                action: #selector(selectSort(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
        item.setAccessibilityIdentifier(action.accessibilityIdentifier)
        if let conditions = sortConditions?() {
            switch action {
            case .sort(let key): item.state = conditions.sort == key ? .on : .off
            case .direction(let direction): item.state = conditions.direction == direction ? .on : .off
            default: break
            }
        }
    }
    @objc private func selectSort(_ item: NSMenuItem) {
        guard let action = item.representedObject as? FolderMenuAction else { return }
        onSort?(action)
    }
    private func refreshToggleLabel() {
        let label = String(localized: preferencesStore.value.gridSidebarVisible ? "Hide sidebar" : "Show sidebar")
        toggleButton.toolTip = label
        toggleButton.setAccessibilityLabel(label)
    }
}
