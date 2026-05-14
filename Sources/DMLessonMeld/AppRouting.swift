import Foundation

@MainActor
final class LessonMeldAppRouter: ObservableObject {
    @Published private(set) var settingsRequest: LessonMeldSettingsWindowRequest?

    func openSettings(_ section: LessonMeldSettingsSection? = nil) {
        settingsRequest = LessonMeldSettingsWindowRequest(section: section)
    }
}

struct LessonMeldSettingsWindowRequest: Identifiable, Equatable {
    let id = UUID()
    var section: LessonMeldSettingsSection?
}

enum LessonMeldSettingsSection: String, CaseIterable, Identifiable {
    case general
    case capture
    case annotations
    case export
    case community
    case privacy
    case shortcuts
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .capture: "Capture"
        case .annotations: "Annotations"
        case .export: "Export"
        case .community: "Community"
        case .privacy: "Privacy"
        case .shortcuts: "Shortcuts"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .capture: "record.circle"
        case .annotations: "pencil.tip"
        case .export: "square.and.arrow.up"
        case .community: "person.2"
        case .privacy: "lock.shield"
        case .shortcuts: "keyboard"
        case .diagnostics: "stethoscope"
        }
    }
}
