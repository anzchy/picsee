import AppKit
import CryptoKit
import Testing
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

private struct Issue221AboutViews {
    let pane: NSView
    let icon: NSImageView
    let name: NSTextField
    let version: NSTextField
    let privacy: NSTextField
    let links: [NSButton]
    let licences: NSTextField
}

@MainActor private func issue221Panel(
    info: [String: Any]? = nil,
    openURL: @escaping (URL) -> Void = { _ in }
) -> SettingsPanelWindow {
    let preferences = InMemoryDisplayPreferencesStore()
    return SettingsPanelWindow(
        cache: ThumbnailDiskCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        appearanceAdapter: WindowAppearanceAdapter(preferencesStore: preferences),
        preferencesStore: preferences,
        defaults: UserDefaults(suiteName: "issue221-about-\(UUID().uuidString)")!,
        openURL: openURL,
        aboutInfoDictionary: info)
}

@MainActor private func issue221View(_ id: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == id { return root }
    for child in root.subviews {
        if let found = issue221View(id, in: child) { return found }
    }
    return nil
}

@MainActor private func issue221AboutViews(in panel: SettingsPanelWindow) throws -> Issue221AboutViews {
    panel.select(.about)
    let root = try #require(panel.window.contentView)
    root.layoutSubtreeIfNeeded()
    let pane = try #require(issue221View("settings.pane.about", in: root))
    pane.layoutSubtreeIfNeeded()
    let fields = pane.subviews.compactMap { $0 as? NSTextField }
    let icon = try #require(pane.subviews.compactMap { $0 as? NSImageView }.first)
    let name = try #require(fields.first { $0.stringValue == "picsee" })
    let version = try #require(fields.first { $0.stringValue.hasPrefix(String(localized: "Version") + " ") })
    let privacyKey = "A macOS image viewer for files on your disk. picsee collects no data and uploads no images; the sandbox reads only folders you authorize."
    let privacy = try #require(fields.first { $0.stringValue == String(localized: String.LocalizationValue(privacyKey)) })
    let licenceKey = "picsee is released under the MIT License.\nThird party: Sparkle (MIT) · Welcome sample images from Unsplash (Unsplash License)."
    let licences = try #require(fields.first { $0.stringValue == String(localized: String.LocalizationValue(licenceKey)) })
    let links = try (0...2).map { try #require(issue221View("settings.about.link.\($0)", in: pane) as? NSButton) }
    return Issue221AboutViews(pane: pane, icon: icon, name: name, version: version,
                              privacy: privacy, links: links, licences: licences)
}

private func issue221CatalogValue(_ key: String, _ language: String) throws -> String {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Resources/Localizable.xcstrings")
    let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: Any])
    let entry = try #require(strings[key] as? [String: Any])
    let localizations = try #require(entry["localizations"] as? [String: Any])
    let localized = try #require(localizations[language] as? [String: Any])
    let unit = try #require(localized["stringUnit"] as? [String: Any])
    return try #require(unit["value"] as? String)
}

private struct PinnedDesign {
    struct ParseError: Swift.Error {
        let message: String
    }

    let html: String
    let appearance: String

    static func page(_ name: String, appearance: String = "light") throws -> Self {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("design/prototypes/picsee-browser/states")
        let manifestData = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let states = try #require(manifest["states"] as? [[String: Any]])
        let entry = try #require(states.first { $0["name"] as? String == name })
        let file = try #require(entry["file"] as? String)
        let data = try Data(contentsOf: directory.appendingPathComponent(file))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == entry["sha256"] as? String)
        let source = try #require(String(data: data, encoding: .utf8))
        let styleRegex = try NSRegularExpression(pattern: "(?s)<style\\b[^>]*>(.*?)</style>")
        let sourceNSString = source as NSString
        let css = styleRegex.matches(in: source, range: NSRange(location: 0, length: sourceNSString.length))
            .map { sourceNSString.substring(with: $0.range(at: 1)) }.joined(separator: "\n")
        return Self(html: css, appearance: appearance)
    }

    func length(_ selector: String, _ property: String) throws -> Double {
        let value = try raw(selector, property)
        guard let number = Double(value.replacingOccurrences(of: "px", with: "")) else {
            throw ParseError(message: "\(selector) \(property) is not a length: \(value)")
        }
        return number
    }

    func marginTop(_ selector: String) throws -> Double {
        let margin = try raw(selector, "margin").split(separator: " ")
        guard let first = margin.first, let number = Double(first.replacingOccurrences(of: "px", with: "")) else {
            throw ParseError(message: "\(selector) has no top margin")
        }
        return number
    }

    func horizontalPadding(_ selector: String) throws -> Double {
        let padding = try raw(selector, "padding").split(separator: " ")
        guard padding.count > 1, let number = Double(padding[1].replacingOccurrences(of: "px", with: "")) else {
            throw ParseError(message: "\(selector) has no horizontal padding")
        }
        return number
    }

    func fontWeight(_ selector: String) throws -> Int {
        guard let weight = Int(try raw(selector, "font-weight")) else {
            throw ParseError(message: "\(selector) has no numeric font weight")
        }
        return weight
    }

    func color(_ selector: String, _ property: String = "color") throws -> [CGFloat] {
        let hex = try raw(selector, property)
        guard hex.hasPrefix("#"), hex.count == 7, let number = Int(hex.dropFirst(), radix: 16) else {
            throw ParseError(message: "\(selector) \(property) is not a six-digit sRGB color: \(hex)")
        }
        return [CGFloat((number >> 16) & 255) / 255,
                CGFloat((number >> 8) & 255) / 255,
                CGFloat(number & 255) / 255]
    }

    private func raw(_ selector: String, _ property: String) throws -> String {
        guard let declaration = try self.declaration(selector, property) else {
            throw ParseError(message: "Missing \(selector) \(property)")
        }
        if declaration.hasPrefix("var("), declaration.hasSuffix(")") {
            let token = String(declaration.dropFirst(4).dropLast())
            let themed = try self.declaration(appearance == "dark" ? ".theme-dark" : ".theme-light", token)
            let fallback = try self.declaration(":root", token)
            guard let value = themed ?? fallback else { throw ParseError(message: "Missing design token \(token)") }
            return value
        }
        return declaration
    }

    private func declaration(_ selector: String, _ property: String) throws -> String? {
        let regex = try NSRegularExpression(pattern: "([^{}]+)\\{([^{}]*)\\}")
        let ns = html as NSString
        var result: String?
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let selectors = ns.substring(with: match.range(at: 1)).split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard selectors.contains(selector) else { continue }
            for declaration in ns.substring(with: match.range(at: 2)).split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == property else { continue }
                result = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }
}

@MainActor @Test(.timeLimit(.minutes(3))) func issue221AboutLinksOpenDestinationsAndStayFocusable() throws {
    var openedURLs: [URL] = []
    let panel = issue221Panel(openURL: { openedURLs.append($0) })
    defer { panel.window.close() }
    let views = try issue221AboutViews(in: panel)
    let expectations: [(EntryPoint, URL)] = [
        (.reportIssue, URL(string: "https://github.com/anzchy/picsee/issues/new?template=bug_report.yml")!),
        (.settingsAboutPrivacyNote, URL(string: "https://github.com/anzchy/picsee#%E9%9A%90%E7%A7%81")!),
        (.settingsAboutSourceCode, URL(string: "https://github.com/anzchy/picsee")!),
    ]
    for (index, expected) in expectations.enumerated() {
        let button = views.links[index]
        #expect(button.isEnabled, "settings.about.link.\(index) must be enabled")
        #expect(button.acceptsFirstResponder, "settings.about.link.\(index) must be in the tab order")
        #expect(!button.refusesFirstResponder)
        #expect(button.accessibilityLabel()?.contains(String(localized: "Coming Soon")) == false)
        #expect(panel.entryPoint(for: button) == expected.0)
        #expect(expected.0.state == .implemented)
        button.performClick(nil)
    }
    #expect(openedURLs == expectations.map { $0.1 })
    #expect(!views.pane.subviews.compactMap { $0 as? NSTextField }
        .contains { $0.stringValue == String(localized: "Coming Soon") })
}

@MainActor @Test(.timeLimit(.minutes(3))) func issue221AboutVersionAndBuildUseInjectedBundleInfo() throws {
    let panel = issue221Panel(info: ["CFBundleShortVersionString": "9.8.7", "CFBundleVersion": "654"])
    defer { panel.window.close() }
    let views = try issue221AboutViews(in: panel)
    let description = String(format: String(localized: "%@ (build %@)"), "9.8.7", "654")
    #expect(views.version.stringValue == String(localized: "Version") + " " + description)
}

@MainActor @Test(.timeLimit(.minutes(3))) func issue221AboutLicenceTextMatchesPinnedEnglishAndChinese() throws {
    let key = "picsee is released under the MIT License.\nThird party: Sparkle (MIT) · Welcome sample images from Unsplash (Unsplash License)."
    let english = "picsee is released under the MIT License.\nThird party: Sparkle (MIT) · Welcome sample images from Unsplash (Unsplash License)."
    let chinese = "picsee 以 MIT 许可发布\n第三方：Sparkle（MIT）· 首次打开页样图来自 Unsplash（Unsplash License）"
    #expect(try issue221CatalogValue(key, "en") == english)
    #expect(try issue221CatalogValue(key, "zh-Hans") == chinese)
    let panel = issue221Panel()
    defer { panel.window.close() }
    #expect(try issue221AboutViews(in: panel).licences.stringValue == english)
}

@MainActor @Test(.timeLimit(.minutes(3))) func issue221PinnedAboutIconTypographyAndParagraphRenderedFrames() throws {
    let design = try PinnedDesign.page("settings")
    let panel = issue221Panel()
    defer { panel.window.close() }
    let views = try issue221AboutViews(in: panel)
    let iconWidth = try design.length(".app-icon", "width")
    let iconHeight = try design.length(".app-icon", "height")
    let aboutGap = try design.length(".about", "gap")
    let titleSize = try design.length(".app-name", "font-size")
    let paragraphMargin = try design.marginTop(".about-text p")
    let linksMargin = try design.length(".links", "margin-top")
    #expect(abs(views.icon.frame.width - iconWidth) < 0.5, ".app-icon width")
    #expect(abs(views.icon.frame.height - iconHeight) < 0.5, ".app-icon height")
    #expect(abs(views.name.frame.minX - views.icon.frame.maxX - aboutGap) < 0.5, ".about gap")
    #expect(abs((views.name.font?.pointSize ?? 0) - titleSize) < 0.5, ".app-name font-size")
    let traits = NSFontManager.shared.traits(of: try #require(views.name.font))
    #expect(try design.fontWeight(".app-name") >= 600 && traits.contains(.boldFontMask), ".app-name font-weight")
    #expect(abs(views.version.frame.minY - views.privacy.frame.maxY - paragraphMargin) < 0.5,
            ".about-text p margin-top")
    #expect(abs(views.privacy.frame.minY - views.links[0].frame.maxY - linksMargin) < 0.5,
            ".links margin-top")
}

@MainActor @Test(.timeLimit(.minutes(3))) func issue221PinnedAboutLinkSpacingAndLicenceWidthRenderedFrames() throws {
    let design = try PinnedDesign.page("settings")
    let panel = issue221Panel()
    defer { panel.window.close() }
    let views = try issue221AboutViews(in: panel)
    let root = try #require(panel.window.contentView)
    let content = try #require(issue221View("settings.content", in: root))
    let linkGap = try design.length(".links", "gap")
    for index in 1..<views.links.count {
        #expect(abs(views.links[index].frame.minX - views.links[index - 1].frame.maxX - linkGap) < 0.5,
                ".links gap at \(index)")
    }
    let licencesMargin = try design.length(".licences", "margin-top")
    #expect(abs(views.links[0].frame.minY - views.licences.frame.maxY - licencesMargin) < 0.5,
            ".licences margin-top")
    let horizontalPadding = try design.horizontalPadding(".settings-pane")
    let iconWidth = try design.length(".app-icon", "width")
    let aboutGap = try design.length(".about", "gap")
    let expectedWidth = content.frame.width - 2 * horizontalPadding - iconWidth - aboutGap
    #expect(abs(views.licences.frame.width - expectedWidth) < 0.5, ".licences wrapping width")
}

@MainActor @Test(.timeLimit(.minutes(3))) func issue221PinnedAboutMutedColorsInLightAndDark() throws {
    let panel = issue221Panel()
    defer { panel.window.close() }
    let views = try issue221AboutViews(in: panel)
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        panel.window.appearance = NSAppearance(named: appearance)
        let expected = try PinnedDesign.page("settings", appearance: name).color(".hint")
        for field in [views.version, views.privacy, views.licences] {
            var actual: NSColor?
            field.effectiveAppearance.performAsCurrentDrawingAppearance {
                actual = field.textColor?.usingColorSpace(.sRGB)
            }
            let color = try #require(actual, ".hint muted color in \(name)")
            for (channel, value) in zip([color.redComponent, color.greenComponent, color.blueComponent], expected) {
                #expect(abs(channel - value) < 0.02, ".hint color in \(name): \(field.stringValue)")
            }
        }
    }
}

@MainActor @Test(.timeLimit(.minutes(3))) func issue221LongestAboutLabelsFitRenderedFramesInEnglishAndChinese() throws {
    let panel = issue221Panel(info: ["CFBundleShortVersionString": "9.8.7", "CFBundleVersion": "654"])
    defer { panel.window.close() }
    let views = try issue221AboutViews(in: panel)
    let textCases: [(NSTextField, String)] = [
        (views.privacy, "A macOS image viewer for files on your disk. picsee collects no data and uploads no images; the sandbox reads only folders you authorize."),
        (views.licences, "picsee is released under the MIT License.\nThird party: Sparkle (MIT) · Welcome sample images from Unsplash (Unsplash License)."),
    ]
    for (field, key) in textCases {
        for language in ["en", "zh-Hans"] {
            let value = try issue221CatalogValue(key, language)
            let text = NSAttributedString(string: value, attributes: [.font: try #require(field.font)])
            let needed = text.boundingRect(with: NSSize(width: field.frame.width, height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            #expect(needed <= field.frame.height + 2, "\(language) clipped: \(key)")
            #expect(field.lineBreakMode == .byWordWrapping)
            #expect(field.maximumNumberOfLines == 0)
        }
    }
    for (button, key) in zip(views.links, ["Report a Problem…", "Privacy Note", "Source Code"]) {
        for language in ["en", "zh-Hans"] {
            let translated = NSButton(title: try issue221CatalogValue(key, language), target: nil, action: nil)
            translated.isBordered = false
            translated.font = button.font
            #expect(translated.intrinsicContentSize.width <= button.frame.width + 1,
                    "\(language) link truncated: \(key)")
        }
    }
}
