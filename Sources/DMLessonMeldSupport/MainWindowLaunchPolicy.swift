public enum MainWindowLaunchAction: Equatable, Sendable {
    case present
    case suppress
}

public enum MainWindowLaunchPolicy {
    public static func action(showMainWindowAtLaunch: Bool) -> MainWindowLaunchAction {
        showMainWindowAtLaunch ? .present : .suppress
    }
}
