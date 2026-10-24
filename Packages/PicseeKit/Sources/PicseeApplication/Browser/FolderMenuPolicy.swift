import Foundation
import PicseeCore

public enum FolderMenuAction: Equatable, Sendable {
    case sort(FolderSortKey)
    case direction(FolderSortDirection)
    case extensionType(String)
    case clearFilter
    case loop

    public var accessibilityIdentifier: String {
        switch self {
        case .sort(let key): "folder.sort.\(key.rawValue).menu"
        case .direction(let direction): "folder.order.\(direction.rawValue).menu"
        case .extensionType(let value): value.isEmpty ? "folder.extension.none.menu" : "folder.extension.\(value.lowercased()).menu"
        case .clearFilter: "folder.extension.all.menu"
        case .loop: "folder.loop.menu"
        }
    }
    public var titleKey: String {
        switch self {
        case .sort(.name): "Name"
        case .sort(.modificationDate): "Modification Date"
        case .sort(.type): "Type"
        case .sort(.size): "Size"
        case .direction(.ascending): "Ascending"
        case .direction(.descending): "Descending"
        case .extensionType(let value): value.isEmpty ? "No Extension" : value.uppercased()
        case .clearFilter: "All Extensions"
        case .loop: "Loop Through Folder"
        }
    }
}

public struct FolderMenuSelection: Equatable, Sendable {
    public var conditions: FolderViewConditions
    public var loopEnabled: Bool
    public init(conditions: FolderViewConditions, loopEnabled: Bool) {
        self.conditions = conditions
        self.loopEnabled = loopEnabled
    }
}

public struct FolderMenuItemState: Equatable, Sendable {
    public let enabled: Bool
    public let checked: Bool
    public init(enabled: Bool, checked: Bool) {
        self.enabled = enabled
        self.checked = checked
    }
}

public enum FolderMenuPolicy {
    public static let commonExtensions = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"]
    public static func extensionChoices(available: [String]) -> [String] {
        let extra = Set(available.map { $0.lowercased() }).subtracting(commonExtensions).sorted()
        return commonExtensions + extra
    }
    public static func state(for action: FolderMenuAction, selection: FolderMenuSelection,
                             hasFolderSource: Bool, previewActive: Bool) -> FolderMenuItemState {
        let active = hasFolderSource && !previewActive
        let checked: Bool
        switch action {
        case .sort(let key): checked = selection.conditions.sort == key
        case .direction(let direction): checked = selection.conditions.direction == direction
        case .extensionType(let value):
            checked = selection.conditions.selectedExtensions?.contains(where: { $0.lowercased() == value.lowercased() }) == true
        case .clearFilter: checked = selection.conditions.selectedExtensions == nil
        case .loop: checked = selection.loopEnabled
        }
        return .init(enabled: active, checked: active && checked)
    }
    public static func applying(_ action: FolderMenuAction, to selection: FolderMenuSelection) -> FolderMenuSelection {
        var result = selection
        switch action {
        case .sort(let key): result.conditions.sort = key
        case .direction(let direction): result.conditions.direction = direction
        case .extensionType(let value):
            let normalized = value.lowercased()
            if var selected = result.conditions.selectedExtensions.map({ Set($0.map { $0.lowercased() }) }) {
                if selected.contains(normalized) { selected.remove(normalized) }
                else { selected.insert(normalized) }
                result.conditions.selectedExtensions = selected.isEmpty ? nil : selected
            } else { result.conditions.selectedExtensions = [normalized] }
        case .clearFilter: result.conditions.selectedExtensions = nil
        case .loop: result.loopEnabled.toggle()
        }
        return result
    }
}
