import DMLessonMeldCore
import SwiftUI

enum LessonMeldAppCommandID: String, CaseIterable, Identifiable {
    case showMainWindow
    case newProject
    case openProject
    case importVideo
    case revealProject
    case saveEdits
    case exportVideo
    case newRecording
    case recordingControls
    case pauseRecording
    case stopRecording
    case toggleAnnotationOverlay
    case settings
    case onboarding
    case commandPalette

    var id: String { rawValue }
}

enum LessonMeldProjectCommand: String, Identifiable {
    case newProject
    case openProject
    case importVideo
    case revealProject
    case saveEdits
    case exportVideo

    var id: String { rawValue }
}

struct LessonMeldProjectCommandState: Equatable {
    var hasProject = false
    var hasScreenVideo = false
    var isRendering = false
    var hasUnsavedChanges = false

    static let empty = LessonMeldProjectCommandState()
}

struct LessonMeldRecorderCommandState: Equatable {
    var isRecording = false
    var isPaused = false
    var isStopping = false
}

struct LessonMeldCommandContext {
    var preferences: LessonMeldPreferences
    var project: LessonMeldProjectCommandState
    var recorder: LessonMeldRecorderCommandState
    var isAnnotationPresented: Bool
}

struct LessonMeldAppCommand: Identifiable {
    let id: LessonMeldAppCommandID
    let title: String
    let subtitle: String
    let systemImage: String
    let shortcut: String?
    let keywords: [String]
    let isEnabled: Bool
    let disabledReason: String?
    let action: () -> Void
}

private struct LessonMeldCommandDefinition {
    let id: LessonMeldAppCommandID
    let title: String
    let subtitle: String
    let systemImage: String
    let shortcut: String?
    let keywords: [String]
}

enum LessonMeldCommandRegistry {
    static func command(
        _ id: LessonMeldAppCommandID,
        context: LessonMeldCommandContext,
        handler: @escaping (LessonMeldAppCommandID) -> Void
    ) -> LessonMeldAppCommand {
        let definition = definition(for: id)
        let availability = availability(for: id, context: context)
        return LessonMeldAppCommand(
            id: id,
            title: title(for: definition, context: context),
            subtitle: availability.disabledReason ?? subtitle(for: definition, context: context),
            systemImage: systemImage(for: definition, context: context),
            shortcut: shortcut(for: definition, context: context),
            keywords: definition.keywords,
            isEnabled: availability.isEnabled,
            disabledReason: availability.disabledReason,
            action: { handler(id) }
        )
    }

    static func commands(
        context: LessonMeldCommandContext,
        handler: @escaping (LessonMeldAppCommandID) -> Void
    ) -> [LessonMeldAppCommand] {
        commandOrder.map { command($0, context: context, handler: handler) }
    }

    private static let commandOrder: [LessonMeldAppCommandID] = [
        .showMainWindow,
        .newProject,
        .openProject,
        .importVideo,
        .revealProject,
        .saveEdits,
        .exportVideo,
        .newRecording,
        .recordingControls,
        .pauseRecording,
        .stopRecording,
        .toggleAnnotationOverlay,
        .settings,
        .onboarding,
        .commandPalette
    ]

    private static func definition(for id: LessonMeldAppCommandID) -> LessonMeldCommandDefinition {
        switch id {
        case .showMainWindow:
            LessonMeldCommandDefinition(id: id, title: "Show Main Window", subtitle: "Open the record, edit, export workspace.", systemImage: "rectangle.stack.badge.play", shortcut: "⌘0", keywords: ["home", "record", "edit", "export", "project"])
        case .newProject:
            LessonMeldCommandDefinition(id: id, title: "New Project", subtitle: "Create an empty lesson project for recording or import.", systemImage: "doc.badge.plus", shortcut: "⌘N", keywords: ["project", "lesson", "new", "record", "edit"])
        case .openProject:
            LessonMeldCommandDefinition(id: id, title: "Open Project", subtitle: "Open an existing .dmlm lesson project for editing or export.", systemImage: "folder", shortcut: "⌘O", keywords: ["project", "lesson", "open", "bundle", "edit", "export"])
        case .importVideo:
            LessonMeldCommandDefinition(id: id, title: "Import Video", subtitle: "Create a lesson project from an MP4 or MOV and open Edit Video.", systemImage: "film.badge.plus", shortcut: "⌘I", keywords: ["import", "video", "edit", "project", "mp4", "mov"])
        case .revealProject:
            LessonMeldCommandDefinition(id: id, title: "Reveal Project in Finder", subtitle: "Show the editable .dmlm project package.", systemImage: "arrow.up.forward.app", shortcut: "⇧⌘R", keywords: ["finder", "reveal", "project", "bundle"])
        case .saveEdits:
            LessonMeldCommandDefinition(id: id, title: "Save Changes", subtitle: "Save timeline, marker, overlay, caption, and editor sidecars.", systemImage: "checkmark.circle", shortcut: "⌘S", keywords: ["save", "edits", "changes", "sidecar", "timeline"])
        case .exportVideo:
            LessonMeldCommandDefinition(id: id, title: "Export Video", subtitle: "Render the current lesson video or package it for LearnHouse.", systemImage: "square.and.arrow.up", shortcut: "⇧⌘E", keywords: ["export", "render", "video", "package"])
        case .newRecording:
            LessonMeldCommandDefinition(id: id, title: "New Recording", subtitle: "Open the floating recorder for a new take.", systemImage: "record.circle", shortcut: "⌥⌘↩", keywords: ["record", "capture", "take"])
        case .recordingControls:
            LessonMeldCommandDefinition(id: id, title: "Open Recording Controls", subtitle: "Show the floating recorder controls.", systemImage: "slider.horizontal.3", shortcut: "⌥⌘R", keywords: ["record", "controls", "capture"])
        case .pauseRecording:
            LessonMeldCommandDefinition(id: id, title: "Pause Recording", subtitle: "Pause or resume the active recording.", systemImage: "pause.fill", shortcut: nil, keywords: ["pause", "resume", "recording"])
        case .stopRecording:
            LessonMeldCommandDefinition(id: id, title: "Stop Recording", subtitle: "Stop the active recording and open the project.", systemImage: "stop.fill", shortcut: "Esc", keywords: ["stop", "finish", "recording"])
        case .toggleAnnotationOverlay:
            LessonMeldCommandDefinition(id: id, title: "Open Annotation Overlay", subtitle: "Toggle the live local drawing overlay.", systemImage: "pencil.tip", shortcut: nil, keywords: ["draw", "overlay", "annotate"])
        case .settings:
            LessonMeldCommandDefinition(id: id, title: "Settings", subtitle: "Capture, annotation, export, privacy, diagnostics, and shortcuts.", systemImage: "gearshape", shortcut: nil, keywords: ["preferences", "config", "settings"])
        case .onboarding:
            LessonMeldCommandDefinition(id: id, title: "Onboarding", subtitle: "Review permissions and first-run teaching defaults.", systemImage: "checklist", shortcut: nil, keywords: ["permissions", "setup", "privacy"])
        case .commandPalette:
            LessonMeldCommandDefinition(id: id, title: "Command Palette", subtitle: "Search app, project, recording, and editor commands.", systemImage: "command", shortcut: "⌘K", keywords: ["commands", "search", "palette"])
        }
    }

    private static func title(for definition: LessonMeldCommandDefinition, context: LessonMeldCommandContext) -> String {
        switch definition.id {
        case .recordingControls:
            context.recorder.isRecording ? "Show Recording Controls" : definition.title
        case .pauseRecording:
            context.recorder.isPaused ? "Resume Recording" : definition.title
        case .toggleAnnotationOverlay:
            context.isAnnotationPresented ? "Close Annotation Overlay" : definition.title
        default:
            definition.title
        }
    }

    private static func subtitle(for definition: LessonMeldCommandDefinition, context: LessonMeldCommandContext) -> String {
        switch definition.id {
        case .recordingControls where context.recorder.isRecording:
            "Bring the active recording controls forward."
        case .toggleAnnotationOverlay where context.isAnnotationPresented:
            "Close the live local drawing overlay."
        default:
            definition.subtitle
        }
    }

    private static func systemImage(for definition: LessonMeldCommandDefinition, context: LessonMeldCommandContext) -> String {
        switch definition.id {
        case .pauseRecording:
            context.recorder.isPaused ? "play.fill" : definition.systemImage
        default:
            definition.systemImage
        }
    }

    private static func shortcut(for definition: LessonMeldCommandDefinition, context: LessonMeldCommandContext) -> String? {
        switch definition.id {
        case .settings:
            context.preferences.shortcuts[.showSettings] ?? "⌘,"
        case .onboarding:
            context.preferences.shortcuts[.showOnboarding]
        case .toggleAnnotationOverlay:
            context.preferences.shortcuts[.openAnnotationOverlay]
        default:
            definition.shortcut
        }
    }

    private static func availability(for id: LessonMeldAppCommandID, context: LessonMeldCommandContext) -> (isEnabled: Bool, disabledReason: String?) {
        switch id {
        case .revealProject:
            return context.project.hasProject ? (true, nil) : (false, "Open or create a lesson project first.")
        case .saveEdits:
            if !context.project.hasProject {
                return (false, "Open or create a lesson project before saving edits.")
            }
            return context.project.hasUnsavedChanges ? (true, nil) : (false, "No unsaved edits.")
        case .exportVideo:
            if context.project.isRendering {
                return (false, "A render is already running.")
            }
            return context.project.hasScreenVideo ? (true, nil) : (false, "Record or import a source video before exporting.")
        case .newRecording:
            return context.recorder.isRecording ? (false, "A recording is already in progress.") : (true, nil)
        case .pauseRecording, .stopRecording:
            return context.recorder.isRecording && !context.recorder.isStopping ? (true, nil) : (false, "No active recording.")
        default:
            return (true, nil)
        }
    }
}
