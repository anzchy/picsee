import AppKit
import SwiftUI
import Observation
import PicseeCore
import PicseeApplication

private struct StateText: View {
    let lines: [String]
    let isLoading: Bool
    let isNotice: Bool
    var body: some View {
        VStack(spacing: 12) {
            if isLoading { IndeterminateProgressRow(label: lines[0]) }
            else {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line).font(Font(DesignMetrics.font(isNotice ? "uiSmall" : index == 0 ? "title" : "ui")))
                        .foregroundStyle(index == 0 ? DesignColor.textPrimary.color : DesignColor.textSecondary.color)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Native state surface; decisions arrive as Application-owned image status.
public final class ViewerStateHost: NSView {
    public private(set) var buttons: [NSButton] = []
    public private(set) var textLines: [String] = []
    public private(set) var showsProgress = false
    public var onRetry: (() -> Void)?
    public var onCancelFolderReading: (() -> Void)?
    private weak var keyCanvas: NSView?
    private weak var keyChrome: ViewerChromeOverlay?
    private var displayedStatus: ViewerImageStatus?
    private var displayedNextEnabled = false
    private var composedState: ViewerImageStatus?
    private var stateIcon: NSImageView?
    private var stateLabels: [NSTextField] = []
    public func linkKeyViews(to canvas: NSView, chrome: ViewerChromeOverlay) {
        keyCanvas = canvas; keyChrome = chrome
        ViewerStateFocus.link(canvas: canvas, state: self, chrome: chrome)
    }
    private var session: ViewerSession?
    private var tracking = false

    public convenience init(frame: NSRect, session: ViewerSession) {
        self.init(frame: frame)
        self.session = session
        refresh()
    }
    public func refresh() {
        guard let session else { return }
        if !tracking {
            tracking = true
            withObservationTracking {
                display(session.imageStatus, nextEnabled: session.isEnabled(.next))
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in self?.tracking = false; self?.refresh() }
            }
        } else { display(session.imageStatus, nextEnabled: session.isEnabled(.next)) }
    }
    public func display(_ status: ViewerImageStatus, nextEnabled: Bool = false) {
        guard displayedStatus != status || displayedNextEnabled != nextEnabled else { return }
        displayedStatus = status; displayedNextEnabled = nextEnabled
        if let focused = window?.firstResponder as? NSView,
           buttons.contains(where: { focused === $0 || focused.isDescendant(of: $0) }), let keyCanvas {
            session?.updateFocus(.canvas)
            window?.makeFirstResponder(keyCanvas)
        }
        defer {
            if let keyCanvas, let keyChrome { ViewerStateFocus.link(canvas: keyCanvas, state: self, chrome: keyChrome) }
        }
        setAccessibilityChildren([])
        isHidden = status == .showing
        setAccessibilityHidden(isHidden)
        subviews.forEach {
            $0.isHidden = true; $0.setAccessibilityHidden(true); $0.nextKeyView = nil
            if let button = $0 as? NSButton { button.isEnabled = false; button.setAccessibilityEnabled(false) }
            $0.removeFromSuperview()
        }
        buttons = []; textLines = []; showsProgress = false
        composedState = nil; stateIcon = nil; stateLabels = []
        var actions: [(String, String)] = []
        var failure = false
        let notice = status == .detailLimited
        switch status {
        case .empty:
            textLines = [String(localized: "Open a folder to start browsing"),
                         String(localized: "Images stay on your Mac. Browse by folder."),
                         String(localized: "You can also drop images or folders here.")]
            actions = [(String(localized: "Choose Folder…"), "state.open")]
        case .loading(let name):
            showsProgress = true
            textLines = [String(format: String(localized: "Opening %@…"), name)]
            actions = [(String(localized: "Cancel"), "state.cancel")]
        case .readingFolder:
            // Page 24 uses the canvas surface; keep the prior image intact underneath for Cancel.
            let surface = NSBox(frame: bounds)
            surface.boxType = .custom; surface.borderType = .noBorder
            surface.titlePosition = .noTitle; surface.cornerRadius = 0
            surface.fillColor = DesignColor.canvasBackground.nsColor
            surface.autoresizingMask = [.width, .height]
            surface.setAccessibilityElement(false)
            addSubview(surface)
            showsProgress = true
            textLines = [String(localized: "Reading Folder…"),
                String(localized: "Looking for images to browse. Please wait.")]
            let center = max(160, bounds.midY)
            let progress = NSHostingView(rootView: IndeterminateProgressRow(label: textLines[0]))
            progress.frame = NSRect(x: 16, y: center, width: max(0, bounds.width - 32), height: 80)
            progress.autoresizingMask = [.width, .minYMargin, .maxYMargin]
            progress.setAccessibilityIdentifier("state.folder-title")
            progress.setAccessibilityElement(true); progress.setAccessibilityLabel(textLines[0])
            let subtitle = NSTextField(labelWithString: textLines[1])
            subtitle.font = DesignMetrics.font("ui"); subtitle.textColor = DesignColor.textSecondary.nsColor
            subtitle.alignment = .center
            subtitle.frame = NSRect(x: 16, y: center + 2, width: max(0, bounds.width - 32), height: 24)
            subtitle.autoresizingMask = [.width, .minYMargin, .maxYMargin]
            subtitle.setAccessibilityIdentifier("state.folder-subtitle")
            let cancel = ViewerStateButton(title: String(localized: "Cancel Reading"), target: self, action: #selector(activate(_:)))
            cancel.session = session; cancel.bezelStyle = .rounded; cancel.focusRingType = .exterior
            cancel.identifier = NSUserInterfaceItemIdentifier("state.cancel-folder")
            cancel.setAccessibilityIdentifier("state.cancel-folder")
            cancel.frame = NSRect(x: (bounds.width - 180) / 2, y: center - 44, width: 180, height: 32)
            cancel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            [progress, subtitle, cancel].forEach { addSubview($0) }
            buttons = [cancel]; setAccessibilityChildren([progress, subtitle, cancel])
            return
        case .noMatches:
            textLines = [String(localized: "No Images Match This Filter"),
                         String(localized: "Choose another extension or clear the filter.")]
            actions = [(String(localized: "Clear Filter"), "state.clear-filter")]
        case .failed(let kind, let name):
            failure = true
            textLines = [String(localized: "Unable to read this image"), name,
                String(localized: String.LocalizationValue(kind.messageKey))]
            actions = [(String(localized: "Retry"), "state.retry")]
            if nextEnabled { actions.append((String(localized: "Next"), "state.next")) }
        case .detailLimited: textLines = [String(localized: "Showing reduced detail")]
        case .showing: return
        }
        if case .empty = status {
            composeState(status, actions: actions)
            return
        }
        if failure {
            composeState(status, actions: actions)
            return
        }
        let text = NSHostingView(rootView: StateText(lines: textLines, isLoading: showsProgress,
            isNotice: notice))
        let center = max(160, bounds.midY)
        text.frame = NSRect(x: 16, y: notice ? bounds.height - 84 : center,
            width: max(0, bounds.width - 32), height: notice ? 32 : failure ? 160 : 80)
        text.autoresizingMask = notice ? [.width, .minYMargin] : [.width, .minYMargin, .maxYMargin]
        addSubview(text)
        let width: CGFloat = actions.count > 1 ? 80 : 180
        let total = CGFloat(actions.count) * width + CGFloat(max(0, actions.count - 1)) * 12
        for (index, action) in actions.enumerated() {
            let button = ViewerStateButton(title: action.0, target: self, action: #selector(activate(_:)))
            button.session = session
            button.bezelStyle = .rounded; button.focusRingType = .exterior
            button.identifier = NSUserInterfaceItemIdentifier(action.1)
            button.setAccessibilityIdentifier(action.1)
            button.frame = NSRect(x: (bounds.width - total) / 2 + CGFloat(index) * (width + 12),
                y: center - 44, width: width, height: 32)
            button.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            addSubview(button); buttons.append(button)
        }
        setAccessibilityChildren([text as NSView] + buttons)
    }

    private func composeState(_ status: ViewerImageStatus, actions: [(String, String)]) {
        composedState = status
        let failure: Bool
        if case .failed = status { failure = true } else { failure = false }
        let iconLabel = Self.stateIconLabel(failure: failure)
        let image = NSImageView(image: NSImage(systemSymbolName: failure
            ? "exclamationmark.triangle" : DesignSymbol.folder.name,
            accessibilityDescription: iconLabel)!)
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        image.imageScaling = .scaleProportionallyDown
        image.setAccessibilityIdentifier("state.icon")
        image.setAccessibilityRole(.image)
        image.setAccessibilityLabel(iconLabel)
        addSubview(image); stateIcon = image
        for (index, line) in textLines.enumerated() {
            let field = NSTextField(labelWithString: line)
            field.font = index == 0 ? .systemFont(ofSize: 16, weight: .medium) : DesignMetrics.font("ui")
            field.textColor = failure && index == 2 ? DesignColor.errorText.nsColor :
                index == 0 ? DesignColor.textPrimary.nsColor : DesignColor.textSecondary.nsColor
            field.alignment = .center
            field.cell?.wraps = true
            field.cell?.usesSingleLineMode = false
            field.maximumNumberOfLines = 0
            let id = index == 0 ? "state.heading" : failure
                ? (index == 1 ? "state.filename" : "state.reason")
                : (index == 1 ? "state.description" : "state.drop-hint")
            field.setAccessibilityIdentifier(id)
            field.setAccessibilityRole(.staticText)
            field.setAccessibilityLabel(line)
            addSubview(field); stateLabels.append(field)
        }
        for action in actions {
            let button = ViewerStateButton(title: action.0, target: self, action: #selector(activate(_:)))
            button.session = session
            button.bezelStyle = .rounded; button.focusRingType = .exterior
            button.identifier = NSUserInterfaceItemIdentifier(action.1)
            button.setAccessibilityIdentifier(action.1)
            addSubview(button); buttons.append(button)
        }
        if failure {
            setAccessibilityChildren([image] + stateLabels + buttons)
        } else {
            setAccessibilityChildren([image, stateLabels[0], stateLabels[1], buttons[0], stateLabels[2]])
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    static func stateIconLabel(failure: Bool, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        if let locale {
            let localizedBundle = bundle.path(forResource: locale.identifier, ofType: "lproj")
                .flatMap(Bundle.init(path:)) ?? bundle
            return localizedBundle.localizedString(forKey: failure ? "Unreadable image" : "Open folder",
                                                   value: nil, table: nil)
        }
        return failure
            ? String(localized: "Unreadable image", bundle: bundle)
            : String(localized: "Open folder", bundle: bundle)
    }

    public override func layout() {
        super.layout()
        guard let status = composedState, let icon = stateIcon else { return }
        let failure: Bool
        if case .failed = status { failure = true } else { failure = false }
        let available = max(0, bounds.width - 32)
        let textWidth = min(640, available)
        func measure(_ field: NSTextField, width: CGFloat) -> CGFloat {
            let rect = (field.stringValue as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: field.font!])
            return ceil(rect.height) + 2
        }
        let heading = stateLabels[0], description = stateLabels[1]
        let headingHeight = measure(heading, width: textWidth)
        let descriptionHeight = measure(description, width: textWidth)
        let filenameHeight = failure ? descriptionHeight : 0
        let reasonHeight = failure ? measure(stateLabels[2], width: textWidth) : 0
        let hint = failure ? nil : stateLabels[2]
        let buttonWidth: CGFloat = failure ? 80 : max(180, ceil(buttons[0].intrinsicContentSize.width))
        let buttonHeight: CGFloat = 32
        let naturalHintWidth = hint.map { ceil($0.cell!.cellSize.width) } ?? 0
        let rowWidth = buttonWidth + 16 + naturalHintWidth
        let inlineHint = !failure && rowWidth <= textWidth
        let hintWidth = inlineHint ? naturalHintWidth : textWidth
        let hintHeight = hint.map {
            ceil($0.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: hintWidth,
                                                   height: .greatestFiniteMagnitude)).height)
        } ?? 0
        let actionHeight = inlineHint ? max(buttonHeight, hintHeight) : buttonHeight + (failure ? 0 : 9 + hintHeight)
        let contentHeight: CGFloat = 32 + 18 + headingHeight + 9 +
            (failure ? filenameHeight + 9 + reasonHeight : descriptionHeight) + 18 + actionHeight
        var top = bounds.midY + contentHeight / 2
        icon.frame = NSRect(x: bounds.midX - 16, y: top - 32, width: 32, height: 32)
        top -= 32 + 18
        heading.frame = NSRect(x: bounds.midX - textWidth / 2, y: top - headingHeight,
                               width: textWidth, height: headingHeight)
        top -= headingHeight + 9
        description.frame = NSRect(x: bounds.midX - textWidth / 2, y: top - descriptionHeight,
                                   width: textWidth, height: descriptionHeight)
        top -= descriptionHeight
        if failure {
            top -= 9
            stateLabels[2].frame = NSRect(x: bounds.midX - textWidth / 2, y: top - reasonHeight,
                                          width: textWidth, height: reasonHeight)
            top -= reasonHeight
        }
        top -= 18
        if failure {
            let gap: CGFloat = 16
            let total = CGFloat(buttons.count) * buttonWidth + CGFloat(max(0, buttons.count - 1)) * gap
            for (index, button) in buttons.enumerated() {
                button.frame = NSRect(x: bounds.midX - total / 2 + CGFloat(index) * (buttonWidth + gap),
                                      y: top - buttonHeight, width: buttonWidth, height: buttonHeight)
            }
        } else if let button = buttons.first, let hint {
            if inlineHint {
                button.frame = NSRect(x: bounds.midX - rowWidth / 2,
                                      y: top - (actionHeight + buttonHeight) / 2,
                                      width: buttonWidth, height: buttonHeight)
                hint.frame = NSRect(x: button.frame.maxX + 16,
                                    y: top - (actionHeight + hintHeight) / 2,
                                    width: hintWidth, height: hintHeight)
            } else {
                button.frame = NSRect(x: bounds.midX - buttonWidth / 2, y: top - buttonHeight,
                                      width: buttonWidth, height: buttonHeight)
                hint.frame = NSRect(x: bounds.midX - textWidth / 2,
                                    y: top - buttonHeight - 9 - hintHeight,
                                    width: textWidth, height: hintHeight)
            }
        }
    }
    @objc private func activate(_ sender: NSButton) {
        guard !isHiddenOrHasHiddenAncestor, sender.isEnabled, !sender.isHiddenOrHasHiddenAncestor,
              buttons.contains(where: { $0 === sender }), let session else { return }
        switch sender.identifier?.rawValue {
        case "state.cancel": session.cancelImageOpening(); refresh()
        case "state.cancel-folder":
            if let onCancelFolderReading { onCancelFolderReading() }
            else { session.cancelFolderReading() }
            refresh()
        case "state.clear-filter":
            var conditions = session.folderConditions
            conditions.selectedExtensions = nil
            session.setFolderConditions(conditions)
            refresh()
        case "state.retry": onRetry?()
        case "state.next": CommandRouter().route(.next, from: .button, to: session)
        default: CommandRouter().route(.open, from: .button, to: session)
        }
    }
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHiddenOrHasHiddenAncestor else { return nil }
        let local = convert(point, from: superview)
        return buttons.first { !$0.isHidden && $0.frame.contains(local) }
    }
}
