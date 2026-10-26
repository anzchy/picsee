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
    public let searchButton: NSButton = GridSidebarToggleButton()
    public var emptyStateTitle: NSTextField? { emptyTitle }
    public var emptyStateDetail: NSTextField? { emptyDetail }
    public let sortButton: NSButton = GridSidebarToggleButton()
    public let searchStatus = NSTextField(labelWithString: "")
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
        footer.addSubview(searchButton)
        footer.addSubview(searchStatus)
        footer.addSubview(sortButton)
        footer.addSubview(footerRule)
        mainContent.addSubview(emptyState)
        emptyState.addSubview(emptyTitle)
        emptyState.addSubview(emptyIcon)
        emptyState.addSubview(emptyDetail)
        emptyState.addSubview(clearSearchButton)
        emptyState.isHidden = true
        emptyState.setAccessibilityIdentifier("grid.search.empty")
        emptyTitle.font = .systemFont(ofSize: 16, weight: .medium)
        emptyTitle.textColor = DesignColor.textPrimary.nsColor
        emptyIcon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        emptyIcon.contentTintColor = .secondaryLabelColor
        emptyDetail.textColor = DesignColor.textSecondary.nsColor
        emptyDetail.font = .systemFont(ofSize: 13)
        setEmptyDetailText(emptyDetail.stringValue)
        emptyDetail.lineBreakMode = .byTruncatingMiddle
        emptyTitle.alignment = .center
        emptyDetail.alignment = .center
        clearSearchButton.title = String(localized: "Clear Search")
        clearSearchButton.bezelStyle = .rounded
        clearSearchButton.isBordered = true
        clearSearchButton.bezelColor = DesignColor.primaryFill.nsColor
        clearSearchButton.target = self
        clearSearchButton.action = #selector(clearFromButton)
        clearSearchButton.setAccessibilityIdentifier("grid.search.clear")
        searchField.placeholderString = String(localized: "Search current folder")
        searchField.setAccessibilityLabel(String(localized: "Search current folder"))
        searchField.setAccessibilityIdentifier("grid.search.field")
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction)
        searchField.isHidden = true
        searchButton.isBordered = false
        searchButton.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchButton.target = self
        searchButton.action = #selector(openSearchFromButton)
        searchButton.setAccessibilityLabel(String(localized: "Search images"))
        searchButton.setAccessibilityIdentifier("grid.search.button")
        searchStatus.font = .systemFont(ofSize: 12)
        searchStatus.textColor = DesignColor.textSecondary.nsColor
        searchStatus.lineBreakMode = .byTruncatingTail
        searchStatus.isHidden = true
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
            footerRule.layer?.backgroundColor = DesignColor.divider.nsColor.cgColor
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
        // grid-light.html: 12pt trailing inset, 7pt only through 480pt;
        // toolbar gap 6pt, reduced to 2pt through 800pt.
        let trailingInset: CGFloat = footer.bounds.width <= 480 ? 7 : 12
        let toolGap: CGFloat = footer.bounds.width <= 800 ? 2 : 6
        sortButton.frame = NSRect(x: max(48, footer.bounds.width - trailingInset - 30), y: 6, width: 30, height: 28)
        searchButton.frame = NSRect(x: sortButton.frame.minX - 30 - toolGap, y: 6, width: 30, height: 28)
        let searchWidth = min(190, max(0, sortButton.frame.minX - 58))
        searchField.frame = NSRect(x: sortButton.frame.minX - searchWidth - toolGap, y: 6,
                                   width: searchWidth, height: 28)
        searchStatus.frame = NSRect(x: 48, y: 6, width: max(0, (searchField.isHidden ? searchButton.frame.minX : searchField.frame.minX) - 56), height: 28)
        emptyState.frame = mainContent.bounds
        let centerX = emptyState.bounds.midX
        let centerY = emptyState.bounds.midY
        // search-empty.html: centered flex column; h2 margin-top 18,
        // p margin-top 9 and line-height 1.7 × 13, actions margin-top 18.
        let titleGap: CGFloat = 18
        let detailGap: CGFloat = 9
        let actionGap: CGFloat = 18
        let iconHeight: CGFloat = 32
        let titleHeight: CGFloat = 25
        let detailHeight: CGFloat = 22.1
        let clearHeight: CGFloat = 30
        let groupHeight = iconHeight + titleGap + titleHeight + detailGap + detailHeight + actionGap + clearHeight
        let groupTop = centerY + groupHeight / 2
        emptyIcon.frame = NSRect(x: centerX - 16, y: groupTop - iconHeight, width: 32, height: iconHeight)
        let emptyWidth = min(360, max(0, emptyState.bounds.width - 48))
        emptyTitle.frame = NSRect(x: centerX - emptyWidth / 2,
                                  y: emptyIcon.frame.minY - titleGap - titleHeight,
                                  width: emptyWidth, height: titleHeight)
        emptyDetail.frame = NSRect(x: centerX - emptyWidth / 2,
                                   y: emptyTitle.frame.minY - detailGap - detailHeight,
                                   width: emptyWidth, height: detailHeight)
        clearSearchButton.frame = NSRect(x: max(0, centerX - 65),
                                         y: emptyDetail.frame.minY - actionGap - clearHeight,
                                         width: 130, height: clearHeight)
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
        let nextAction: NSView = footerActionsEnabled ? (searchField.isHidden ? searchButton : searchField) : focusAnchor
        toggleButton.nextKeyView = preferencesStore.value.gridSidebarVisible ? divider : nextAction
        divider.nextKeyView = nextAction
        searchButton.nextKeyView = sortButton
        searchField.nextKeyView = sortButton
        sortButton.nextKeyView = emptyState.isHidden ? focusAnchor : clearSearchButton
        clearSearchButton.nextKeyView = focusAnchor
    }
    public func focusSearch() {
        searchButton.isHidden = true
        searchField.isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateKeyViewLoop()
        window?.makeFirstResponder(searchField)
    }
    @objc private func openSearchFromButton() { focusSearch() }
    private func collapseSearch() {
        searchField.isHidden = true
        searchButton.isHidden = false
        searchButton.state = searchField.stringValue.isEmpty ? .off : .on
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateKeyViewLoop()
    }
    public func controlTextDidEndEditing(_ obj: Notification) { collapseSearch() }
    public func setFooterActionsEnabled(_ enabled: Bool) {
        footerActionsEnabled = enabled
        searchField.isEnabled = enabled
        searchButton.isEnabled = enabled
        sortButton.isEnabled = enabled
        emptyState.setAccessibilityHidden(!enabled || emptyState.isHidden)
        if !enabled { emptyState.isHidden = true }
        updateKeyViewLoop()
    }
    public func setSearchTerm(_ term: String) {
        searchField.stringValue = term
        searchButton.state = term.isEmpty ? .off : .on
        if term.isEmpty { searchStatus.isHidden = true }
    }
    public func setSearchStatus(resultCount: Int, term: String) {
        searchStatus.stringValue = term.isEmpty
            ? String(format: String(localized: "%lld images"), resultCount)
            : String(format: String(localized: "Search: %@ · %lld results"), term, resultCount)
        searchStatus.isHidden = false
        searchButton.state = term.isEmpty ? .off : .on
    }
    private func setEmptyDetailText(_ text: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = 22.1
        paragraph.maximumLineHeight = 22.1
        emptyDetail.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: DesignColor.textSecondary.nsColor,
            .paragraphStyle: paragraph,
        ])
    }
    public func showSearchEmpty(_ visible: Bool, term: String = "") {
        if visible { mainContent.addSubview(emptyState, positioned: .above, relativeTo: nil) }
        if visible { setEmptyDetailText(String(format: String(localized: "No images with “%@” in their filename."), term)) }
        emptyState.isHidden = !visible
        emptyState.setAccessibilityHidden(!visible || !footerActionsEnabled)
        updateKeyViewLoop()
    }
    public var searchEmptyVisible: Bool { !emptyState.isHidden }
    public func controlTextDidChange(_ obj: Notification) { onSearchChange?(searchField.stringValue) }
    public func searchFieldDidEndSearching(_ sender: NSSearchField) {
        if sender.stringValue.isEmpty { clearSearch() }
    }
    @objc func searchFieldAction() {
        if searchField.stringValue.isEmpty { clearSearch() }
        else { onSearchChange?(searchField.stringValue) }
    }
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchField, selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        clearSearch()
        return true
    }
    @objc private func clearFromButton() { clearSearch() }
    private func clearSearch() {
        searchField.stringValue = ""
        if !searchField.isHidden { window?.makeFirstResponder(searchButton) }
        collapseSearch()
        searchStatus.isHidden = true
        onSearchChange?("")
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
