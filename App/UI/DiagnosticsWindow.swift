import AppKit
import SwiftUI
import PicseeCore
import PicseeMacUI

/// Untested native panel (CACHE-04, a native exception: no pinned C state). The model's refresh loop runs only
/// while the panel is on screen; closing, minimising or covering it stops the loop. Shows counts and sizes only.
@MainActor
final class DiagnosticsWindow: NSObject {
    private let panel: NSPanel
    private let appearanceAdapter: WindowAppearanceAdapter
    private let model: DiagnosticsPanelModel

    init(source: any DiagnosticsProviding, appearanceAdapter: WindowAppearanceAdapter) {
        self.appearanceAdapter = appearanceAdapter
        model = DiagnosticsPanelModel(source: source)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
                        styleMask: [.titled, .closable, .miniaturizable, .utilityWindow],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = String(localized: "Diagnostics")
        panel.identifier = NSUserInterfaceItemIdentifier("diagnostics.window")
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: DiagnosticsPane(model: model))
        panel.center()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(visibilityChanged(_:)),
                           name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        center.addObserver(self, selector: #selector(willClose(_:)), name: NSWindow.willCloseNotification, object: panel)
    }

    func show() {
        appearanceAdapter.register(panel)
        panel.makeKeyAndOrderFront(nil)
        model.setVisible(true)
    }

    @objc private func visibilityChanged(_ notification: Notification) {
        model.setVisible(panel.isVisible && panel.occlusionState.contains(.visible))
    }

    @objc private func willClose(_ notification: Notification) { model.setVisible(false) }
}

private struct DiagnosticsPane: View {
    let model: DiagnosticsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.spacing[4]) {
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: DesignMetrics.spacing[1]) {
                        Text(LocalizedStringKey(section.title))
                            .font(Font(DesignMetrics.font("uiLarge")).weight(.semibold))
                            .foregroundStyle(DesignColor.textPrimary.color)
                        ForEach(section.rows) { row in
                            HStack(spacing: DesignMetrics.spacing[2]) {
                                Text(LocalizedStringKey(row.title))
                                    .foregroundStyle(DesignColor.textSecondary.color)
                                Spacer(minLength: DesignMetrics.spacing[2])
                                value(row.value)
                                    .monospacedDigit()
                                    .foregroundStyle(DesignColor.textPrimary.color)
                            }
                            .font(Font(DesignMetrics.font("ui")))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("diagnostics.\(row.id)")
                        }
                    }
                }
            }
            .padding(DesignMetrics.spacing[3])
        }
        .frame(minWidth: 300, minHeight: 360)
        .background(DesignColor.popoverBackground.color)
    }

    /// Only the Unknown marker is a localization key; counts and sizes are already formatted.
    private func value(_ text: String) -> Text {
        text == DiagnosticsPanelModel.unknown ? Text(LocalizedStringKey(text)) : Text(verbatim: text)
    }
}
