import DMLessonMeldCore
import DMLessonMeldSupport
import Testing

@Suite("Shortcut presentation policy")
struct ShortcutPresentationPolicyTests {
    @Test("Native command shortcuts report their actual bindings", arguments: [
        (LessonMeldShortcutAction.showSettings, "⌘,"),
        (.showOnboarding, "⌥⌘P"),
        (.openAnnotationOverlay, "⌥⌘A"),
        (.quickRecord, "⌥⌘R"),
        (.stopRecording, "Esc"),
    ])
    func activeBindings(action: LessonMeldShortcutAction, displayValue: String) {
        #expect(ShortcutPresentationPolicy.status(for: action) == .builtIn(displayValue))
    }

    @Test("Future annotation color bindings are labeled reserved", arguments: [
        LessonMeldShortcutAction.quickColor1,
        .quickColor2,
        .quickColor3,
        .quickColor4,
    ])
    func reservedBindings(action: LessonMeldShortcutAction) {
        #expect(ShortcutPresentationPolicy.status(for: action) == .reserved)
    }
}
