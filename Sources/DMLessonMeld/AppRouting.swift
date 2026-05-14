import Foundation

@MainActor
final class LessonMeldAppRouter: ObservableObject {
    @Published private(set) var settingsRequest: LessonMeldSettingsWindowRequest?
    @Published private(set) var importVideoRequest: UUID?
    @Published private(set) var projectCommandRequest: LessonMeldProjectCommandRequest?
    @Published private(set) var projectCommandState = LessonMeldProjectCommandState.empty

    func openSettings(_ section: LessonMeldSettingsSection? = nil) {
        settingsRequest = LessonMeldSettingsWindowRequest(section: section)
    }

    func importVideoForEditing() {
        importVideoRequest = UUID()
    }

    func runProjectCommand(_ command: LessonMeldProjectCommand) {
        projectCommandRequest = LessonMeldProjectCommandRequest(command: command)
    }

    func updateProjectCommandState(_ state: LessonMeldProjectCommandState) {
        guard projectCommandState != state else { return }
        projectCommandState = state
    }
}

struct LessonMeldSettingsWindowRequest: Identifiable, Equatable {
    let id = UUID()
    var section: LessonMeldSettingsSection?
}

struct LessonMeldProjectCommandRequest: Identifiable, Equatable {
    let id = UUID()
    var command: LessonMeldProjectCommand
}

enum LessonMeldSettingsSection: String, CaseIterable, Identifiable {
    case general
    case capture
    case annotations
    case export
    case presets
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
        case .presets: "Presets"
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
        case .presets: "wand.and.stars"
        case .community: "person.2"
        case .privacy: "lock.shield"
        case .shortcuts: "keyboard"
        case .diagnostics: "stethoscope"
        }
    }
}
