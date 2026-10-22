#if DEBUG
import SwiftUI
import PicseeMacUI

private struct PreviewReduceMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var previewReduceMotion: Bool {
        get { self[PreviewReduceMotionKey.self] }
        set { self[PreviewReduceMotionKey.self] = newValue }
    }
}

/// Native control closures need event dispatch; these preview compositions stay outside package coverage.
struct PreviewCommandStyle: ButtonStyle {
    let kind: ComponentKind; let state: ComponentState; let theme: DesignTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.previewReduceMotion) private var previewReduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let current = configuration.isPressed ? state.union(.pressed) : state
        let style = ComponentResolver.resolve(kind, state: current, theme: theme)
        configuration.label.padding(6).foregroundStyle(style.foreground.color.opacity(style.opacity))
            .background(ComponentSurface(kind: kind, state: current, theme: theme))
            .animation(.easeOut(duration: ComponentResolver.transition(reduceMotion: reduceMotion || previewReduceMotion)), value: current)
    }
}
struct IconCommandButton: View {
    let symbol: DesignSymbol; let state: ComponentState; let theme: DesignTheme; let action: () -> Void
    @State private var hover = false
    @FocusState private var focused: Bool
    var current: ComponentState { state.union(hover ? .hover : []).union(focused ? .keyboardFocused : []) }
    var body: some View {
        Button { ComponentResolver.activate(.click, state: current, action: action) } label: {
            Image(nsImage: symbol.image()).resizable().scaledToFit().frame(width: 16, height: 16)
                .frame(width: DesignMetrics.hitArea[0]-12, height: DesignMetrics.hitArea[1]-12)
        }
        .buttonStyle(PreviewCommandStyle(kind: .icon, state: current, theme: theme))
        .disabled(state.contains(.disabled)).focused($focused).onHover { hover = $0 }
        .accessibilityLabel(Text(String(localized: String.LocalizationValue(symbol.label)))).help(Text(String(localized: String.LocalizationValue(symbol.label))))
    }
}
struct ShortcutHint: View {
    let text: String
    var body: some View {
        Text(text).font(Font(DesignMetrics.font("uiSmall", monospaced: true))).padding(4)
            .background(DesignColor.hoverBackground.color, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(DesignColor.divider.color))
    }
}
struct FolderNavigationRow: View {
    let nodeID: String; let name: String; let count: Int?; let expanded: Bool
    let state: ComponentState; let theme: DesignTheme; let onSelect: () -> Void; let onExpand: () -> Void
    @State private var hover = false
    @FocusState private var focused: Bool
    var current: ComponentState { state.union(hover ? .hover : []).union(focused ? .keyboardFocused : []) }
    var body: some View {
        HStack(spacing: 4) {
            Button(expanded ? "▾" : "▸") { ComponentResolver.activate(.click, state: state, action: onExpand) }
                .accessibilityLabel(Text(expanded ? "Collapse folder" : "Expand folder"))
            Button { ComponentResolver.activate(.click, state: state, action: onSelect) } label: {
                HStack {
                    Image(nsImage: DesignSymbol.folder.image()); Text(name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let count { Text(count.formatted()).font(Font(DesignMetrics.font("uiSmall", monospaced: true))) }
                }.frame(maxWidth: .infinity, minHeight: 20)
            }.focused($focused).accessibilityLabel(name).help(name)
        }
        .buttonStyle(PreviewCommandStyle(kind: .folder, state: current, theme: theme))
        .disabled(state.contains(.disabled)).onHover { hover = $0 }.id(nodeID)
        .accessibilityAddTraits(state.contains(.selected) ? .isSelected : [])
    }
}
struct ThumbnailSelectionFrame: View {
    let filename: String; let state: ComponentState; let theme: DesignTheme; let action: () -> Void
    var body: some View {
        Button { ComponentResolver.activate(.click, state: state, action: action) } label: {
            VStack(spacing: 4) {
                // Drawn preview data, independent of image loading and file access.
                ZStack { Rectangle().fill(DesignColor.sidebarBackground.color); Image(systemName: "mountain.2").font(.system(size: 28)) }
                    .frame(width: 120, height: 64)
                    .overlay(ComponentSurface(kind: .thumbnail, state: state, theme: theme))
                Text(filename).lineLimit(1).truncationMode(.middle).frame(width: 120)
                    .background(state.contains(.selected) ? DesignColor.selectionFill.color : .clear)
            }
        }.buttonStyle(.plain).disabled(state.contains(.disabled)).help(filename).accessibilityLabel(filename)
    }
}
struct SearchFilterField: View {
    @Binding var query: String
    let resultCount: Int; let state: ComponentState; let theme: DesignTheme; let clear: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search current folder", text: $query).textFieldStyle(.roundedBorder)
                .background(ComponentSurface(kind: .search, state: state, theme: theme))
            HStack {
                Text("Filter: \(query) · \(resultCount) results").foregroundStyle(DesignColor.selectionText.color)
                Button("Clear search", action: clear)
            }.padding(4).background(DesignColor.selectionFill.color)
            if resultCount == 0 { Text("No matching images").foregroundStyle(DesignColor.textSecondary.color) }
        }.disabled(state.contains(.disabled))
    }
}
struct ScaleIndicator: View {
    let actualPixels: Bool; let action: () -> Void
    var body: some View { Button(action: action) { ShortcutHint(text: actualPixels ? "1:1 · 100%" : String(localized: "Fit window")) }.buttonStyle(.plain) }
}
struct IndeterminateProgressRow: View {
    let label: String
    var body: some View { HStack { ProgressView().controlSize(.small); Text(label) } }
}
struct ImageErrorRow: View {
    let message: String; let state: ComponentState; let retry: () -> Void
    var body: some View {
        HStack {
            Text(message).foregroundStyle(DesignColor.errorText.color)
            Button("Retry") { ComponentResolver.activate(.click, state: state, action: retry) }
                .disabled(state.contains(.disabled))
        }
    }
}
struct ImageStatusCount: View {
    let count: Int
    var body: some View { Text("\(count) images").font(Font(DesignMetrics.font("uiSmall", monospaced: true))).foregroundStyle(DesignColor.textSecondary.color) }
}
#endif
