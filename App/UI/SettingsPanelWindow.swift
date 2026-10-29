import AppKit
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

enum SettingsSection: String, CaseIterable {
    case general, display, cache, update, about
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .display: String(localized: "Display")
        case .cache: String(localized: "Cache")
        case .update: String(localized: "Updates")
        case .about: String(localized: "About")
        }
    }
}

@MainActor final class SettingsPanelWindow: NSObject, DisplayPreferencesObserver {
    private static let sectionKey = "settings.selectedSection.v1"
    let window: NSWindow
    private(set) var selectedSection: SettingsSection
    private let appearanceAdapter: WindowAppearanceAdapter
    private let preferencesStore: any DisplayPreferencesStore
    private let defaults: UserDefaults
    private let model: CacheSettingsModel
    private let confirmClear: (NSWindow, @escaping (Bool) -> Void) -> Void
    private var panes: [SettingsSection: NSView] = [:]
    private var sidebarButtons: [SettingsSection: NSButton] = [:]
    private var appearanceButtons: [DisplayAppearance: NSButton] = [:]
    private var toolsButton: NSButton!
    private var cacheSize: NSTextField!
    private var cacheDiagnostic: NSTextField!
    private var cacheClear: NSButton!

    init(cache: ThumbnailDiskCache, appearanceAdapter: WindowAppearanceAdapter,
         preferencesStore: any DisplayPreferencesStore, defaults: UserDefaults,
         confirmClear: ((NSWindow, @escaping (Bool) -> Void) -> Void)? = nil) {
        self.appearanceAdapter = appearanceAdapter
        self.preferencesStore = preferencesStore
        self.defaults = defaults
        self.model = CacheSettingsModel(cache: cache)
        self.selectedSection = SettingsSection(rawValue: defaults.string(forKey: Self.sectionKey) ?? "") ?? .general
        self.confirmClear = confirmClear ?? Self.presentClearConfirmation
        self.window = SettingsPanelNativeWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 482),
                                                styleMask: [.titled, .closable, .miniaturizable],
                                                backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.center()
        buildViews()
        preferencesStore.observe(self)
        preferencesDidChange(preferencesStore.value)
        select(selectedSection)
    }

    func show() {
        appearanceAdapter.register(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshCache()
    }

    func select(_ section: SettingsSection) {
        selectedSection = section
        defaults.set(section.rawValue, forKey: Self.sectionKey)
        window.title = section.title
        for (key, pane) in panes { pane.isHidden = key != section }
        for (key, button) in sidebarButtons {
            button.state = key == section ? .on : .off
            button.setAccessibilityValue(key == section ? "1" : "0")
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: DesignMetrics.font("ui"),
                .foregroundColor: key == section ? DesignColor.selectionText.nsColor : DesignColor.textPrimary.nsColor
            ])
            button.contentTintColor = key == section ? DesignColor.selectionText.nsColor : DesignColor.textSecondary.nsColor
            button.needsDisplay = true
        }
        if section == .cache { refreshCache() }
    }

    func preferencesDidChange(_ preferences: DisplayPreferences) {
        for (appearance, button) in appearanceButtons {
            button.state = appearance == preferences.appearance ? .on : .off
            button.setAccessibilityValue(appearance == preferences.appearance ? "1" : "0")
        }
        toolsButton.state = preferences.alwaysShowTools ? .on : .off
    }

    private func buildViews() {
        let root = SettingsSurfaceView(frame: NSRect(x: 0, y: 0, width: 760, height: 482), surface: .panel)
        let sidebar = SettingsSurfaceView(frame: NSRect(x: 0, y: 0, width: 180, height: 482), surface: .sidebar)
        sidebar.setAccessibilityIdentifier("settings.sidebar")
        root.addSubview(sidebar)
        let content = NSView(frame: NSRect(x: 180, y: 0, width: 580, height: 482))
        content.setAccessibilityIdentifier("settings.content")
        root.addSubview(content)
        for (index, section) in SettingsSection.allCases.enumerated() {
            let button = SettingsSidebarButton(title: section.title, target: self, action: #selector(selectSidebar(_:)))
            button.frame = NSRect(x: 8, y: 442 - CGFloat(index * 32), width: 164, height: 30)
            button.tag = index
            button.isBordered = false
            button.setButtonType(.toggle)
            button.alignment = .left
            button.font = DesignMetrics.font("ui")
            let symbols = ["gearshape", "rectangle.3.group", "externaldrive", "arrow.triangle.2.circlepath", "info.circle"]
            button.image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.setAccessibilityIdentifier("settings.section.\(section.rawValue)")
            sidebar.addSubview(button)
            sidebarButtons[section] = button
            let pane = NSView(frame: content.bounds)
            pane.setAccessibilityIdentifier("settings.pane.\(section.rawValue)")
            content.addSubview(pane)
            panes[section] = pane
            let heading = label(section.title, role: "title", bold: true)
            heading.frame = NSRect(x: 26, y: 444, width: 528, height: 20)
            pane.addSubview(heading)
        }
        buildGeneral()
        buildDisplay()
        buildCache()
        buildUpdates()
        buildAbout()
        window.contentView = root
    }

    private func label(_ text: String, role: String = "ui", bold: Bool = false, muted: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        let font = DesignMetrics.font(role)
        field.font = bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        field.textColor = muted ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        return field
    }

    private func rowLabel(_ text: String, y: CGFloat, in pane: NSView) {
        let field = label(text)
        field.alignment = .right
        field.frame = NSRect(x: 26, y: y, width: 120, height: 24)
        pane.addSubview(field)
    }

    private func buildGeneral() {
        let pane = panes[.general]!
        rowLabel(String(localized: "Appearance"), y: 397, in: pane)
        let titles: [(DisplayAppearance, String)] = [
            (.system, String(localized: "Follow System")),
            (.light, String(localized: "Light")),
            (.dark, String(localized: "Dark"))
        ]
        var x: CGFloat = 162
        for (index, item) in titles.enumerated() {
            let button = NSButton(title: item.1, target: self, action: #selector(changeAppearance(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.setButtonType(.pushOnPushOff)
            button.font = DesignMetrics.font("uiSmall")
            button.setAccessibilityRole(.radioButton)
            let width = max(62, button.intrinsicContentSize.width + 14)
            button.frame = NSRect(x: x, y: 397, width: width, height: 24)
            button.setAccessibilityIdentifier("settings.appearance.\(item.0.rawValue)")
            pane.addSubview(button)
            appearanceButtons[item.0] = button
            x += width + 2
        }
        rowLabel(String(localized: "Image Tools"), y: 350, in: pane)
        toolsButton = NSButton(checkboxWithTitle: String(localized: "Always Show Image Tools"),
                               target: self, action: #selector(changeTools(_:)))
        toolsButton.font = DesignMetrics.font("ui")
        toolsButton.frame = NSRect(x: 162, y: 350, width: toolsButton.intrinsicContentSize.width, height: 24)
        toolsButton.setAccessibilityIdentifier("settings.always-show-tools")
        pane.addSubview(toolsButton)
        let hint = label(String(localized: "When off, tools hide after inactivity. Move the pointer to an edge or press Tab to show them."), role: "uiSmall", muted: true)
        hint.frame = NSRect(x: 162, y: 310, width: 390, height: 36)
        pane.addSubview(hint)
        rowLabel(String(localized: "Language"), y: 275, in: pane)
        let language = label(String(localized: "Follows the system language (Chinese / English). Set a language for picsee in System Settings → General → Language & Region."), role: "uiSmall", muted: true)
        language.frame = NSRect(x: 162, y: 232, width: 390, height: 67)
        language.setAccessibilityIdentifier("settings.language-note")
        pane.addSubview(language)
    }

    private func future(_ control: NSControl, id: String, title: String) {
        control.font = DesignMetrics.font("ui")
        control.isEnabled = false
        control.setAccessibilityIdentifier(id)
        control.setAccessibilityLabel(title + ", " + String(localized: "Coming Soon"))
    }

    private func soon(_ x: CGFloat, _ y: CGFloat, in pane: NSView) {
        let badge = label(String(localized: "Coming Soon"), role: "uiSmall", muted: true)
        badge.frame = NSRect(x: x, y: y, width: 100, height: 24)
        pane.addSubview(badge)
    }

    private func buildDisplay() {
        let pane = panes[.display]!
        rowLabel(String(localized: "Thumbnail Size"), y: 397, in: pane)
        let size = NSSlider(value: 220, minValue: 140, maxValue: 280, target: nil, action: nil)
        size.frame = NSRect(x: 162, y: 397, width: 220, height: 24)
        future(size, id: "settings.display.size", title: String(localized: "Thumbnail Size"))
        pane.addSubview(size)
        soon(390, 397, in: pane)
        rowLabel(String(localized: "Show File Names"), y: 352, in: pane)
        let names = NSButton(checkboxWithTitle: String(localized: "Show names below thumbnails"), target: nil, action: nil)
        names.font = DesignMetrics.font("ui")
        names.frame = NSRect(x: 162, y: 352, width: names.intrinsicContentSize.width, height: 24)
        future(names, id: "settings.display.names", title: String(localized: "Show File Names"))
        pane.addSubview(names)
        soon(450, 352, in: pane)
        rowLabel(String(localized: "Thumbnails"), y: 307, in: pane)
        var fitX: CGFloat = 162
        for (index, title) in [String(localized: "Fill and Crop"), String(localized: "Fit Entire Image")].enumerated() {
            let button = NSButton(title: title, target: nil, action: nil)
            button.font = DesignMetrics.font("ui")
            let width = button.intrinsicContentSize.width
            button.frame = NSRect(x: fitX, y: 307, width: width, height: 24)
            future(button, id: "settings.display.fit.\(index)", title: title)
            pane.addSubview(button)
            fitX += width + 8
        }
        soon(fitX, 307, in: pane)
        let note = label(String(localized: "These are the same preferences as the grid footer Display panel; changes will sync immediately."), role: "uiSmall", muted: true)
        note.frame = NSRect(x: 162, y: 260, width: 390, height: 40)
        pane.addSubview(note)
    }

    private func buildCache() {
        let pane = panes[.cache]!
        rowLabel(String(localized: "Thumbnail Cache"), y: 397, in: pane)
        cacheSize = label(String(localized: "Unknown"), role: "uiSmall")
        cacheSize.font = DesignMetrics.font("uiSmall", monospaced: true)
        cacheSize.frame = NSRect(x: 162, y: 397, width: 350, height: 24)
        cacheSize.setAccessibilityIdentifier("settings.cache.size")
        pane.addSubview(cacheSize)
        cacheClear = NSButton(title: String(localized: "Clear Cache…"), target: self, action: #selector(requestClear(_:)))
        cacheClear.font = DesignMetrics.font("ui")
        cacheClear.frame = NSRect(x: 162, y: 353, width: cacheClear.intrinsicContentSize.width, height: 26)
        cacheClear.setAccessibilityIdentifier("settings.cache.clear")
        pane.addSubview(cacheClear)
        let hint = label(String(localized: "Only thumbnails created by picsee are deleted. Your images are untouched. Confirm before clearing; thumbnails are rebuilt while browsing."), role: "uiSmall", muted: true)
        hint.frame = NSRect(x: 162, y: 302, width: 390, height: 45)
        pane.addSubview(hint)
        cacheDiagnostic = label("", role: "uiSmall", muted: true)
        cacheDiagnostic.frame = NSRect(x: 162, y: 274, width: 390, height: 24)
        cacheDiagnostic.setAccessibilityIdentifier("settings.cache.diagnostic")
        pane.addSubview(cacheDiagnostic)
    }

    private static var versionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? String(localized: "Unknown")
        let build = info["CFBundleVersion"] as? String ?? String(localized: "Unknown")
        return String(format: String(localized: "%@ (build %@)"), version, build)
    }

    private func buildUpdates() {
        let pane = panes[.update]!
        rowLabel(String(localized: "Current Version"), y: 397, in: pane)
        let version = label(Self.versionDescription, role: "uiSmall")
        version.frame = NSRect(x: 162, y: 397, width: 350, height: 24)
        pane.addSubview(version)
        rowLabel(String(localized: "Auto Check"), y: 352, in: pane)
        let automatic = NSButton(checkboxWithTitle: String(localized: "Check for updates automatically"), target: nil, action: nil)
        automatic.font = DesignMetrics.font("ui")
        automatic.frame = NSRect(x: 162, y: 352, width: automatic.intrinsicContentSize.width, height: 24)
        future(automatic, id: "settings.update.automatic", title: automatic.title)
        pane.addSubview(automatic)
        soon(450, 352, in: pane)
        let privacy = label(String(localized: "picsee contacts GitHub only to check for updates and sends no system information."), role: "uiSmall", muted: true)
        privacy.frame = NSRect(x: 162, y: 310, width: 390, height: 36)
        pane.addSubview(privacy)
        let check = NSButton(title: String(localized: "Check Now"), target: nil, action: nil)
        check.font = DesignMetrics.font("ui")
        check.frame = NSRect(x: 162, y: 275, width: check.intrinsicContentSize.width, height: 26)
        future(check, id: "settings.update.now", title: check.title)
        pane.addSubview(check)
        soon(290, 275, in: pane)
        let last = label(String(localized: "Last checked: Unknown"), role: "uiSmall", muted: true)
        last.frame = NSRect(x: 162, y: 247, width: 390, height: 24)
        pane.addSubview(last)
    }

    private func buildAbout() {
        let pane = panes[.about]!
        let icon = NSImageView(frame: NSRect(x: 26, y: 362, width: 64, height: 64))
        icon.image = NSImage(named: NSImage.applicationIconName)
        pane.addSubview(icon)
        let name = label("picsee", role: "title", bold: true)
        name.frame = NSRect(x: 108, y: 406, width: 380, height: 20)
        pane.addSubview(name)
        let version = label(String(localized: "Version") + " " + Self.versionDescription, role: "uiSmall", muted: true)
        version.frame = NSRect(x: 108, y: 383, width: 390, height: 20)
        pane.addSubview(version)
        let privacy = label(String(localized: "A macOS image viewer for files on your disk. picsee collects no data and uploads no images; the sandbox reads only folders you authorize."), role: "uiSmall", muted: true)
        privacy.frame = NSRect(x: 108, y: 327, width: 440, height: 54)
        pane.addSubview(privacy)
        var linkX: CGFloat = 108
        for (index, title) in [String(localized: "Report a Problem…"), String(localized: "Privacy Note"), String(localized: "Source Code")].enumerated() {
            let button = NSButton(title: title, target: nil, action: nil)
            button.font = DesignMetrics.font("ui")
            let width = button.intrinsicContentSize.width
            button.frame = NSRect(x: linkX, y: 291, width: width, height: 26)
            future(button, id: "settings.about.link.\(index)", title: title)
            pane.addSubview(button)
            linkX += width + 8
        }
        soon(linkX, 291, in: pane)
        let licences = label(String(localized: "picsee is released under the MIT License.\nThird party: Sparkle (MIT) · Welcome sample images from Unsplash (Unsplash License)."), role: "uiSmall", muted: true)
        licences.frame = NSRect(x: 108, y: 235, width: 440, height: 52)
        pane.addSubview(licences)
    }

    private func renderCache() {
        if model.isMeasuring { cacheSize.stringValue = String(localized: "Measuring…") }
        else if let bytes = model.sizeBytes { cacheSize.stringValue = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        else { cacheSize.stringValue = String(localized: "Unknown") }
        cacheDiagnostic.stringValue = model.diagnostic.map { String(localized: String.LocalizationValue($0)) } ?? ""
        cacheClear.isEnabled = !model.isMeasuring && !model.isClearing
    }

    private func showCacheBusy() {
        cacheSize.stringValue = String(localized: "Measuring…")
        cacheClear.isEnabled = false
    }

    private func refreshCache() {
        showCacheBusy()
        Task {
            showCacheBusy()
            await model.refresh()
            renderCache()
        }
    }

    private static func presentClearConfirmation(window: NSWindow, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Clear Thumbnail Cache?")
        alert.informativeText = String(localized: "This deletes picsee thumbnails only. Your images are untouched.")
        alert.addButton(withTitle: String(localized: "Clear Cache"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { response in completion(response == .alertFirstButtonReturn) }
    }

    @objc private func requestClear(_ sender: NSButton) {
        confirmClear(window) { [weak self] confirmed in
            guard confirmed, let self else { return }
            self.showCacheBusy()
            Task {
                self.showCacheBusy()
                await self.model.clear()
                self.renderCache()
            }
        }
    }

    @objc private func selectSidebar(_ sender: NSButton) {
        select(SettingsSection.allCases[sender.tag])
    }

    @objc private func changeAppearance(_ sender: NSButton) {
        let appearance: DisplayAppearance = [.system, .light, .dark][sender.tag]
        preferencesStore.value.appearance = appearance
        preferencesDidChange(preferencesStore.value)
    }

    @objc private func changeTools(_ sender: NSButton) {
        preferencesStore.value.alwaysShowTools = sender.state == .on
    }
}

private final class SettingsPanelNativeWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

private final class SettingsSidebarButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        if state == .on {
            DesignColor.selectionFill.nsColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class SettingsSurfaceView: NSView {
    enum Surface { case panel, sidebar }
    let surface: Surface
    init(frame: NSRect, surface: Surface) { self.surface = surface; super.init(frame: frame) }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = surface == .sidebar
            ? DesignColor.sidebarBackground.nsColor : DesignColor.popoverBackground.nsColor
        color.setFill()
        dirtyRect.fill()
        if surface == .sidebar {
            DesignColor.divider.nsColor.setFill()
            NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
