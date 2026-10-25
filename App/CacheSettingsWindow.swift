import AppKit
import SwiftUI
import PicseeInfrastructure
import PicseeMacUI

@MainActor
final class CacheSettingsWindow {
    private let window: NSWindow
    private let appearanceAdapter: WindowAppearanceAdapter
    private let model: CacheSettingsModel

    init(cache: ThumbnailDiskCache, appearanceAdapter: WindowAppearanceAdapter) {
        self.appearanceAdapter = appearanceAdapter
        model = CacheSettingsModel(cache: cache)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 190),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = String(localized: "Settings")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CacheSettingsPane(model: model))
        window.center()
    }

    func show() {
        Task { await model.refresh() }
        appearanceAdapter.register(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct CacheSettingsPane: View {
    let model: CacheSettingsModel

    var body: some View {
        Form {
            LabeledContent(String(localized: "Thumbnail Cache")) {
                Text(sizeLabel).accessibilityIdentifier("settings.cache.size")
            }
            if let diagnostic = model.diagnostic {
                Text(String(localized: "Cache operation failed"))
                    .foregroundStyle(.secondary)
                    .help(diagnostic)
                    .accessibilityIdentifier("settings.cache.diagnostic")
            }
            HStack {
                Spacer()
                Button(role: .destructive) {
                    Task { await model.clear() }
                } label: {
                    Text(String(localized: "Clear Cache"))
                }
                .disabled(model.isMeasuring)
                .accessibilityIdentifier("settings.cache.clear")
            }
        }
        .padding(24)
        .frame(width: 460, height: 190)
        .task { await model.refresh() }
    }

    private var sizeLabel: String {
        if model.isMeasuring { return String(localized: "Measuring…") }
        guard let bytes = model.sizeBytes else { return String(localized: "Unknown") }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
