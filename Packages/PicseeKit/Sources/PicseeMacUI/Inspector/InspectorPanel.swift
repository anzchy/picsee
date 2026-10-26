import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PicseeApplication
import PicseeCore

public enum InspectorPanelLayout {
    public static func frame(in bounds: NSRect, grid: Bool) -> NSRect {
        let footer: CGFloat = grid ? 40 : 0
        let title: CGFloat = grid ? 28 : 0
        return NSRect(x: bounds.maxX - 220, y: bounds.minY + footer,
                      width: 220, height: max(0, bounds.height - footer - title))
    }
}

/// Pages 16/34 share the same hierarchy; DesignColor resolves the window appearance.
public struct InspectorPanel: View {
    @Bindable public var model: InspectorModel
    public let session: ViewerSession
    public let close: () -> Void
    public let restoreCanvasFocus: () -> Void
    public let updateFocus: (FocusContext) -> Void
    @FocusState private var closeFocused: Bool

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
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(label).foregroundStyle(DesignColor.textSecondary.color).frame(width: 48, alignment: .leading)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DesignColor.textPrimary.color).multilineTextAlignment(.trailing)
                .accessibilityIdentifier("inspector.\(id)")
        }
        .font(.system(size: 12))
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Image Information").font(.system(size: 13, weight: .medium))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 12)) }
                    .buttonStyle(.plain).frame(width: 24, height: 24)
                    .accessibilityLabel(Text("Close Inspector"))
                    .accessibilityIdentifier("inspector.close")
                    .focused($closeFocused)
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
        .padding(.bottom, 18)
        .frame(width: 220)
        .background(DesignColor.canvasBackground.color)
        .overlay(alignment: .leading) { Rectangle().fill(DesignColor.divider.color).frame(width: 1) }
        .onChange(of: session.inspectorFocus.focus) { _, current in closeFocused = current == .textInput || current == .panel }
        .onChange(of: closeFocused) { _, focused in
            if focused { updateFocus(.panel) }
            else if session.inspectorFocus.focus == .canvas { restoreCanvasFocus() }
        }
    }
}
