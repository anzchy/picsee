import AppKit

public struct GridSidebarFolder: Sendable, Equatable {
    public let url: URL
    public let count: Int?
    public init(url: URL, count: Int? = nil) { self.url = url; self.count = count }
}

@MainActor public final class GridSidebarFolderButton: NSButton {
    public let folderURL: URL
    public let nameLabel = NSTextField(labelWithString: "")
    public let countLabel = NSTextField(labelWithString: "")
    public let glyph = NSImageView()
    public let depth: Int
    public let current: Bool
    public var compact = false {
        didSet {
            nameLabel.font = .systemFont(ofSize: compact ? 12 : 13)
            needsLayout = true
        }
    }
    public init(folder: GridSidebarFolder, depth: Int, current: Bool) {
        self.folderURL = folder.url; self.depth = depth; self.current = current
        super.init(frame: .zero)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 6
        addSubview(glyph)
        addSubview(nameLabel)
        addSubview(countLabel)
        nameLabel.stringValue = folder.url.lastPathComponent
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        glyph.image = current ? Self.openFolderImage() : NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        glyph.imageScaling = .scaleProportionallyDown
        glyph.contentTintColor = current ? DesignColor.selectionText.nsColor : DesignColor.textSecondary.nsColor
        countLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        setCount(folder.count)
        setAccessibilityRole(.button)
        if current { setAccessibilityValue(String(localized: "Selected")) }
        setAccessibilityIdentifier("grid.sidebar.folder.\(folder.url.lastPathComponent)")
        refreshAppearance()
    }
    public required init?(coder: NSCoder) { nil }
    private static func openFolderImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 17, height: 17), flipped: false) { _ in
            let back = NSBezierPath()
            back.move(to: NSPoint(x: 2, y: 4))
            back.line(to: NSPoint(x: 2, y: 12))
            back.line(to: NSPoint(x: 6, y: 12))
            back.line(to: NSPoint(x: 7.5, y: 10.5))
            back.line(to: NSPoint(x: 15, y: 10.5))
            back.line(to: NSPoint(x: 15, y: 4))
            back.lineWidth = 1.5
            back.lineJoinStyle = .round
            back.stroke()
            let flap = NSBezierPath()
            flap.move(to: NSPoint(x: 2, y: 4))
            flap.line(to: NSPoint(x: 4, y: 9))
            flap.line(to: NSPoint(x: 16, y: 9))
            flap.line(to: NSPoint(x: 14, y: 3))
            flap.close()
            flap.lineWidth = 1.5
            flap.lineJoinStyle = .round
            flap.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
    public override var acceptsFirstResponder: Bool { !isHiddenOrHasHiddenAncestor && isEnabled }
    public override var canBecomeKeyView: Bool { acceptsFirstResponder }
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 || event.keyCode == 76 { performClick(nil) }
        else { super.keyDown(with: event) }
    }
    public func setCount(_ count: Int?) {
        countLabel.stringValue = count.map(String.init) ?? ""
        countLabel.isHidden = count == nil
        let name = folderURL.lastPathComponent
        if let count {
            let images = String(format: String(localized: "%lld images"), Int64(count))
            setAccessibilityLabel("\(name), \(images)")
        } else { setAccessibilityLabel(name) }
        needsLayout = true
    }
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = current ? DesignColor.selectionFill.nsColor.cgColor : NSColor.clear.cgColor
            nameLabel.textColor = current ? DesignColor.selectionText.nsColor : DesignColor.textPrimary.nsColor
            countLabel.textColor = DesignColor.textSecondary.nsColor
        }
    }
    public override func layout() {
        super.layout()
        let padding: CGFloat = compact ? (depth > 0 ? 9 : 7) : 10
        glyph.frame = NSRect(x: padding, y: depth > 0 && !current ? 8 : 7,
            width: depth > 0 && !current ? 16 : 17, height: depth > 0 && !current ? 16 : 17)
        let countWidth: CGFloat = countLabel.isHidden ? 0 : max(13, countLabel.intrinsicContentSize.width)
        countLabel.frame = NSRect(x: bounds.width - padding - countWidth, y: 7, width: countWidth, height: 18)
        let labelX = glyph.frame.maxX + (compact ? 6 : 9)
        nameLabel.frame = NSRect(x: labelX, y: 6, width: max(0, countLabel.frame.minX - labelX - (countLabel.isHidden ? 0 : 8)), height: 20)
    }
}

@MainActor public final class GridSidebarTreeView: NSView {
    public let heading = NSTextField(labelWithString: "")
    public let guide = NSView()
    public var viewportWidth: CGFloat = 1280 { didSet { if oldValue != viewportWidth { needsLayout = true } } }
    public private(set) var rows: [GridSidebarFolderButton] = []
    public var onSelectFolder: ((URL) -> Void)?
    private let scroll = NSScrollView()
    private let document = NSView()
    private let addFolderButton = NSButton()
    private let addFolderPlusButton = NSButton()
    private let addFolderBorder = CAShapeLayer()
    private var parent: GridSidebarFolder?
    private var currentFolder: GridSidebarFolder?
    public private(set) var children: [GridSidebarFolder] = []
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.documentView = document
        addSubview(scroll)
        document.addSubview(heading)
        document.addSubview(guide)
        heading.stringValue = String(localized: "Folders")
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.attributedStringValue = NSAttributedString(string: heading.stringValue,
            attributes: [.font: heading.font!, .kern: 0.48])
        heading.textColor = DesignColor.textSecondary.nsColor
        guide.wantsLayer = true
        guide.layer?.backgroundColor = DesignColor.divider.nsColor.cgColor
        guide.isHidden = true
        addFolderPlusButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addFolderPlusButton.isBordered = false
        addFolderPlusButton.isEnabled = false
        addFolderPlusButton.refusesFirstResponder = true
        addFolderPlusButton.setAccessibilityIdentifier("grid.sidebar.add-folder-plus")
        document.addSubview(addFolderPlusButton)
        addFolderButton.title = String(localized: "Add Folder")
        addFolderButton.font = .systemFont(ofSize: 12)
        addFolderButton.attributedTitle = NSAttributedString(string: addFolderButton.title, attributes: [
            .font: addFolderButton.font!, .foregroundColor: DesignColor.textSecondary.nsColor,
        ])
        addFolderButton.isBordered = false
        addFolderButton.isEnabled = false
        addFolderButton.refusesFirstResponder = true
        addFolderButton.setAccessibilityIdentifier("grid.sidebar.add-folder")
        addFolderButton.setAccessibilityLabel("\(addFolderButton.title) · \(String(localized: "Coming Soon"))")
        addFolderButton.wantsLayer = true
        addFolderButton.layer?.cornerRadius = DesignMetrics.radii["control"]!
        addFolderBorder.fillColor = NSColor.clear.cgColor
        addFolderBorder.strokeColor = DesignColor.divider.nsColor.cgColor
        addFolderBorder.lineWidth = 1
        addFolderBorder.lineDashPattern = [4, 3]
        addFolderButton.layer?.addSublayer(addFolderBorder)
        document.addSubview(addFolderButton)
    }
    public required init?(coder: NSCoder) { nil }
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            heading.textColor = DesignColor.textSecondary.nsColor
            guide.layer?.backgroundColor = DesignColor.divider.nsColor.cgColor
            addFolderBorder.strokeColor = DesignColor.divider.nsColor.cgColor
            addFolderPlusButton.contentTintColor = DesignColor.textSecondary.nsColor
        }
    }
    public func show(current: GridSidebarFolder, parent: GridSidebarFolder?, children: [GridSidebarFolder]) {
        self.parent = parent; currentFolder = current; self.children = children
        for row in rows { row.removeFromSuperview() }
        rows = []
        if let parent { append(parent, depth: 0, current: false) }
        let depth = parent == nil ? 0 : 1
        append(current, depth: depth, current: true)
        for child in children { append(child, depth: depth + 1, current: false) }
        needsLayout = true
        layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
    }
    public func clear() {
        parent = nil; currentFolder = nil; children = []
        for row in rows { row.removeFromSuperview() }
        rows = []
        guide.isHidden = true
        needsLayout = true
    }
    private func append(_ folder: GridSidebarFolder, depth: Int, current: Bool) {
        let row = GridSidebarFolderButton(folder: folder, depth: depth, current: current)
        if depth > 0 && !current { row.countLabel.alphaValue = 0.8 }
        row.target = self
        row.action = #selector(selectFolder(_:))
        document.addSubview(row)
        rows.append(row)
    }
    @objc private func selectFolder(_ sender: GridSidebarFolderButton) {
        guard !sender.current else { return }
        onSelectFolder?(sender.folderURL)
    }
    public func updateCount(_ count: Int?, for url: URL) {
        if currentFolder?.url == url { currentFolder = GridSidebarFolder(url: url, count: count) }
        if parent?.url == url { parent = GridSidebarFolder(url: url, count: count) }
        if let index = children.firstIndex(where: { $0.url == url }) { children[index] = GridSidebarFolder(url: url, count: count) }
        rows.first(where: { $0.folderURL == url })?.setCount(count)
    }
    public override func layout() {
        super.layout()
        scroll.frame = bounds
        let rowHeight: CGFloat = 32
        let compact = viewportWidth <= 720
        let headerTop: CGFloat = compact ? 44 : 50 // sidebar padding + folder heading 28pt margin
        let headerHeight: CGFloat = 14
        let firstRowTop = headerTop + headerHeight + 8
        func gapBefore(_ index: Int) -> CGFloat {
            index > 0 && rows[index].depth > rows[index - 1].depth ? 3 : 0
        }
        let rowsHeight = rows.indices.reduce(CGFloat(0)) { $0 + rowHeight + gapBefore($1) }
        let documentHeight = max(bounds.height, firstRowTop + rowsHeight + 12 + 30 + 16)
        document.frame = NSRect(x: 0, y: 0, width: bounds.width, height: documentHeight)
        heading.frame = NSRect(x: compact ? 20 : 22, y: documentHeight - headerTop - headerHeight,
            width: max(0, bounds.width - 66), height: headerHeight)
        addFolderPlusButton.frame = NSRect(x: max(0, bounds.width - 38), y: heading.frame.minY - 3,
            width: 20, height: 20)
        var rowY = documentHeight - firstRowTop
        for (index, row) in rows.enumerated() {
            row.compact = compact
            let x: CGFloat = 12 + CGFloat(row.depth) * (compact ? 8 : 19)
            rowY -= gapBefore(index) + rowHeight
            row.frame = NSRect(x: x, y: rowY, width: max(0, bounds.width - x - 12), height: rowHeight)
            row.layoutSubtreeIfNeeded()
        }
        let sidebarPadding: CGFloat = viewportWidth <= 1050 ? 8 : 12
        addFolderButton.frame = NSRect(x: sidebarPadding + 4, y: rowY - 12 - 30,
            width: max(0, bounds.width - 2 * sidebarPadding - 1 - 8), height: 30)
        addFolderBorder.frame = addFolderButton.bounds
        addFolderBorder.path = NSBezierPath(roundedRect: addFolderButton.bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: DesignMetrics.radii["control"]!, yRadius: DesignMetrics.radii["control"]!).cgPath
        if let firstChild = rows.firstIndex(where: { $0.depth > (parent == nil ? 0 : 1) }) {
            guide.isHidden = false
            let lastRowY = rows[rows.count - 1].frame.minY
            guide.frame = NSRect(x: rows[firstChild].frame.minX - (compact ? 3 : 6), y: lastRowY,
                width: 1, height: max(0, rows[firstChild].frame.maxY - lastRowY))
        } else { guide.isHidden = true }
    }
}
