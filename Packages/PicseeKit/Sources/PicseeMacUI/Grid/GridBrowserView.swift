import AppKit
import PicseeCore

@MainActor private final class GridPhotoSurface: NSView {
    var onAppearanceChange: (() -> Void)?
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

/// A reused grid item contains only display data supplied by an authorized snapshot.
@MainActor public final class GridPhotoItem: NSCollectionViewItem {
    public private(set) var representedItemID: ItemID?
    public private(set) var filename = ""
    public private(set) var thumbnailToken = UUID()
    public private(set) var thumbnailGeneration: UInt64 = 0
    public private(set) var thumbnailPixelEdge = 0
    private let tile = NSView()
    private let currentRing = CALayer()
    private let selectionOutline = CALayer()
    private let placeholder = NSTextField(labelWithString: String(localized: "Thumbnail pending"))
    private let nameLabel = NSTextField(labelWithString: "")

    public override func loadView() {
        let surface = GridPhotoSurface(frame: NSRect(x: 0, y: 0, width: 220, height: 184))
        surface.onAppearanceChange = { [weak self] in self?.updateSelection() }
        surface.onLayout = { [weak self] in self?.layoutContent() }
        surface.wantsLayer = true
        // Page 11 `.thumbnail-wrap`: a quiet surface tile with the inner radius inside a transparent cell.
        tile.frame = NSRect(x: 4, y: 32, width: 212, height: 148)
        tile.wantsLayer = true
        tile.layer?.cornerRadius = DesignMetrics.radii["inner"]!
        tile.layer?.masksToBounds = true
        tile.layer?.contentsGravity = .resizeAspectFill
        placeholder.frame = tile.frame
        placeholder.alignment = .center
        placeholder.textColor = .secondaryLabelColor
        placeholder.maximumNumberOfLines = 1
        nameLabel.frame = NSRect(x: 4, y: 4, width: 212, height: 21)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.wantsLayer = true
        // Selection follows page 11/12's tile outline; Current Item is an inset ring.
        selectionOutline.borderWidth = 2
        selectionOutline.cornerRadius = DesignMetrics.radii["inner"]! + 4
        selectionOutline.isHidden = true
        surface.layer?.addSublayer(selectionOutline)
        currentRing.frame = tile.bounds.insetBy(dx: 3, dy: 3)
        currentRing.cornerRadius = DesignMetrics.radii["inner"]!
        currentRing.borderWidth = 2
        currentRing.isHidden = true
        tile.layer?.addSublayer(currentRing)
        surface.addSubview(tile)
        surface.addSubview(placeholder)
        surface.addSubview(nameLabel)
        surface.setAccessibilityRole(.button)
        view = surface
        layoutContent()
    }

    private func layoutContent() {
        guard isViewLoaded else { return }
        let width = max(0, view.bounds.width - 8)
        let height = max(0, view.bounds.height - 36)
        tile.frame = NSRect(x: 4, y: 32, width: width, height: height)
        placeholder.frame = tile.frame
        nameLabel.frame = NSRect(x: 4, y: 4, width: width, height: 21)
        selectionOutline.frame = tile.frame.insetBy(dx: -4, dy: -4)
        currentRing.frame = tile.bounds.insetBy(dx: 3, dy: 3)
    }

    var tileLayer: CALayer? { tile.layer }
    var currentRingLayer: CALayer { currentRing }
    /// Current Item (where arrows, Space and Enter act); distinct from Selection.
    public var isCurrent = false { didSet { updateSelection() } }
    public func configure(_ entry: FolderEntry) {
        thumbnailToken = UUID()
        tile.layer?.contents = nil
        placeholder.stringValue = String(localized: "Thumbnail pending")
        placeholder.isHidden = false
        thumbnailPixelEdge = 0
        representedItemID = entry.itemID
        filename = entry.url.lastPathComponent
        nameLabel.stringValue = filename
        view.setAccessibilityLabel("\(filename), \(String(localized: "thumbnail pending"))")
        view.setAccessibilityIdentifier("grid.cell")
        updateSelection()
    }

    public func beginThumbnail(generation: UInt64, pixelEdge: Int, token: UUID = UUID()) {
        thumbnailToken = token
        thumbnailGeneration = generation
        thumbnailPixelEdge = pixelEdge
        tile.layer?.contents = nil
        placeholder.stringValue = String(localized: "Thumbnail pending")
        placeholder.isHidden = false
        view.setAccessibilityLabel("\(filename), \(String(localized: "thumbnail pending"))")
    }

    @discardableResult public func installThumbnail(_ request: ImageDecodeRequest, image: DecodedImage,
        token: UUID, generation: UInt64, pixelEdge: Int) -> Bool {
        guard let key = request.renderKey,
              token == thumbnailToken, generation == thumbnailGeneration,
              pixelEdge == thumbnailPixelEdge, request.maximumPixelSize == pixelEdge,
              key.maximumPixelSize == pixelEdge, key.itemID == representedItemID,
              image.itemID == key.itemID, image.revision == key.revision,
              image.image.width > 0, image.image.height > 0,
              image.image.width <= pixelEdge, image.image.height <= pixelEdge else { return false }
        tile.layer?.contents = image.image
        placeholder.isHidden = true
        view.setAccessibilityLabel(filename)
        return true
    }

    public func thumbnailUnavailable(token: UUID) {
        guard token == thumbnailToken else { return }
        tile.layer?.contents = nil
        placeholder.stringValue = String(localized: "Thumbnail unavailable")
        placeholder.isHidden = false
        view.setAccessibilityLabel("\(filename), \(String(localized: "thumbnail unavailable"))")
    }

    public override var isSelected: Bool { didSet { updateSelection() } }
    private func updateSelection() {
        guard isViewLoaded else { return }
        var accent = NSColor.clear.cgColor
        var fill = NSColor.clear.cgColor
        var surface = NSColor.clear.cgColor
        var ring = NSColor.clear.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            ring = DesignColor.focusRing.nsColor.cgColor
            accent = DesignColor.accent.nsColor.cgColor
            fill = DesignColor.selectionFill.nsColor.cgColor
            surface = DesignColor.sidebarBackground.nsColor.cgColor
        }
        selectionOutline.borderColor = accent
        selectionOutline.isHidden = !isSelected
        tile.layer?.backgroundColor = surface
        currentRing.borderColor = ring
        currentRing.isHidden = !isCurrent
        nameLabel.layer?.backgroundColor = isSelected ? fill : NSColor.clear.cgColor
        view.setAccessibilityValue(isSelected ? String(localized: "Selected") : "")
    }
}

/// Page 11/12 inlined CSS: `.grid-scroll`, `.photo-grid`, `.photo-cell`,
/// `.thumbnail-wrap`, and `.layout-exploration .photo-name` (grid-light/dark.html).
private struct GridGeometry: Equatable {
    let columns: Int
    let itemSize: NSSize
    let columnGap: CGFloat
    let rowGap: CGFloat
    let horizontalInset: CGFloat
    let topInset: CGFloat = 16

    init(viewportWidth width: CGFloat, contentWidth: CGFloat) {
        let narrow = width <= 1050
        let wide = width >= 1600
        horizontalInset = narrow ? 16 : (wide ? 32 : 24)
        columnGap = narrow ? 12 : (wide ? 22 : 16)
        rowGap = narrow ? 12 : (wide ? 22 : 18)
        let minColumnWidth: CGFloat = width <= 720 ? 145 : 220
        let available = max(0, contentWidth - 2 * horizontalInset)
        columns = width <= 480 ? 1 : max(1, Int((available + columnGap) / (minColumnWidth + columnGap)))
        // Leave one representable step of slack so flow layout does not wrap an exact-fit row.
        let cellWidth = max(0, ((available - CGFloat(columns - 1) * columnGap) / CGFloat(columns)).nextDown)
        let tileHeight: CGFloat
        if width <= 720 { tileHeight = 150 }
        else if narrow { tileHeight = 165 }
        else if wide { tileHeight = 200 }
        else { tileHeight = min(225, max(135, width * 0.147)) }
        // Cell padding 4+4; name margin 7, padded line 21, bottom padding 4.
        itemSize = NSSize(width: cellWidth, height: tileHeight + 36)
    }
}

@MainActor private final class GridCollectionView: NSCollectionView {
    var onArrow: ((Int) -> Void)?
    var columnStep = 1
    override func keyDown(with event: NSEvent) {
        let delta: Int
        switch event.keyCode {
        case 123: delta = -1
        case 124: delta = 1
        case 125: delta = columnStep
        case 126: delta = -columnStep
        default: super.keyDown(with: event); return
        }
        onArrow?(delta)
    }
}

/// Data source retains identity separately from position; native collection view handles reuse.
@MainActor public final class GridBrowserView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    public private(set) var collectionView: NSCollectionView = GridCollectionView()
    public private(set) var currentItemID: ItemID? { didSet { drawCurrent() } }
    public var onSelect: ((ItemID) -> Void)?
    public var onDeselect: (() -> Void)?
    /// The grid's Current Item changed without a selection (entry, Esc return, removal fallback).
    public var onCurrentChange: ((ItemID) -> Void)?
    private let scrollView = NSScrollView()
    private var entries: [FolderEntry] = []
    private var indices: [ItemID: Int] = [:]
    private var updating = false
    private var geometry: GridGeometry?
    private let thumbnailScheduler = GridThumbnailScheduler()
    public var thumbnailLoader: (@Sendable (FolderEntry, AccessRootID, Int, DecodePriority) async throws -> (ImageDecodeRequest, DecodedImage))? {
        didSet { reconcileThumbnails() }
    }
    private var thumbnailsActive = false
    private var thumbnailGeneration: UInt64 = 0
    private static let reuseID = NSUserInterfaceItemIdentifier("grid.photo")

    public override init(frame: NSRect) {
        super.init(frame: frame)
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 220, height: 184)
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 18
        layout.sectionInset = NSEdgeInsets(top: 16, left: 24, bottom: 30, right: 24)
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [DesignColor.canvasBackground.nsColor]
        collectionView.dataSource = self
        collectionView.delegate = self
        (collectionView as? GridCollectionView)?.onArrow = { [weak self] delta in
            self?.moveCurrent(by: delta)
        }
        collectionView.register(GridPhotoItem.self, forItemWithIdentifier: Self.reuseID)
        collectionView.setAccessibilityIdentifier("grid.collection")
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.backgroundColor = DesignColor.canvasBackground.nsColor
        scrollView.documentView = collectionView
        addSubview(scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(clipFrameChanged),
            name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollerStyleChanged),
            name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        thumbnailScheduler.onResult = { [weak self] index, request, image in
            self?.showThumbnail(at: index, request: request, image: image)
        }
        thumbnailScheduler.onFailure = { [weak self] index in self?.showThumbnailFailure(at: index) }
        updateGeometry()
    }
    public required init?(coder: NSCoder) { nil }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func clipFrameChanged() {
        updateGeometry()
        reconcileThumbnails()
    }

    @objc private func clipBoundsChanged() { reconcileThumbnails() }

    @objc private func scrollerStyleChanged() {
        scrollView.tile()
        updateGeometry()
    }

    public override func layout() {
        super.layout()
        updateGeometry()
        reconcileThumbnails()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        reconcileThumbnails()
    }

    public func setThumbnailsActive(_ active: Bool) {
        thumbnailsActive = active
        if active { reconcileThumbnails() } else { thumbnailScheduler.stop() }
    }

    public func stopThumbnails() { setThumbnailsActive(false) }

    private var thumbnailPixelEdge: Int {
        guard let geometry else { return 0 }
        let scale: CGFloat
        if let window { scale = window.backingScaleFactor } else { scale = 1 }
        return GridThumbnailPixelSizing.edge(tile: NSSize(width: geometry.itemSize.width - 8,
            height: geometry.itemSize.height - 36), backingScale: scale)
    }

    private func reconcileThumbnails() {
        guard thumbnailsActive, window != nil, let geometry, thumbnailLoader != nil else {
            thumbnailScheduler.reconcile(visible: [], columns: 1, pixelEdge: 0, loader: nil)
            return
        }
        collectionView.layoutSubtreeIfNeeded()
        // The flow layout is installed in init and remains this view's layout.
        let attributes = collectionView.collectionViewLayout!.layoutAttributesForElements(in: collectionView.visibleRect)
        var visible: Set<Int> = []
        for attribute in attributes where attribute.representedElementCategory == .item {
            if let index = attribute.indexPath?.item { visible.insert(index) }
        }
        thumbnailScheduler.reconcile(visible: visible, columns: geometry.columns,
            pixelEdge: thumbnailPixelEdge, loader: thumbnailLoader)
        for index in visible { bindThumbnail(at: index) }
    }

    private func bindThumbnail(at index: Int) {
        guard entries.indices.contains(index), let token = thumbnailScheduler.token(at: index),
              let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? GridPhotoItem,
              item.representedItemID == entries[index].itemID else { return }
        let edge = thumbnailPixelEdge
        if item.thumbnailToken != token || item.thumbnailGeneration != thumbnailGeneration || item.thumbnailPixelEdge != edge {
            item.beginThumbnail(generation: thumbnailGeneration, pixelEdge: edge, token: token)
        }
        if let (request, image) = thumbnailScheduler.result(at: index) {
            _ = item.installThumbnail(request, image: image, token: token,
                generation: thumbnailGeneration, pixelEdge: edge)
        }
    }

    private func showThumbnail(at index: Int, request: ImageDecodeRequest, image: DecodedImage) {
        guard entries.indices.contains(index), let token = thumbnailScheduler.token(at: index),
              let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? GridPhotoItem,
              item.representedItemID == entries[index].itemID else { return }
        _ = item.installThumbnail(request, image: image, token: token,
            generation: thumbnailGeneration, pixelEdge: thumbnailPixelEdge)
    }

    private func showThumbnailFailure(at index: Int) {
        guard let token = thumbnailScheduler.token(at: index),
              let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? GridPhotoItem else { return }
        item.thumbnailUnavailable(token: token)
    }

    private func updateGeometry() {
        let next = GridGeometry(viewportWidth: bounds.width, contentWidth: scrollView.contentSize.width)
        guard next != geometry, let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        geometry = next
        (collectionView as? GridCollectionView)?.columnStep = next.columns
        layout.itemSize = next.itemSize
        layout.minimumInteritemSpacing = next.columnGap
        layout.minimumLineSpacing = next.rowGap
        layout.sectionInset = NSEdgeInsets(top: next.topInset, left: next.horizontalInset,
            bottom: 30, right: next.horizontalInset)
        layout.invalidateLayout()
    }

    public func display(_ snapshot: FolderSnapshot, selectedItemID: ItemID?) {
        thumbnailScheduler.setSnapshot(snapshot)
        thumbnailGeneration = snapshot.version.generation
        if !snapshot.isComplete {
            entries = []; indices = [:]; currentItemID = nil
            updating = true
            collectionView.reloadData()
            collectionView.deselectAll(nil)
            updating = false
            reconcileThumbnails()
            return
        }
        entries = snapshot.navigationEntries
        indices = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.itemID, $0.offset) })
        if let currentItemID, indices[currentItemID] == nil {
            self.currentItemID = entries.first?.itemID
            if let first = self.currentItemID { onCurrentChange?(first) }
        }
        updating = true
        collectionView.reloadData()
        collectionView.deselectAll(nil)
        if let selectedItemID, let index = indices[selectedItemID] {
            collectionView.selectItems(at: [IndexPath(item: index, section: 0)], scrollPosition: [])
        } else {
            collectionView.deselectAll(nil)
        }
        updating = false
        reconcileThumbnails()
    }
    /// A requested Current Item that is filtered out or gone falls back to the first item in sort order.
    public func activate(currentItemID: ItemID? = nil) {
        if let currentItemID { self.currentItemID = indices[currentItemID] != nil ? currentItemID : nil }
        if self.currentItemID.flatMap({ indices[$0] }) == nil { self.currentItemID = entries.first?.itemID }
        if let current = self.currentItemID { onCurrentChange?(current) }
        window?.makeFirstResponder(collectionView)
    }
    private func moveCurrent(by delta: Int) {
        guard !entries.isEmpty else { return }
        let current = currentItemID.flatMap { indices[$0] } ?? 0
        let next = max(0, min(entries.count - 1, current + delta))
        guard next != current || currentItemID == nil, let id = itemID(at: next) else { return }
        currentItemID = id
        updating = true
        collectionView.deselectAll(nil)
        collectionView.selectItems(at: [IndexPath(item: next, section: 0)], scrollPosition: [])
        updating = false
        onSelect?(id)
    }
    private func drawCurrent() {
        for case let item as GridPhotoItem in collectionView.visibleItems() {
            item.isCurrent = item.representedItemID != nil && item.representedItemID == currentItemID
        }
    }
    public func itemID(at index: Int) -> ItemID? { entries.indices.contains(index) ? entries[index].itemID : nil }
    public func index(for id: ItemID) -> Int? { indices[id] }
    public func entry(for id: ItemID) -> FolderEntry? { indices[id].map { entries[$0] } }
    public var contentOffset: NSPoint { scrollView.contentView.bounds.origin }
    public func restoreContentOffset(_ point: NSPoint) {
        scrollView.contentView.setBoundsOrigin(point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    public func scrollTo(_ id: ItemID) {
        guard let index = indices[id] else { return }
        collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .top)
    }
    public func firstVisibleItemID() -> ItemID? {
        collectionView.visibleItems().compactMap { item in collectionView.indexPath(for: item)?.item }
            .min().flatMap { itemID(at: $0) }
    }
    public func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { entries.count }
    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.reuseID, for: indexPath)
        if let photo = item as? GridPhotoItem {
            photo.configure(entries[indexPath.item])
            photo.isCurrent = entries[indexPath.item].itemID == currentItemID
            if let token = thumbnailScheduler.token(at: indexPath.item) {
                let edge = thumbnailPixelEdge
                photo.beginThumbnail(generation: thumbnailGeneration, pixelEdge: edge, token: token)
                if let (request, image) = thumbnailScheduler.result(at: indexPath.item) {
                    _ = photo.installThumbnail(request, image: image, token: token,
                        generation: thumbnailGeneration, pixelEdge: edge)
                }
            }
        }
        return item
    }
    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !updating, let index = indexPaths.first?.item, let id = itemID(at: index) else { return }
        currentItemID = id
        onSelect?(id)
    }
    public func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !updating, collectionView.selectionIndexPaths.isEmpty else { return }
        onDeselect?()
    }
}
