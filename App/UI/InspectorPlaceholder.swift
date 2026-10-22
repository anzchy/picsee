import SwiftUI
import PicseeCore
import PicseeApplication

@MainActor @Observable
final class InspectorModel {
    var state = InspectorFocus()
    var hasImage = false
}

struct InspectorPlaceholder: View {
    @Bindable var model: InspectorModel
    let route: (CommandID) -> Void
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector Placeholder").font(.headline)
            TextField("Focus test (not saved)", text: $text)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("inspector.focus-test")
                .focused($fieldFocused)
            ForEach([CommandID.fit, .actualPixels, .zoomIn, .zoomOut, .inspector], id: \.self) { id in
                Button(id == .inspector ? "Hide Inspector" : id.menuTitle) { route(id) }
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
            if focused { model.state.updateFocus(.textInput) }
            else if model.state.focus == .textInput { model.state.updateFocus(.panel) }
        }
    }
}
