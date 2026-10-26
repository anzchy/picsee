import Testing
import PicseeCore
@testable import PicseeApplication

@Test func inspectorEscapePrecedesGridTextInputGuard() {
    for focus in [FocusContext.textInput, .panel] {
        #expect(InspectorEscapePolicy.handlesEscape(inspectorVisible: true,
            menuTracking: false, focus: focus, keyCode: 53))
    }
    #expect(!InspectorEscapePolicy.handlesEscape(inspectorVisible: true,
        menuTracking: true, focus: .textInput, keyCode: 53))
    #expect(!InspectorEscapePolicy.handlesEscape(inspectorVisible: false,
        menuTracking: false, focus: .textInput, keyCode: 53))
    #expect(!InspectorEscapePolicy.handlesEscape(inspectorVisible: true,
        menuTracking: false, focus: .canvas, keyCode: 53))
}
