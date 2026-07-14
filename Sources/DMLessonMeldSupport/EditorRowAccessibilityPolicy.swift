import Foundation

public enum EditorRowAccessibilityAction: Sendable {
    case enabled
    case seek
    case delete
}

public enum EditorRowAccessibilityKind: String, Sendable {
    case zoom
    case reaction
    case caption

    fileprivate var displayName: String {
        rawValue.capitalized
    }
}

public enum EditorRowAccessibilityPolicy {
    public static func label(
        for action: EditorRowAccessibilityAction,
        kind: EditorRowAccessibilityKind,
        startSeconds: String
    ) -> String {
        let context = context(startSeconds: startSeconds)

        switch action {
        case .enabled:
            return "\(kind.displayName) \(context) enabled"
        case .seek:
            return "Seek to \(kind.rawValue) \(context)"
        case .delete:
            return "Delete \(kind.rawValue) \(context)"
        }
    }

    private static func context(startSeconds: String) -> String {
        guard let value = Double(startSeconds), value.isFinite, value >= 0 else {
            return "at an unknown time"
        }

        var formatted = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        while formatted.last == "0" {
            formatted.removeLast()
        }
        if formatted.last == "." {
            formatted.removeLast()
        }
        return "at \(formatted) seconds"
    }
}
