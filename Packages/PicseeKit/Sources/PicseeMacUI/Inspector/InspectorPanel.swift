import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PicseeApplication
import PicseeCore

public enum InspectorPanelLayout {
    public static func width(for windowWidth: CGFloat) -> CGFloat {
        if windowWidth <= 720 { return 220 }
        if windowWidth <= 1050 { return 195 }
        return 220
    }
    public static func overlaysContent(at windowWidth: CGFloat) -> Bool { windowWidth <= 720 }
    public static func labelWidth(_ label: String) -> CGFloat {
        max(48, ceil((label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width))
    }
    public static func frame(in bounds: NSRect, grid: Bool) -> NSRect {
        let width = min(Self.width(for: bounds.width), bounds.width)
        if overlaysContent(at: bounds.width) {
            return NSRect(x: bounds.maxX - width, y: bounds.minY + 38,
                          width: width, height: max(0, bounds.height - 125))
        }
        return NSRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height)
    }
}

/// A single Inspector metadata row shared by the English and Chinese panels.
struct InspectorFieldRow: View {
    let label: String
    let value: String
    let id: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(label).foregroundStyle(DesignColor.textSecondary.color)
                .frame(width: InspectorPanelLayout.labelWidth(label), alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DesignColor.textPrimary.color).multilineTextAlignment(.trailing)
                .accessibilityIdentifier("inspector.\(id)")
        }
        .font(.system(size: 12))
    }
}

/// Pages 16/34 share the same hierarchy; DesignColor resolves the window appearance.
public struct InspectorPanel: View {
    @Bindable public var model: InspectorModel
    public let session: ViewerSession
    public let close: () -> Void
    public let restoreCanvasFocus: () -> Void
    public let updateFocus: (FocusContext) -> Void

    public init(model: InspectorModel, session: ViewerSession, close: @escaping () -> Void,
                restoreCanvasFocus: @escaping () -> Void, updateFocus: @escaping (FocusContext) -> Void) {
        self.model = model; self.session = session; self.close = close
        self.restoreCanvasFocus = restoreCanvasFocus; self.updateFocus = updateFocus
    }

    private var unavailable: String {
        switch model.value {
        case .loading: String(localized: "Loading…")
        case .noPermission: String(localized: "No Permission")
        case .unreadable: String(localized: "Unreadable")
        case .unknown, .known: String(localized: "Unknown")
        }
    }
    private func field(_ value: String?) -> String { value ?? unavailable }
    private var metadata: InspectorMetadata? {
        if case .known(let value) = model.value { value } else { nil }
    }
    static func typeName(_ identifier: String) -> String {
        if let ext = UTType(identifier)?.preferredFilenameExtension { return ext.uppercased() }
        return identifier
    }
    private func row(_ label: String, _ value: String, id: String) -> some View {
        InspectorFieldRow(label: label, value: value, id: id)
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Image Information").font(.system(size: 13, weight: .medium))
                Spacer()
                InspectorCloseControl(focused: session.inspectorFocus.focus == .textInput || session.inspectorFocus.focus == .panel,
                    close: close, updateFocus: updateFocus, restoreCanvasFocus: restoreCanvasFocus)
                    .frame(width: 24, height: 24)
            }
            .frame(height: 36)
            .padding(.bottom, 12)
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(DesignColor.sidebarBackground.color)
                if let data = metadata?.thumbnailData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .accessibilityLabel(Text("Image Preview"))
                } else {
                    Image(systemName: "photo").foregroundStyle(DesignColor.textSecondary.color)
                }
            }
            .frame(height: 120)
            .accessibilityIdentifier("inspector.preview")
            Text(verbatim: model.name ?? unavailable)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignColor.textPrimary.color)
                .lineLimit(2).truncationMode(.middle)
                .padding(.top, 14)
                .accessibilityIdentifier("inspector.item-name")
            VStack(spacing: 13) {
                row(String(localized: "Dimensions"), field(metadata.flatMap { value in
                    guard let w = value.pixelWidth, let h = value.pixelHeight else { return nil }
                    return "\(w) × \(h)"
                }), id: "dimensions")
                row(String(localized: "Type"), field(metadata?.typeIdentifier.map(Self.typeName)), id: "type")
                row(String(localized: "Created"), field(metadata?.creationDate?.formatted(date: .numeric, time: .omitted)), id: "created")
                row(String(localized: "Modified"), field(metadata?.modificationDate?.formatted(date: .numeric, time: .omitted)), id: "modified")
                row(String(localized: "Size"), field(metadata?.byteSize.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                }), id: "size")
            }
            .padding(.top, 19)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(minWidth: 0, idealWidth: 220, maxWidth: .infinity)
        .background(DesignColor.canvasBackground.color)
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 8)
        .overlay(alignment: .leading) { Rectangle().fill(DesignColor.divider.color).frame(width: 1) }
    }
}

private final class InspectorFocusButton: NSButton {
    var onFocus: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}

private struct InspectorCloseControl: NSViewRepresentable {
    let focused: Bool
    let close: () -> Void
    let updateFocus: (FocusContext) -> Void
    let restoreCanvasFocus: () -> Void

    final class Coordinator: NSObject {
        var close: () -> Void = {}
        @objc func performClose() { close() }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> InspectorFocusButton {
        let button = InspectorFocusButton()
        button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        button.isBordered = false
        button.focusRingType = .exterior
        button.setAccessibilityLabel(String(localized: "Close Inspector"))
        button.setAccessibilityIdentifier("inspector.close")
        button.target = context.coordinator
        button.action = #selector(Coordinator.performClose)
        return button
    }
    func updateNSView(_ button: InspectorFocusButton, context: Context) {
        context.coordinator.close = close
        button.onFocus = { updateFocus(.panel) }
        if focused, button.window?.firstResponder !== button {
            button.window?.makeFirstResponder(button)
        } else if !focused, button.window?.firstResponder === button {
            restoreCanvasFocus()
        }
    }
}
