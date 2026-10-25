import AppKit
import PicseeCore

@MainActor private final class GridPhotoSurface: NSView {
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

/// A reused grid item contains only display data supplied by an authorized snapshot.
@MainActor public final class GridPhotoItem: NSCollectionViewItem {
    public private(set) var representedItemID: ItemID?
    public private(set) var filename = ""
    private let tile = NSView()
    private let placeholder = NSTextField(labelWithString: String(localized: "Thumbnail pending"))
    private let nameLabel = NSTextField(labelWithString: "")

    public override func loadView() {
        let surface = GridPhotoSurface(frame: NSRect(x: 0, y: 0, width: 220, height: 184))
        surface.onAppearanceChange = { [weak self] in self?.updateSelection() }
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 7
        // Page 11 `.thumbnail-wrap`: a quiet surface tile with the inner radius inside a transparent cell.
        tile.frame = NSRect(x: 8, y: 36, width: 204, height: 140)
        tile.wantsLayer = true
        tile.layer?.cornerRadius = CGFloat(DesignMetrics.radii["inner"] ?? 4)
        tile.autoresizingMask = [.width, .height]
        placeholder.frame = NSRect(x: 8, y: 36, width: 204, height: 140)
        placeholder.alignment = .center
        placeholder.textColor = .secondaryLabelColor
        placeholder.maximumNumberOfLines = 1
        placeholder.autoresizingMask = [.width, .height]
        nameLabel.frame = NSRect(x: 8, y: 6, width: 204, height: 22)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        nameLabel.wantsLayer = true
        nameLabel.autoresizingMask = [.width, .maxYMargin]
        surface.addSubview(tile)
        surface.addSubview(placeholder)
        surface.addSubview(nameLabel)
        surface.setAccessibilityRole(.button)
        view = surface
    }

    var tileLayer: CALayer? { tile.layer }
    public func configure(_ entry: FolderEntry) {
        representedItemID = entry.itemID
        filename = entry.url.lastPathComponent
        nameLabel.stringValue = filename
        view.setAccessibilityLabel("\(filename), \(String(localized: "thumbnail pending"))")
        view.setAccessibilityIdentifier("grid.cell")
        updateSelection()
    }

    public override var isSelected: Bool { didSet { updateSelection() } }
    private func updateSelection() {
        guard isViewLoaded else { return }
        var accent = NSColor.clear.cgColor
        var fill = NSColor.clear.cgColor
        var surface = NSColor.clear.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            accent = DesignColor.accent.nsColor.cgColor
            fill = DesignColor.selectionFill.nsColor.cgColor
            surface = DesignColor.sidebarBackground.nsColor.cgColor
        }
        view.layer?.borderWidth = isSelected ? 2 : 0
        view.layer?.borderColor = accent
        tile.layer?.backgroundColor = surface
        nameLabel.layer?.backgroundColor = isSelected ? fill : NSColor.clear.cgColor
        view.setAccessibilityValue(isSelected ? String(localized: "Selected") : "")
    }
}

func gridViewportWidth(enclosing: CGFloat?, visible: CGFloat) -> CGFloat { enclosing ?? visible }

@MainActor private final class GridCollectionView: NSCollectionView {
    var onArrow: ((Int) -> Void)?
    override func keyDown(with event: NSEvent) {
        let delta: Int
        switch event.keyCode {
        case 123: delta = -1
        case 124: delta = 1
        case 125: delta = columns
        case 126: delta = -columns
        default: super.keyDown(with: event); return
        }
        onArrow?(delta)
    }
    private var columns: Int {
        guard let layout = collectionViewLayout as? NSCollectionViewFlowLayout else { return 1 }
        let inset = layout.sectionInset.left + layout.sectionInset.right
        let viewportWidth = gridViewportWidth(enclosing: enclosingScrollView?.bounds.width, visible: visibleRect.width)
        return max(1, Int((viewportWidth - inset + layout.minimumInteritemSpacing) /
            (layout.itemSize.width + layout.minimumInteritemSpacing)))
    }
}

/// Data source retains identity separately from position; native collection view handles reuse.
@MainActor public final class GridBrowserView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    public private(set) var collectionView: NSCollectionView = GridCollectionView()
    public private(set) var currentItemID: ItemID?
    public var onSelect: ((ItemID) -> Void)?
    public var onDeselect: (() -> Void)?
    /// The grid's Current Item changed without a selection (entry, Esc return, removal fallback).
    public var onCurrentChange: ((ItemID) -> Void)?
    private let scrollView = NSScrollView()
    private var entries: [FolderEntry] = []
    private var indices: [ItemID: Int] = [:]
    private var updating = false
    private static let reuseID = NSUserInterfaceItemIdentifier("grid.photo")

    public override init(frame: NSRect) {
        super.init(frame: frame)
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 220, height: 184)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 16
        layout.sectionInset = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
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
        scrollView.backgroundColor = DesignColor.canvasBackground.nsColor
        scrollView.documentView = collectionView
        addSubview(scrollView)
    }
    public required init?(coder: NSCoder) { nil }

    public func display(_ snapshot: FolderSnapshot, selectedItemID: ItemID?) {
        if !snapshot.isComplete {
            entries = []; indices = [:]; currentItemID = nil
            updating = true
            collectionView.reloadData()
            collectionView.deselectAll(nil)
            updating = false
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
        if let selectedItemID, let index = indices[selectedItemID] {
            collectionView.selectItems(at: [IndexPath(item: index, section: 0)], scrollPosition: [])
        } else {
            collectionView.deselectAll(nil)
        }
        updating = false
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
        collectionView.selectItems(at: [IndexPath(item: next, section: 0)], scrollPosition: [])
        updating = false
        onSelect?(id)
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
        if let photo = item as? GridPhotoItem { photo.configure(entries[indexPath.item]) }
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
