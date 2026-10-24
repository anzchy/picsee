import Foundation
import Testing
import PicseeCore
@testable import PicseeApplication

@Test func folderMenuPolicyUsesActiveWindowConditionsAndClearableNoMatches() {
    let initial = FolderMenuSelection(conditions: .init(), loopEnabled: false)
    let actions: [FolderMenuAction] = [.sort(.name), .sort(.modificationDate), .sort(.type), .sort(.size),
        .direction(.ascending), .direction(.descending), .extensionType("png"), .clearFilter, .loop]
    for action in actions {
        #expect(!FolderMenuPolicy.state(for: action, selection: initial,
            hasFolderSource: false, previewActive: false).enabled)
        #expect(!FolderMenuPolicy.state(for: action, selection: initial,
            hasFolderSource: true, previewActive: true).enabled)
    }
    var a = FolderMenuPolicy.applying(.sort(.modificationDate), to: initial)
    a = FolderMenuPolicy.applying(.direction(.descending), to: a)
    a = FolderMenuPolicy.applying(.extensionType("PNG"), to: a)
    a = FolderMenuPolicy.applying(.loop, to: a)
    #expect(a.conditions == .init(sort: .modificationDate, direction: .descending, selectedExtensions: ["png"]))
    #expect(a.loopEnabled)
    for (action, checked) in [(.sort(.name), false), (.sort(.modificationDate), true),
        (.sort(.type), false), (.direction(.ascending), false), (.direction(.descending), true),
        (.extensionType("png"), true), (.extensionType("jpg"), false), (.clearFilter, false), (.loop, true)] as [(FolderMenuAction, Bool)] {
        let state = FolderMenuPolicy.state(for: action, selection: a, hasFolderSource: true, previewActive: false)
        #expect(state.enabled && state.checked == checked)
    }
    let b = initial
    #expect(FolderMenuPolicy.state(for: .sort(.name), selection: b, hasFolderSource: true, previewActive: false).checked)
    #expect(FolderMenuPolicy.state(for: .sort(.modificationDate), selection: b, hasFolderSource: true, previewActive: false).checked == false)
    a = FolderMenuPolicy.applying(.clearFilter, to: a)
    #expect(a.conditions.selectedExtensions == nil)
    #expect(FolderMenuPolicy.state(for: .clearFilter, selection: a, hasFolderSource: true, previewActive: false).checked)
}

@Test func folderMenuPolicyExtensionChoicesAndTogglesRoundTrip() {
    #expect(FolderMenuPolicy.commonExtensions.contains("png"))
    let choices = FolderMenuPolicy.extensionChoices(available: ["JPG", "raw", "png", "raw"])
    #expect(choices.contains("png") && choices.contains("jpg") && choices.contains("raw"))
    #expect(Set(choices).count == choices.count)
    var selected = FolderMenuSelection(conditions: .init(), loopEnabled: false)
    selected = FolderMenuPolicy.applying(.extensionType("PNG"), to: selected)
    #expect(selected.conditions.selectedExtensions == ["png"])
    selected = FolderMenuPolicy.applying(.extensionType("jpg"), to: selected)
    #expect(selected.conditions.selectedExtensions == ["png", "jpg"])
    selected = FolderMenuPolicy.applying(.extensionType("PNG"), to: selected)
    #expect(selected.conditions.selectedExtensions == ["jpg"])
    selected = FolderMenuPolicy.applying(.extensionType("JPG"), to: selected)
    #expect(selected.conditions.selectedExtensions == nil)
}

@Test func folderMenuPolicyIdentifiersAndLabelsCoverEveryAction() {
    let actions: [FolderMenuAction] = FolderSortKey.allCases.map { .sort($0) }
        + FolderSortDirection.allCases.map { .direction($0) }
        + [.extensionType("png"), .extensionType("jpg"), .clearFilter, .loop]
    let identifiers = actions.map(\.accessibilityIdentifier)
    #expect(Set(identifiers).count == identifiers.count)
    #expect(identifiers.allSatisfy { $0.hasPrefix("folder.") && $0.hasSuffix(".menu") })
    #expect(actions.allSatisfy { !$0.titleKey.isEmpty })
}

@Test func folderMenuPolicyExtensionlessImageHasNamedReachableChoice() {
    let extensionless = FolderMenuAction.extensionType("")
    #expect(FolderMenuPolicy.extensionChoices(available: [""]).contains(""))
    #expect(extensionless.accessibilityIdentifier == "folder.extension.none.menu")
    #expect(extensionless.titleKey == "No Extension")
    let initial = FolderMenuSelection(conditions: .init(), loopEnabled: false)
    let selected = FolderMenuPolicy.applying(extensionless, to: initial)
    #expect(selected.conditions.selectedExtensions == [""])
    #expect(FolderMenuPolicy.state(for: extensionless, selection: selected,
        hasFolderSource: true, previewActive: false).checked)
    #expect(FolderMenuPolicy.applying(extensionless, to: selected).conditions.selectedExtensions == nil)
}

@Test func folderMenuPolicyNormalizesMutatedExtensionSetForCheckmarksAndToggles() {
    var conditions = FolderViewConditions()
    conditions.selectedExtensions = ["JPG"]
    let selected = FolderMenuSelection(conditions: conditions, loopEnabled: false)
    #expect(FolderMenuPolicy.state(for: .extensionType("jpg"), selection: selected,
        hasFolderSource: true, previewActive: false).checked)
    #expect(FolderMenuPolicy.applying(.extensionType("jpg"), to: selected).conditions.selectedExtensions == nil)
    let expanded = FolderMenuPolicy.applying(.extensionType("PNG"), to: selected)
    #expect(expanded.conditions.selectedExtensions == ["jpg", "png"])
}
