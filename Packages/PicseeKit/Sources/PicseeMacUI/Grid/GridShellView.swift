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
    public let favoritesButton: NSButton = GridSidebarToggleButton()
    public let recentsButton: NSButton = GridSidebarToggleButton()
    public let infoButton: NSButton = GridSidebarToggleButton()
    public let displayButton: NSButton = GridSidebarToggleButton()
    public let searchStatus = NSTextField(labelWithString: "")
    public var onSearchChange: ((String) -> Void)?
    public var onClearSearch: (() -> Void)?
    public var onSort: ((FolderMenuAction) -> Void)?
    public var onSelectFolder: ((URL) -> Void)?
    public var onOpenSortMenu: ((NSButton, NSMenu) -> Void)?
    public var sortConditions: (() -> FolderViewConditions)?
    public var onMainFrameChange: ((NSRect) -> Void)?
    public var onOpenRecent: ((RecentFolder) -> Void)?
    public var onDropFolders: (([URL]) -> Void)?
    public weak var session: ViewerSession?
    public let emptyFolderView = EmptyFolderStateView()
    public var emptyFolderVisible: Bool { !isHidden && !emptyFolderView.isHidden }
    private var emptyFolderRequest: (recents: [RecentFolder], now: Date)?
    private var footerActionsRequested = true
    private var searchEmptyRequested = false
    private let preferencesStore: any DisplayPreferencesStore
    private let divider = GridSidebarDivider()
    private let folderName = NSTextField(labelWithString: "")
    public let folderTree = GridSidebarTreeView(frame: .zero)
    private let sidebarRule = NSView()
    private let footerRule = NSView()
    private let footerLeadingDivider = NSView()
    private let currentFileStatus = NSTextField(labelWithString: "")
    private var currentFileName = ""
    private var countText = ""
    private var isReading = false
    private let keyboardHint = NSView()
    private let spaceKeycap = NSTextField(labelWithString: "Space")
    private let quickLookLabel = NSTextField(labelWithString: "")
    private let emptyState = NSView()
    private let emptyIcon = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: String(localized: "No matching images"))
    private let emptyDetail = NSTextField(labelWithString: String(localized: "Try another filename or clear the search."))
    public let clearSearchButton: NSButton = GridSidebarToggleButton()
    private var lastMainFrame: NSRect?
    private var dragStartWidth: CGFloat?
    private var liveSidebarWidth: CGFloat?
    private weak var focusAnchor: NSView?
    private weak var focusTail: NSView?
    private var footerActionsEnabled = true
    private var preserveRestoredSearchEditor = false
    private var comingSoonEntries: [ObjectIdentifier: EntryPoint] = [:]

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
        footer.addSubview(infoButton)
        footer.addSubview(displayButton)
        footer.addSubview(footerRule)
        footer.addSubview(footerLeadingDivider)
        footer.addSubview(currentFileStatus)
        footer.addSubview(keyboardHint)
        keyboardHint.addSubview(spaceKeycap)
        keyboardHint.addSubview(quickLookLabel)
        sidebar.addSubview(favoritesButton)
        sidebar.addSubview(recentsButton)
        mainContent.addSubview(emptyState)
        mainContent.addSubview(emptyFolderView)
        emptyFolderView.isHidden = true
        emptyFolderView.onSelectSubfolder = { [weak self] in self?.onSelectFolder?($0) }
        emptyFolderView.onOpenRecent = { [weak self] in self?.onOpenRecent?($0) }
        emptyFolderView.onDropFolders = { [weak self] in self?.onDropFolders?($0) }
        emptyFolderView.onIncludeSubfolders = { [weak self] in self?.session?.setFolderRecursiveEnabled(true) }
        emptyFolderView.onChooseFolder = { [weak self] in
            if let session = self?.session { CommandRouter().route(.open, from: .button, to: session) }
        }
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
        searchStatus.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        searchStatus.textColor = DesignColor.textSecondary.nsColor
        searchStatus.lineBreakMode = .byTruncatingTail
        searchStatus.isHidden = true
        searchStatus.setAccessibilityIdentifier("grid.folder-count")
        currentFileStatus.font = .systemFont(ofSize: 12)
        currentFileStatus.textColor = DesignColor.textSecondary.nsColor
        currentFileStatus.lineBreakMode = .byTruncatingTail
        currentFileStatus.maximumNumberOfLines = 1
        currentFileStatus.isHidden = true
        currentFileStatus.setAccessibilityIdentifier("grid.current-file-status")
        footerLeadingDivider.setAccessibilityIdentifier("grid.footer.leading-divider")
        footerLeadingDivider.wantsLayer = true
        keyboardHint.setAccessibilityIdentifier("grid.keyboard-hint")
        spaceKeycap.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        spaceKeycap.textColor = DesignColor.textSecondary.nsColor
        spaceKeycap.alignment = .center
        spaceKeycap.wantsLayer = true
        spaceKeycap.layer?.cornerRadius = DesignMetrics.radii["inner"]!
        spaceKeycap.layer?.borderWidth = 1
        quickLookLabel.stringValue = String(localized: "Quick Look")
        quickLookLabel.font = .systemFont(ofSize: 12)
        quickLookLabel.textColor = DesignColor.textSecondary.nsColor
        sortButton.isBordered = false
        sortButton.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
        sortButton.target = self
        sortButton.action = #selector(showSortMenu)
        sortButton.toolTip = String(localized: "Sort images")
        sortButton.setAccessibilityLabel(String(localized: "Sort images"))
        sortButton.setAccessibilityIdentifier("grid.sort.button")
        configureComingSoon(favoritesButton, entry: .favorites, title: String(localized: "Personal Favorites"), identifier: "grid.favorites.row", systemImage: "heart")
        configureComingSoon(recentsButton, entry: .recents, title: String(localized: "Recently Viewed"), identifier: "grid.recents.row", systemImage: "clock")
        configureComingSoon(infoButton, entry: .footerInfo, title: String(localized: "Show Image Information"), identifier: "grid.info.button", systemImage: "info.circle", iconOnly: true)
        configureComingSoon(displayButton, entry: .footerDisplay, title: String(localized: "Display and Appearance"), identifier: "grid.display.button", systemImage: "square.grid.2x2", iconOnly: true)
        favoritesButton.alignment = .left
        recentsButton.alignment = .left
        sidebar.addSubview(folderName)
        sidebar.addSubview(folderTree)
        sidebar.addSubview(sidebarRule)
        sidebar.addSubview(divider)
        sidebarRule.setAccessibilityIdentifier("grid.sidebar.divider")
        sidebarRule.wantsLayer = true
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
        folderTree.isHidden = true
        folderTree.onSelectFolder = { [weak self] url in self?.onSelectFolder?(url) }
        toggleButton.bezelStyle = .texturedRounded
        toggleButton.isBordered = false
        toggleButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
        toggleButton.target = self
        toggleButton.action = #selector(toggleFromButton)
        toggleButton.setAccessibilityIdentifier("grid.sidebar.toggle")
        toggleButton.wantsLayer = true
        toggleButton.layer?.cornerRadius = DesignMetrics.radii["control"]!
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
            sidebarRule.layer?.backgroundColor = DesignColor.divider.nsColor.cgColor
            footer.layer?.backgroundColor = DesignColor.sidebarBackground.nsColor.cgColor
            footerRule.layer?.backgroundColor = DesignColor.divider.nsColor.cgColor
            footerLeadingDivider.layer?.backgroundColor = DesignColor.divider.nsColor.cgColor
            toggleButton.layer?.backgroundColor = preferencesStore.value.gridSidebarVisible
                ? DesignColor.hoverBackground.nsColor.cgColor : NSColor.clear.cgColor
            spaceKeycap.layer?.backgroundColor = DesignColor.popoverBackground.nsColor.cgColor
            spaceKeycap.layer?.borderColor = DesignColor.divider.nsColor.cgColor
        }
    }
    public func showFolder(_ name: String?) {
        folderTree.isHidden = true
        folderName.stringValue = name ?? ""
        folderName.isHidden = name == nil
        folderName.setAccessibilityLabel(name ?? "")
        refreshEmptyFolder()
    }
    public func showFolderTree(current: GridSidebarFolder, parent: GridSidebarFolder?, children: [GridSidebarFolder]) {
        folderName.isHidden = true
        folderTree.isHidden = false
        folderTree.show(current: current, parent: parent, children: children)
        refreshEmptyFolder()
    }
    /// Page 22 after a complete empty scan (ADR-014); its tiles follow the folder tree's current children.
    public func setEmptyFolderState(_ isEmpty: Bool, recents: [RecentFolder], now: Date) {
        emptyFolderRequest = isEmpty ? (recents, now) : nil
        refreshEmptyFolder()
    }
    /// Page 22 replacing the Reading State takes focus from the content it covers (the hidden collection view).
    private func focusAppearingEmptyFolder() {
        guard let window, !emptyFolderView.isHiddenOrHasHiddenAncestor, let first = emptyFolderView.keyViews.first
        else { return }
        let responder = window.firstResponder
        if responder === window || (responder as? NSView)?.isDescendant(of: mainContent) == true {
            window.makeFirstResponder(first)
        }
    }
    private weak var emptyFolderMirror: ViewerStateHost?
    /// Owner decision C (#137): the viewer's state host shows this same page 22, and its actions route as here.
    public func mirrorEmptyFolderPage(to host: ViewerStateHost) {
        emptyFolderMirror = host
        let mirror = host.emptyFolderView, source = emptyFolderView
        mirror.onSelectSubfolder = { [weak source] in source?.onSelectSubfolder?($0) }
        mirror.onOpenRecent = { [weak source] in source?.onOpenRecent?($0) }
        mirror.onDropFolders = { [weak source] in source?.onDropFolders?($0) }
        mirror.onIncludeSubfolders = { [weak source] in source?.onIncludeSubfolders?() }
        mirror.onChooseFolder = { [weak source] in source?.onChooseFolder?() }
        refreshEmptyFolder()
    }
    private func refreshEmptyFolder() {
        let subfolders = folderTree.isHidden ? [] : folderTree.children.map(\.url)
        let content = emptyFolderRequest.map {
            EmptyFolderContent.make(subfolders: subfolders, recents: $0.recents, now: $0.now,
                                    locale: .current, calendar: .current)
        }
        let appearing = emptyFolderView.isHidden && content != nil
        emptyFolderView.isHidden = content == nil
        var page: EmptyFolderPage?
        if let content {
            var rows: [EmptyFolderRecentRow] = []
            if case .recents(let recents) = content { rows = recents }
            let shown = EmptyFolderPage(subfolders: subfolders, recents: rows,
                                        includeSubfoldersAvailable: session?.folderRecursiveEnabled != true)
            mainContent.addSubview(emptyFolderView, positioned: .above, relativeTo: nil)
            emptyFolderView.frame = mainContent.bounds
            emptyFolderView.display(subfolders: shown.subfolders, recents: shown.recents,
                                    includeSubfoldersAvailable: shown.includeSubfoldersAvailable)
            page = shown
            if appearing { focusAppearingEmptyFolder() }
        }
        emptyFolderMirror?.setEmptyFolderPage(page)
        applyFooterState()
    }
    public func updateFolderCount(_ count: Int?, for url: URL) {
        folderTree.updateCount(count, for: url)
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
        let compactFooter = footer.bounds.width < 280
        let toggleWidth: CGFloat = compactFooter ? 16 : 30
        toggleButton.frame = NSRect(x: compactFooter ? 8 : 12, y: compactFooter ? 4 : 5,
                                    width: toggleWidth, height: compactFooter ? 32 : 30)
        footerRule.frame = NSRect(x: 0, y: 39, width: bounds.width, height: 1)
        footerLeadingDivider.frame = NSRect(x: 52, y: 10, width: 1, height: 20)
        // grid-light.html: 12pt trailing inset, 7pt only through 480pt;
        // toolbar gap 6pt, reduced to 2pt through 800pt.
        let trailingInset: CGFloat = footer.bounds.width <= 480 ? 7 : 12
        let toolGap: CGFloat = footer.bounds.width <= 800 ? 2 : 6
        let buttonWidth: CGFloat = footer.bounds.width <= 480 ? 26 : 30
        displayButton.frame = NSRect(x: footer.bounds.width - trailingInset - buttonWidth, y: 6,
                                     width: buttonWidth, height: 28)
        infoButton.frame = NSRect(x: displayButton.frame.minX - buttonWidth - toolGap, y: 6,
                                  width: buttonWidth, height: 28)
        sortButton.frame = NSRect(x: infoButton.frame.minX - buttonWidth - toolGap, y: 6,
                                  width: buttonWidth, height: 28)
        searchButton.frame = NSRect(x: sortButton.frame.minX - buttonWidth - toolGap, y: 6,
                                    width: buttonWidth, height: 28)
        let statusReserve: CGFloat = 48 + 60 + 8
        let searchWidth = min(190, max(120, sortButton.frame.minX - statusReserve - toolGap))
        searchField.frame = NSRect(x: sortButton.frame.minX - searchWidth - toolGap, y: 6,
                                   width: searchWidth, height: 28)
        keyboardHint.isHidden = !footerActionsEnabled || footer.bounds.width <= 800 || !searchField.isHidden
        keyboardHint.setAccessibilityHidden(keyboardHint.isHidden)
        let keycapWidth = spaceKeycap.intrinsicContentSize.width
        let quickLookWidth = quickLookLabel.intrinsicContentSize.width
        let hintWidth = keycapWidth + 5 + quickLookWidth
        keyboardHint.frame = NSRect(x: searchButton.frame.minX - 16 - hintWidth, y: 6,
                                    width: hintWidth, height: 28)
        spaceKeycap.frame = NSRect(x: 0, y: 5, width: keycapWidth, height: 18)
        quickLookLabel.frame = NSRect(x: keycapWidth + 5, y: 6, width: quickLookWidth, height: 18)
        searchStatus.isHidden = footer.bounds.width <= 480 || searchStatus.stringValue.isEmpty
        let statusRight = (keyboardHint.isHidden
            ? (searchField.isHidden ? searchButton.frame.minX : searchField.frame.minX)
            : keyboardHint.frame.minX) - 16
        // grid-light.html .grid-file-status: the name hugs its text up to 240/180/140/90px, the count follows
        // after a 12px (7px through 800px) gap at full width; both are centred in the 40pt bar.
        let countWidth = min(ceil(searchStatus.intrinsicContentSize.width), max(0, statusRight - 62))
        let countGap: CGFloat = footer.bounds.width <= 800 ? 7 : 12
        let fileMaxWidth: CGFloat = footer.bounds.width <= 480 ? 90
            : footer.bounds.width <= 720 ? 140 : footer.bounds.width <= 800 ? 180 : 240
        let fileWidth = min(fileMaxWidth, ceil(currentFileStatus.intrinsicContentSize.width),
                            max(0, statusRight - 62 - countWidth - countGap))
        let fileHeight = ceil(currentFileStatus.intrinsicContentSize.height)
        currentFileStatus.frame = NSRect(x: 62, y: ((footer.bounds.height - fileHeight) / 2).rounded(),
                                         width: fileWidth, height: fileHeight)
        let countHeight = ceil(searchStatus.intrinsicContentSize.height)
        searchStatus.frame = NSRect(x: currentFileStatus.frame.maxX + countGap,
                                    y: ((footer.bounds.height - countHeight) / 2).rounded(),
                                    width: countWidth, height: countHeight)
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
        favoritesButton.frame = NSRect(x: 12, y: max(0, sidebar.bounds.height - 54),
                                       width: max(0, sidebar.bounds.width - 24), height: 32)
        recentsButton.frame = NSRect(x: 12, y: max(0, favoritesButton.frame.minY - 35),
                                     width: max(0, sidebar.bounds.width - 24), height: 32)
        folderName.frame = NSRect(x: 14, y: max(0, recentsButton.frame.minY - 25),
                                  width: max(0, sidebar.bounds.width - 28), height: 20)
        folderTree.frame = NSRect(x: 0, y: 0, width: sidebar.bounds.width,
                                  height: max(0, recentsButton.frame.minY - 4))
        folderTree.viewportWidth = bounds.width
        sidebarRule.frame = NSRect(x: max(0, sidebar.bounds.width - 1), y: 0, width: 1,
                                   height: sidebar.bounds.height)
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
        focusTail = nil
        updateKeyViewLoop()
    }
    public func linkKeyViews(from first: NSView, through last: NSView) {
        focusAnchor = first
        focusTail = last
        updateKeyViewLoop()
    }
    private var footerKeyViews: [NSView] {
        var views: [NSView] = [toggleButton]
        if preferencesStore.value.gridSidebarVisible {
            views.append(divider)
            if !folderTree.isHidden { views.append(contentsOf: folderTree.rows) }
        }
        views.append(contentsOf: pageKeyViews)
        if footerActionsEnabled {
            views.append(searchField.isHidden ? searchButton : searchField)
            views.append(sortButton)
            if !emptyState.isHidden { views.append(clearSearchButton) }
        }
        return views
    }
    public var firstFooterKeyView: NSView { footerKeyViews[0] }
    public var lastFooterKeyView: NSView { footerKeyViews[footerKeyViews.count - 1] }
    public func adjacentFooterKeyView(to view: NSView, reverse: Bool) -> NSView? {
        let views = footerKeyViews
        guard let index = views.firstIndex(where: { $0 === view }) else { return nil }
        let next = index + (reverse ? -1 : 1)
        return views.indices.contains(next) ? views[next] : nil
    }
    private var pageKeyViews: [NSView] { emptyFolderView.isHidden ? [] : emptyFolderView.keyViews }
    private func updateKeyViewLoop() {
        guard let focusAnchor else { return }
        (focusTail ?? focusAnchor).nextKeyView = toggleButton
        let page = pageKeyViews
        let nextAction: NSView = footerActionsEnabled ? (searchField.isHidden ? searchButton : searchField)
            : page.first ?? focusAnchor
        for (index, view) in page.enumerated() {
            view.nextKeyView = page.indices.contains(index + 1) ? page[index + 1] : focusAnchor
        }
        let treeRows: [NSView] = preferencesStore.value.gridSidebarVisible && !folderTree.isHidden ? folderTree.rows : []
        toggleButton.nextKeyView = preferencesStore.value.gridSidebarVisible ? divider : nextAction
        divider.nextKeyView = treeRows.first ?? nextAction
        for (index, row) in treeRows.enumerated() {
            row.nextKeyView = treeRows.indices.contains(index + 1) ? treeRows[index + 1] : nextAction
        }
        searchButton.nextKeyView = sortButton
        searchField.nextKeyView = sortButton
        sortButton.nextKeyView = emptyState.isHidden ? focusAnchor : clearSearchButton
        clearSearchButton.nextKeyView = focusAnchor
    }
    /// Footer search is offered: not while reading, and not on page 22 (its search and sort are disabled).
    public var searchAvailable: Bool { footerActionsEnabled }
    public func focusSearch() {
        guard footerActionsEnabled else { return }
        searchButton.isHidden = true
        searchField.isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateKeyViewLoop()
        window?.makeFirstResponder(searchField)
    }
    public func preserveRestoredSearchEditorThroughMenuDispatch() {
        preserveRestoredSearchEditor = true
        DispatchQueue.main.async { [weak self] in self?.preserveRestoredSearchEditor = false }
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
    public func controlTextDidEndEditing(_ obj: Notification) {
        // A menu key equivalent can restore this editor before AppKit delivers its old end-editing callback.
        if preserveRestoredSearchEditor,
           window?.firstResponder === searchField || window?.firstResponder === searchField.currentEditor() {
            preserveRestoredSearchEditor = false
            return
        }
        preserveRestoredSearchEditor = false
        collapseSearch()
    }
    public func setFooterActionsEnabled(_ enabled: Bool) {
        footerActionsRequested = enabled
        if !enabled { searchEmptyRequested = false }
        applyFooterState()
    }
    /// Page 22 disables footer search and sort and hides page 23 until it leaves.
    private func applyFooterState() {
        let enabled = footerActionsRequested && emptyFolderView.isHidden
        footerActionsEnabled = enabled
        searchField.isEnabled = enabled
        searchButton.isEnabled = enabled
        sortButton.isEnabled = enabled
        emptyState.isHidden = !searchEmptyRequested || !emptyFolderView.isHidden
        emptyState.setAccessibilityHidden(!enabled || emptyState.isHidden)
        updateKeyViewLoop()
    }
    public func setSearchTerm(_ term: String) {
        searchField.stringValue = term
        searchButton.state = term.isEmpty ? .off : .on
        if term.isEmpty {
            countText = ""
            if !isReading {
                searchStatus.stringValue = ""
                searchStatus.isHidden = true
            }
        }
    }
    public func setCurrentFile(_ name: String) {
        currentFileName = name
        if !isReading {
            currentFileStatus.stringValue = name
            currentFileStatus.isHidden = name.isEmpty
        }
        needsLayout = true
    }
    /// folder-loading.html: the empty name slot `—`, then `Reading…` in the count's place.
    public func setReadingStatus(_ reading: Bool) {
        isReading = reading
        currentFileStatus.stringValue = reading ? "—" : currentFileName
        currentFileStatus.isHidden = !reading && currentFileName.isEmpty
        searchStatus.stringValue = reading ? String(localized: "Reading…") : countText
        searchStatus.isHidden = footer.bounds.width <= 480 || searchStatus.stringValue.isEmpty
        needsLayout = true
    }
    public func setSearchStatus(resultCount: Int, term: String) {
        countText = term.isEmpty
            ? String(format: String(localized: "%lld images"), resultCount)
            : String(format: String(localized: "Search: %@ · %lld results"), term, resultCount)
        if !isReading { searchStatus.stringValue = countText }
        searchStatus.isHidden = footer.bounds.width <= 480
        searchButton.state = term.isEmpty ? .off : .on
        needsLayout = true
    }
    private func setEmptyDetailText(_ text: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
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
        else { setEmptyDetailText(String(localized: "Try another filename or clear the search.")) }
        searchEmptyRequested = visible
        applyFooterState()
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
    public func entryPoint(for button: NSButton) -> EntryPoint? {
        comingSoonEntries[ObjectIdentifier(button)]
    }
    private func configureComingSoon(_ button: NSButton, entry: EntryPoint, title: String, identifier: String,
                                     systemImage: String, iconOnly: Bool = false) {
        let label = "\(title) · \(entry.accessibilityLabel(for: .preferred))"
        comingSoonEntries[ObjectIdentifier(button)] = entry
        button.title = iconOnly ? "" : title
        button.font = .systemFont(ofSize: 12)
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        button.imagePosition = iconOnly ? .imageOnly : .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.isEnabled = entry.isEnabled
        button.refusesFirstResponder = !entry.isFocusable
        button.keyEquivalent = entry.keyEquivalent ?? ""
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier(identifier)
    }
    private func refreshToggleLabel() {
        let label = String(localized: preferencesStore.value.gridSidebarVisible ? "Hide sidebar" : "Show sidebar")
        toggleButton.toolTip = label
        toggleButton.setAccessibilityLabel(label)
        toggleButton.state = preferencesStore.value.gridSidebarVisible ? .on : .off
        refreshAppearance()
    }
}
