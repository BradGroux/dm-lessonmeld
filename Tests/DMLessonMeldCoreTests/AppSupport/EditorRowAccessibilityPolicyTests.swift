import DMLessonMeldSupport
import Testing

@Suite("Editor row accessibility policy")
struct EditorRowAccessibilityPolicyTests {
    @Test("Row actions include their editor item and start time", arguments: [
        (EditorRowAccessibilityAction.enabled, EditorRowAccessibilityKind.zoom, "12.500", "Zoom at 12.5 seconds enabled"),
        (.seek, .zoom, "12.500", "Seek to zoom at 12.5 seconds"),
        (.delete, .zoom, "12.500", "Delete zoom at 12.5 seconds"),
        (.enabled, .reaction, "3", "Reaction at 3 seconds enabled"),
        (.delete, .reaction, "3", "Delete reaction at 3 seconds"),
        (.seek, .caption, "8.25", "Seek to caption at 8.25 seconds"),
        (.delete, .caption, "8.25", "Delete caption at 8.25 seconds"),
    ])
    func contextualLabels(
        action: EditorRowAccessibilityAction,
        kind: EditorRowAccessibilityKind,
        startSeconds: String,
        expected: String
    ) {
        #expect(EditorRowAccessibilityPolicy.label(for: action, kind: kind, startSeconds: startSeconds) == expected)
    }

    @Test("Invalid row times remain understandable without echoing malformed input")
    func invalidTime() {
        #expect(
            EditorRowAccessibilityPolicy.label(for: .delete, kind: .caption, startSeconds: "not-a-time")
                == "Delete caption at an unknown time"
        )
    }
}
