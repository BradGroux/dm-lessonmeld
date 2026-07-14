import DMLessonMeldCore

public enum ShortcutPresentationStatus: Equatable, Sendable {
    case builtIn(String)
    case reserved
}

public enum ShortcutPresentationPolicy {
    public static func status(
        for action: LessonMeldShortcutAction
    ) -> ShortcutPresentationStatus {
        switch action {
        case .showSettings:
            .builtIn("⌘,")
        case .showOnboarding:
            .builtIn("⌥⌘P")
        case .openAnnotationOverlay:
            .builtIn("⌥⌘A")
        case .quickRecord:
            .builtIn("⌥⌘R")
        case .stopRecording:
            .builtIn("Esc")
        case .quickColor1, .quickColor2, .quickColor3, .quickColor4:
            .reserved
        }
    }
}
