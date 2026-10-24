import Foundation

public enum FolderSortKey: String, CaseIterable, Sendable {
    case name, modificationDate, type, size
}

public enum FolderSortDirection: String, CaseIterable, Sendable {
    case ascending, descending
}

public struct FolderViewConditions: Equatable, Sendable {
    public var sort: FolderSortKey
    public var direction: FolderSortDirection
    public var selectedExtensions: Set<String>?

    public init(sort: FolderSortKey = .name, direction: FolderSortDirection = .ascending,
                selectedExtensions: Set<String>? = nil) {
        self.sort = sort
        self.direction = direction
        self.selectedExtensions = selectedExtensions.map { Set($0.map { $0.lowercased() }) }
    }
}

extension FolderSnapshot {
    public func applying(_ conditions: FolderViewConditions) -> Self {
        let selected = conditions.selectedExtensions.map { Set($0.map { $0.lowercased() }) }
        let projected = entries.filter { selected?.contains($0.normalizedExtension) != false }
            .sorted { folderEntryBefore($0, $1, conditions: conditions) }
        return Self(version: version, orderedEntries: projected, isComplete: isComplete)
    }
}

private func folderEntryBefore(_ lhs: FolderEntry, _ rhs: FolderEntry,
                               conditions: FolderViewConditions) -> Bool {
    let comparison: ComparisonResult
    switch conditions.sort {
    case .name:
        comparison = folderNaturalNameCompare(lhs, rhs)
    case .type:
        comparison = lhs.normalizedExtension.compare(rhs.normalizedExtension)
    case .modificationDate:
        switch (lhs.modificationDate, rhs.modificationDate) {
        case (nil, nil): comparison = .orderedSame
        case (nil, _?): return false
        case (_?, nil): return true
        case let (left?, right?): comparison = left.compare(right)
        }
    case .size:
        switch (lhs.fileSize, rhs.fileSize) {
        case (nil, nil): comparison = .orderedSame
        case (nil, _?): return false
        case (_?, nil): return true
        case let (left?, right?):
            comparison = left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
        }
    }
    guard comparison == .orderedSame else {
        return conditions.direction == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
    let names = folderNaturalNameCompare(lhs, rhs)
    return names == .orderedSame ? lhs.relativePath < rhs.relativePath : names == .orderedAscending
}

func folderNaturalNameCompare(_ lhs: FolderEntry, _ rhs: FolderEntry) -> ComparisonResult {
    lhs.url.lastPathComponent.lowercased().localizedStandardCompare(rhs.url.lastPathComponent.lowercased())
}
