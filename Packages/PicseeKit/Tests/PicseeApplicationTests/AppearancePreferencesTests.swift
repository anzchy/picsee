import Foundation
import Testing
import PicseeApplication

@Test func appearancePreferencesDefaultIsSystem() {
    let value = DisplayPreferences()
    #expect(value.appearance == .system)
    #expect(value.alwaysShowTools == false)
    #expect(value.filmstripExpanded == false)
}

@Test func appearancePreferencesLiteralJSONAndFullDomainRoundTrip() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let cases: [(DisplayAppearance, Bool, Bool, String)] = [
        (.system, false, false, #"{"alwaysShowTools":false,"appearance":"system","filmstripExpanded":false}"#),
        (.system, false, true, #"{"alwaysShowTools":false,"appearance":"system","filmstripExpanded":true}"#),
        (.system, true, false, #"{"alwaysShowTools":true,"appearance":"system","filmstripExpanded":false}"#),
        (.system, true, true, #"{"alwaysShowTools":true,"appearance":"system","filmstripExpanded":true}"#),
        (.light, false, false, #"{"alwaysShowTools":false,"appearance":"light","filmstripExpanded":false}"#),
        (.light, false, true, #"{"alwaysShowTools":false,"appearance":"light","filmstripExpanded":true}"#),
        (.light, true, false, #"{"alwaysShowTools":true,"appearance":"light","filmstripExpanded":false}"#),
        (.light, true, true, #"{"alwaysShowTools":true,"appearance":"light","filmstripExpanded":true}"#),
        (.dark, false, false, #"{"alwaysShowTools":false,"appearance":"dark","filmstripExpanded":false}"#),
        (.dark, false, true, #"{"alwaysShowTools":false,"appearance":"dark","filmstripExpanded":true}"#),
        (.dark, true, false, #"{"alwaysShowTools":true,"appearance":"dark","filmstripExpanded":false}"#),
        (.dark, true, true, #"{"alwaysShowTools":true,"appearance":"dark","filmstripExpanded":true}"#),
    ]
    for (appearance, tools, filmstrip, literal) in cases {
        let value = DisplayPreferences(alwaysShowTools: tools, filmstripExpanded: filmstrip, appearance: appearance)
        #expect(value.appearance == appearance)
        let data = try encoder.encode(value)
        #expect(String(decoding: data, as: UTF8.self) == literal)
        #expect(try JSONDecoder().decode(DisplayPreferences.self, from: data) == value)
        #expect(try JSONDecoder().decode(DisplayPreferences.self, from: Data(literal.utf8)) == value)
    }
}

@Test func appearancePreferencesLegacyUnknownAndExtraFields() {
    let legacy = #"{"alwaysShowTools":true,"filmstripExpanded":false}"#
    let unknown = #"{"alwaysShowTools":true,"appearance":"sepia","filmstripExpanded":false,"future":42}"#
    let extra = #"{"alwaysShowTools":false,"appearance":"light","filmstripExpanded":true,"search":"ignored"}"#
    let decoder = JSONDecoder()
    #expect((try? decoder.decode(DisplayPreferences.self, from: Data(legacy.utf8))) ==
        DisplayPreferences(alwaysShowTools: true, filmstripExpanded: false, appearance: .system))
    #expect((try? decoder.decode(DisplayPreferences.self, from: Data(unknown.utf8))) ==
        DisplayPreferences(alwaysShowTools: true, filmstripExpanded: false, appearance: .system))
    #expect((try? decoder.decode(DisplayPreferences.self, from: Data(extra.utf8))) ==
        DisplayPreferences(alwaysShowTools: false, filmstripExpanded: true, appearance: .light))
}
