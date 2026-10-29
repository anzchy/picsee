import AppKit

private final class ShortcutTextField: NSTextField {
    override var intrinsicContentSize: NSSize {
        let size = attributedStringValue.size()
        return NSSize(width: size.width, height: ceil(size.height))
    }
}

final class ShortcutKeycapView: NSView {
    let label: NSTextField
    let bottomEdge = NSView()

    init(_ glyph: String) {
        label = ShortcutTextField(labelWithString: glyph)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 4
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        label.textColor = DesignColor.textPrimary.nsColor
        label.lineBreakMode = .byClipping
        addSubview(label)
        bottomEdge.wantsLayer = true
        addSubview(bottomEdge)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    var preferredWidth: CGFloat { max(22, label.intrinsicContentSize.width + 12) }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 6, y: 0, width: max(0, bounds.width - 12), height: bounds.height)
        bottomEdge.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        applyColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = DesignColor.divider.nsColor.cgColor
            layer?.backgroundColor = DesignColor.canvasBackground.nsColor.cgColor
            bottomEdge.layer?.backgroundColor = DesignColor.divider.nsColor.cgColor
        }
    }
}

final class ShortcutRowView: NSView {
    let nameLabel: NSTextField
    let keycapViews: [ShortcutKeycapView]
    let separator = NSView()

    init(row: ShortcutRow) {
        nameLabel = ShortcutTextField(labelWithString: row.name)
        keycapViews = row.keycaps.map(ShortcutKeycapView.init)
        super.init(frame: .zero)
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.textColor = DesignColor.textPrimary.nsColor
        nameLabel.lineBreakMode = .byClipping
        nameLabel.maximumNumberOfLines = 1
        addSubview(nameLabel)
        for keycap in keycapViews { addSubview(keycap) }
        separator.wantsLayer = true
        addSubview(separator)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        var x = bounds.width
        for keycap in keycapViews.reversed() {
            let width = keycap.preferredWidth
            x -= width
            keycap.frame = NSRect(x: x, y: 6, width: width, height: 22)
            x -= 4
        }
        let keysMinX = keycapViews.first?.frame.minX ?? bounds.width
        nameLabel.frame = NSRect(x: 0, y: 0, width: max(0, keysMinX - 8), height: bounds.height)
        separator.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            separator.layer?.backgroundColor = DesignColor.dividerSubtle.nsColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}

final class ShortcutCardView: NSView {
    let titleLabel: NSTextField
    let whenLabel: NSTextField
    let rowViews: [ShortcutRowView]

    init(card: ShortcutCard) {
        titleLabel = NSTextField(labelWithString: card.title)
        whenLabel = NSTextField(labelWithString: card.when)
        rowViews = card.rows.map(ShortcutRowView.init)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 10
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = DesignColor.textPrimary.nsColor
        whenLabel.font = .systemFont(ofSize: 12)
        whenLabel.textColor = DesignColor.textSecondary.nsColor
        addSubview(titleLabel)
        addSubview(whenLabel)
        for (index, row) in rowViews.enumerated() {
            row.separator.isHidden = index == rowViews.count - 1
            addSubview(row)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    var requiredHeight: CGFloat { 44 + CGFloat(rowViews.count) * 34 }

    override func layout() {
        super.layout()
        let contentWidth = max(0, bounds.width - 30)
        titleLabel.frame = NSRect(x: 15, y: 15, width: titleLabel.intrinsicContentSize.width, height: 16)
        whenLabel.frame = NSRect(x: titleLabel.frame.maxX + 8, y: 17,
            width: whenLabel.intrinsicContentSize.width, height: 15)
        for (index, row) in rowViews.enumerated() {
            row.frame = NSRect(x: 15, y: 37 + CGFloat(index) * 34, width: contentWidth, height: 34)
        }
        applyColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = DesignColor.divider.nsColor.cgColor
            layer?.backgroundColor = DesignColor.canvasBackground.nsColor.cgColor
        }
    }
}

public final class ShortcutListView: NSView {
    let cardViews: [ShortcutCardView]

    public init(frame frameRect: NSRect, catalog: ShortcutCatalog) {
        cardViews = catalog.cards.map(ShortcutCardView.init)
        super.init(frame: frameRect)
        wantsLayer = true
        for card in cardViews { addSubview(card) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        let gap: CGFloat = 14
        let width = floor((bounds.width - 36 - gap * 2) / 3)
        let height = cardViews.map(\.requiredHeight).max() ?? 0
        for (index, card) in cardViews.enumerated() {
            card.frame = NSRect(x: 18 + CGFloat(index) * (width + gap), y: 18, width: width, height: height)
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = DesignColor.popoverBackground.nsColor.cgColor
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}
