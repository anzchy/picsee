import AppKit
import ImageIO

@MainActor private final class CoverImageView: NSImageView {
    var cropRadius: CGFloat = 6
    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        let targetRatio = bounds.width / bounds.height
        let sourceRatio = image.size.width / image.size.height
        let source: NSRect
        if sourceRatio > targetRatio {
            let width = image.size.height * targetRatio
            source = NSRect(x: (image.size.width - width) / 2, y: 0, width: width, height: image.size.height)
        } else {
            let height = image.size.width / targetRatio
            source = NSRect(x: 0, y: (image.size.height - height) / 2, width: image.size.width, height: height)
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: cropRadius, yRadius: cropRadius).addClip()
        image.draw(in: bounds, from: source, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
}

@MainActor final class FirstLaunchView: NSView {
    static func sampleURL(name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "jpg")
    }
    let openButton: ViewerStateButton
    private let dropArea = NSView()
    private let dropOutline = CAShapeLayer()
    private let stack = NSView()
    private let heading = NSTextField(labelWithString: "")
    private let shortcut = NSTextField(labelWithString: "")
    private let chips = (0..<3).map { _ in NSTextField(labelWithString: "") }
    private var printViews: [String: CoverImageView] = [:]
    private var printHairlines: [String: CALayer] = [:]
    private var stackViews: [CoverImageView] = []
    private var dragActive = false
    private var animateFan = false
    var themeOverride: DesignTheme?
    var reduceMotionOverride: Bool?
    var reduceTransparencyOverride: Bool?
    var semanticViews: [NSView] { [heading, openButton, shortcut] + chips }
    private var reduceMotion: Bool { reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    private var theme: DesignTheme {
        themeOverride ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light)
    }
    init(frame: NSRect, openButton: ViewerStateButton) {
        self.openButton = openButton
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        setAccessibilityElement(false)
        for name in ["alley", "lakeside", "hillside", "gate", "temple", "lakehouse"] {
            let image = CoverImageView()
            image.wantsLayer = true
            image.setAccessibilityElement(false)
            image.setAccessibilityIdentifier("first-launch.print.\(name)")
            let hairline = CALayer()
            hairline.borderWidth = 1
            hairline.cornerRadius = 7
            image.layer?.addSublayer(hairline)
            addSubview(image)
            printViews[name] = image
            printHairlines[name] = hairline
        }
        dropArea.wantsLayer = true
        dropArea.setAccessibilityElement(false)
        dropArea.setAccessibilityIdentifier("first-launch.drop")
        dropOutline.fillColor = NSColor.clear.cgColor
        dropOutline.lineWidth = 1.5
        dropOutline.lineDashPattern = [6, 4]
        dropArea.layer?.addSublayer(dropOutline)
        addSubview(dropArea)
        stack.setAccessibilityElement(false)
        stack.setAccessibilityIdentifier("first-launch.stack")
        addSubview(stack)
        for _ in 0..<3 {
            let image = CoverImageView()
            image.cropRadius = 10
            image.wantsLayer = true
            image.setAccessibilityElement(false)
            stack.addSubview(image)
            stackViews.append(image)
        }
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        heading.alignment = .center
        heading.setAccessibilityElement(true); heading.setAccessibilityRole(.staticText)
        heading.setAccessibilityIdentifier("first-launch.heading")
        shortcut.font = .systemFont(ofSize: 13)
        shortcut.alignment = .left
        shortcut.setAccessibilityElement(true); shortcut.setAccessibilityRole(.staticText)
        shortcut.setAccessibilityIdentifier("first-launch.shortcut")
        addSubview(heading); addSubview(openButton); addSubview(shortcut)
        for (index, chip) in chips.enumerated() {
            chip.font = .systemFont(ofSize: 12)
            chip.alignment = .center
            chip.setAccessibilityElement(true); chip.setAccessibilityRole(.staticText)
            chip.wantsLayer = true
            chip.setAccessibilityIdentifier(["first-launch.chip.folder", "first-launch.chip.images", "first-launch.chip.formats"][index])
            addSubview(chip)
        }
        refreshStyle()
        loadSamples()
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(accessibilityOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }
    required init?(coder: NSCoder) { nil }
    @objc private func accessibilityOptionsChanged(_ notification: Notification) {
        if reduceMotion {
            stackViews.forEach { $0.layer?.removeAnimation(forKey: "b4.fan") }
            printViews.values.forEach { $0.layer?.removeAllAnimations() }
        }
        animateFan = false
        refreshStyle()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshStyle() }
    private func refreshStyle(animate: Bool = false) {
        let dark = theme == .dark
        let bg = DesignColor.canvasBackground.nsColor
        let border = DesignColor.divider.nsColor
        let tint = DesignColor.accent.nsColor
        heading.stringValue = dragActive ? String(localized: "Release to open") : String(localized: "Drop a photo folder here")
        shortcut.stringValue = String(localized: "or press ⌘O")
        heading.setAccessibilityLabel(heading.stringValue)
        shortcut.setAccessibilityLabel(shortcut.stringValue)
        for (chip, key) in zip(chips, ["Folder", "One or more images", "Common image formats"]) {
            chip.stringValue = String(localized: String.LocalizationValue(key))
            chip.setAccessibilityLabel(chip.stringValue)
            chip.textColor = DesignColor.textSecondary.nsColor
            chip.layer?.cornerRadius = 10
            chip.layer?.backgroundColor = (reduceTransparency ? DesignColor.sidebarBackground.nsColor : DesignColor.sidebarBackground.nsColor.withAlphaComponent(0.75)).cgColor
            chip.layer?.borderWidth = reduceTransparency ? 1 : 0
            chip.layer?.borderColor = border.cgColor
        }
        heading.textColor = DesignColor.textPrimary.nsColor
        shortcut.textColor = DesignColor.textSecondary.nsColor
        openButton.bezelColor = DesignColor.primaryFill.nsColor
        openButton.contentTintColor = DesignColor.onPrimary.nsColor
        openButton.font = .systemFont(ofSize: 13, weight: .semibold)
        dropArea.layer?.cornerRadius = 16
        dropOutline.isHidden = !dragActive
        dropOutline.strokeColor = tint.cgColor
        dropArea.layer?.backgroundColor = dragActive
            ? (reduceTransparency ? bg.blended(withFraction: 0.1, of: tint)! : tint.withAlphaComponent(0.1)).cgColor
            : NSColor.clear.cgColor
        let targetAlpha: CGFloat = reduceTransparency && dragActive ? 0 : (dark ? 0.4 : 0.3) * (dragActive ? 0.4 : 1)
        for (name, print) in printViews {
            print.layer?.cornerRadius = 6
            print.layer?.borderWidth = 5
            print.layer?.borderColor = bg.cgColor
            printHairlines[name]?.borderColor = border.cgColor
            print.layer?.shadowColor = NSColor.black.cgColor
            print.layer?.shadowOpacity = dark ? 0.45 : 0.14
            print.layer?.shadowRadius = 11
            print.layer?.shadowOffset = CGSize(width: 0, height: -8)
            if animate && !reduceMotion && !reduceTransparency {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.45
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    print.animator().alphaValue = targetAlpha
                }
            } else { print.alphaValue = targetAlpha }
        }
        for photo in stackViews {
            photo.layer?.cornerRadius = 10
            photo.layer?.borderWidth = 1
            photo.layer?.borderColor = border.cgColor
            photo.layer?.shadowColor = NSColor.black.cgColor
            photo.layer?.shadowOpacity = 0.18
            photo.layer?.shadowRadius = 13
        }
        needsLayout = true
    }
    func setDragActive(_ active: Bool) {
        guard dragActive != active else { return }
        dragActive = active
        animateFan = !reduceMotion
        if reduceMotion { stackViews.forEach { $0.layer?.removeAnimation(forKey: "b4.fan") } }
        refreshStyle(animate: true)
    }
    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        dropArea.frame = NSRect(x: 24, y: 24, width: max(0, w - 48), height: max(0, h - 62))
        dropOutline.frame = dropArea.bounds
        dropOutline.path = CGPath(roundedRect: dropArea.bounds.insetBy(dx: 0.75, dy: 0.75),
                                  cornerWidth: 16, cornerHeight: 16, transform: nil)
        // The B4 centre stays at native point size when the window changes size.
        let chipWidths = chips.map { ceil(($0.stringValue as NSString).size(withAttributes: [.font: $0.font!]).width) + 18 }
        let chipTotal = chipWidths.reduce(0, +) + 12
        let centreHeight: CGFloat = 150 + 30 + 18 + 24 + 18 + 30 + 18 + 20
        let centreMidY = dropArea.frame.midY
        let centreTop = centreMidY + centreHeight / 2
        stack.frame = NSRect(x: w / 2 - 110, y: centreTop - 150, width: 220, height: 150)
        for (index, image) in stackViews.enumerated() {
            image.frame = stack.bounds
            let expanded = dragActive && !reduceMotion
            let angle: CGFloat = index == 0 ? (expanded ? -14 : -9) : index == 1 ? (expanded ? 12 : 7) : 0
            let dx: CGFloat = index == 0 ? (expanded ? -58 : -36) : index == 1 ? (expanded ? 56 : 34) : 0
            let dy: CGFloat = index == 0 ? (expanded ? -10 : -8) : index == 1 ? (expanded ? -8 : -6) : (expanded ? 8 : 0)
            let next = CGAffineTransform(translationX: dx, y: dy).rotated(by: angle * .pi / 180)
            if animateFan, let layer = image.layer {
                let fan = CABasicAnimation(keyPath: "transform")
                fan.fromValue = CATransform3DMakeAffineTransform(layer.affineTransform())
                fan.toValue = CATransform3DMakeAffineTransform(next)
                fan.duration = 0.35
                fan.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(fan, forKey: "b4.fan")
            }
            image.layer?.setAffineTransform(next)
        }
        animateFan = false
        heading.frame = NSRect(x: w / 2 - 240, y: stack.frame.minY - 30 - 18 - 24, width: 480, height: 24)
        openButton.frame = NSRect(x: w / 2 - 152, y: heading.frame.minY - 18 - 30, width: 140, height: 30)
        shortcut.frame = NSRect(x: openButton.frame.maxX + 12, y: openButton.frame.minY + 6, width: 160, height: 18)
        var x = w / 2 - chipTotal / 2
        for (chip, width) in zip(chips, chipWidths) {
            chip.frame = NSRect(x: x, y: openButton.frame.minY - 18 - 20, width: width, height: 20)
            x += width + 6
        }
        let centre = NSRect(x: w / 2 - max(420, chipTotal) / 2, y: chips[0].frame.minY,
                            width: max(420, chipTotal), height: stack.frame.maxY - chips[0].frame.minY)
        for layout in FirstLaunchLayout.prints(in: bounds.size, centre: centre) {
            guard let image = printViews[layout.name] else { continue }
            image.frame = layout.frame
            printHairlines[layout.name]?.frame = image.bounds.insetBy(dx: -1, dy: -1)
            image.isHidden = layout.hidden
            image.layer?.setAffineTransform(CGAffineTransform(rotationAngle: layout.angle * .pi / 180))
        }
    }
    private func loadSamples() {
        let names = ["alley", "lakeside", "hillside", "gate", "temple", "lakehouse"]
        let paths = names.compactMap { name -> (String, URL)? in
            Self.sampleURL(name: name).map { (name, $0) }
        }
        Task.detached(priority: .utility) { [weak self] in
            var decoded: [String: CGImage] = [:]
            for (name, url) in paths {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 480,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { continue }
                decoded[name] = image
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (name, image) in decoded {
                    let nsImage = NSImage(cgImage: image, size: .zero)
                    if let print = self.printViews[name] {
                        let target = print.alphaValue
                        print.alphaValue = 0
                        print.image = nsImage
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = self.reduceMotion ? 0 : 0.45
                            print.animator().alphaValue = target
                        }
                    }
                    if let index = ["lakehouse", "gate", "alley"].firstIndex(of: name) {
                        self.stackViews[index].image = nsImage
                    }
                }
            }
        }
    }
}
