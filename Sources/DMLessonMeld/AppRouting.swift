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
    case camera
    case audio
    case transcription
    case editor
    case annotations
    case export
    case privacy
    case shortcuts
    case diagnostics
    case presets
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .capture: "Capture"
        case .camera: "Camera"
        case .audio: "Audio"
        case .transcription: "Transcription"
        case .editor: "Editor"
        case .annotations: "Annotations"
        case .export: "Export"
        case .privacy: "Privacy"
        case .shortcuts: "Shortcuts"
        case .diagnostics: "Diagnostics"
        case .presets: "Presets"
        case .community: "Community"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .capture: "record.circle"
        case .camera: "web.camera"
        case .audio: "waveform"
        case .transcription: "captions.bubble"
        case .editor: "timeline.selection"
        case .annotations: "pencil.tip"
        case .export: "square.and.arrow.up"
        case .privacy: "lock.shield"
        case .shortcuts: "keyboard"
        case .diagnostics: "stethoscope"
        case .presets: "wand.and.stars"
        case .community: "person.2"
        }
    }

    var groupTitle: String {
        switch self {
        case .general, .privacy, .shortcuts, .diagnostics:
            "App"
        case .capture, .camera, .audio, .transcription:
            "Recording"
        case .editor, .annotations, .export, .presets:
            "Lesson Defaults"
        case .community:
            "Community"
        }
    }

    var searchKeywords: String {
        switch self {
        case .general:
            "appearance project folder template launch main window"
        case .capture:
            "recording screen fps cursor countdown region controls"
        case .camera:
            "webcam camera picture in picture pip resolution fps mirror border shadow"
        case .audio:
            "microphone mic system audio voice input"
        case .transcription:
            "transcription transcript captions whisper model local language sidecars"
        case .editor:
            "editor video timeline canvas project level cuts zooms overlays captions"
        case .annotations:
            "annotations overlay pencil palette stroke colors toolbar"
        case .export:
            "render export learnhouse package mp4 mov quality archive"
        case .privacy:
            "privacy local only agent manifest transcript media git backup"
        case .shortcuts:
            "keyboard shortcuts hotkeys commands"
        case .diagnostics:
            "diagnostics permissions health cli status"
        case .presets:
            "presets import export reusable defaults"
        case .community:
            "community sstb discord podcast links"
        }
    }
}
