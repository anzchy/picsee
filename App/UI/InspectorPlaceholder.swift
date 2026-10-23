import SwiftUI
import PicseeCore
import PicseeApplication

@MainActor @Observable
final class InspectorModel {
    let session: ViewerSession
    var state: InspectorFocus { session.inspectorFocus }
    init(session: ViewerSession) { self.session = session }
    var hasImage = false
}

struct InspectorPlaceholder: View {
    @Bindable var model: InspectorModel
    let route: (CommandID) -> Void
    let restoreCanvasFocus: () -> Void
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector Placeholder").font(.headline)
            Text(verbatim: model.session.imageLoader.presented?.name ?? "")
                .accessibilityIdentifier("inspector.item-name")
            TextField("Focus test (not saved)", text: $text)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("inspector.focus-test")
                .focused($fieldFocused)
            ForEach([CommandID.previous, .next, .fit, .actualPixels, .zoomIn, .zoomOut, .inspector], id: \.self) { id in
                Button(id == .inspector ? String(localized: "Hide Inspector") : id.menuTitle) { route(id) }
                    .accessibilityIdentifier("command.\(id.rawValue).button")
                    .disabled(id != .inspector && !model.hasImage)
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 240)
        .background(.background)
        .onChange(of: model.state.focus) { _, focus in fieldFocused = focus == .textInput }
        .onChange(of: fieldFocused) { _, focused in
            if focused { model.session.updateFocus(.textInput) }
            else if model.state.focus == .canvas { restoreCanvasFocus() }
            else if model.state.focus == .textInput { model.session.updateFocus(.panel) }
        }
    }
}
