import PicseeCore

/// Temporary per-window seam, to be implemented by ViewerSession in #11.
@MainActor
public protocol WindowCommandTarget: AnyObject {
    func isEnabled(_ command: CommandID) -> Bool
    func perform(_ command: CommandID)
}

@MainActor
public struct CommandRouter {
    public init() {}
    @discardableResult
    public func route(_ command: CommandID, from entry: CommandEntry, focus: FocusContext,
                      menuTracking: Bool = false, to target: any WindowCommandTarget) -> Bool {
        guard command.isImplemented, target.isEnabled(command) else { return false }
        if entry == .key {
            guard !menuTracking else { return false }
            if focus == .textInput && !command.usesCommand && command != .escape { return false }
        }
        if command == .escape && menuTracking { return false }
        target.perform(command)
        return true
    }
}
