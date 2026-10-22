import PicseeCore
import PicseeApplication

/// Temporary navigation adapter. #11 can move FolderNavigation onto its ViewerSession.
@MainActor
final class AccessCommandRouter {
    let canNavigate: () -> Bool
    let navigate: (NavigationDirection) -> Void
    init(canNavigate: @escaping () -> Bool, navigate: @escaping (NavigationDirection) -> Void) {
        self.canNavigate = canNavigate; self.navigate = navigate
    }
    func route(_ command: CommandID, from entry: CommandEntry, focus: FocusContext,
               menuTracking: Bool, to target: any WindowCommandTarget) -> Bool {
        let adapter = NavigationTarget(base: target, canNavigate: canNavigate(), navigate: navigate)
        return CommandRouter().route(command, from: entry, focus: focus, menuTracking: menuTracking, to: adapter)
    }
    private final class NavigationTarget: WindowCommandTarget {
        let base: any WindowCommandTarget
        let canNavigate: Bool
        let navigate: (NavigationDirection) -> Void
        init(base: any WindowCommandTarget, canNavigate: Bool, navigate: @escaping (NavigationDirection) -> Void) {
            self.base = base; self.canNavigate = canNavigate; self.navigate = navigate
        }
        func isEnabled(_ command: CommandID) -> Bool {
            command == .previous || command == .next ? canNavigate : base.isEnabled(command)
        }
        func perform(_ command: CommandID) {
            if command == .previous { navigate(.previous) }
            else if command == .next { navigate(.next) }
            else { base.perform(command) }
        }
    }
}
