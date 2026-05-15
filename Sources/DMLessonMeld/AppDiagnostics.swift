import DMLessonMeldCore
import SwiftUI

struct AppDiagnostics {
    let summary: String
    let modules: [DiagnosticModule]
    let cliSummary: String
    let cliCommands: [String]

    static var current: AppDiagnostics {
        let templates = LessonTemplateLibrary.defaultTemplates
        let presets = LessonTemplateLibrary.defaultExportPresets

        return AppDiagnostics(
            summary: "\(AppMetadata.versionBuildText) recorder, editor, annotation, package, CLI, and agent foundations are wired locally.",
            modules: [
                DiagnosticModule(
                    name: "Project bundles",
                    state: .available,
                    detail: "Schema v\(ProjectManifest.currentSchemaVersion), media sidecars, tracks, markers, and export preset references.",
                    symbolName: "folder"
                ),
                DiagnosticModule(
                    name: "Templates",
                    state: .available,
                    detail: "\(templates.count) templates and \(presets.count) export presets are bundled.",
                    symbolName: "rectangle.stack"
                ),
                DiagnosticModule(
                    name: "LearnHouse export",
                    state: .available,
                    detail: "Local package assembly is wired through the LearnHouse folder in DMLessonMeldCore.",
                    symbolName: "shippingbox"
                ),
                DiagnosticModule(
                    name: "Config sync",
                    state: .available,
                    detail: "Safe local Git init/status/commit backup is wired through the config sync core.",
                    symbolName: "arrow.triangle.2.circlepath"
                ),
                DiagnosticModule(
                    name: "Agent bridge",
                    state: .available,
                    detail: "Agent-readable project manifests are wired through the agent bridge core.",
                    symbolName: "point.3.connected.trianglepath.dotted"
                ),
                DiagnosticModule(
                    name: "Captions and transcripts",
                    state: .available,
                    detail: "Caption/transcript sidecar exporters are wired through DMLessonMeldCore.",
                    symbolName: "captions.bubble"
                ),
                DiagnosticModule(
                    name: "Audio",
                    state: .available,
                    detail: "Audio source models, waveform peaks, region validation, and microphone recorder foundation are in DMLessonMeldCore.",
                    symbolName: "waveform"
                ),
                DiagnosticModule(
                    name: "Editor",
                    state: .available,
                    detail: "Project inspection, screen preview/scrub, saved cut-list decisions, cut-list export, full render, and contiguous trim export are available in the app.",
                    symbolName: "timeline.selection"
                ),
                DiagnosticModule(
                    name: "Annotations",
                    state: .available,
                    detail: "\(AnnotationTool.allCases.count) annotation tools, undoable annotation store, and live overlay shell are wired.",
                    symbolName: "pencil.tip"
                ),
                DiagnosticModule(
                    name: "Recorder/editor",
                    state: .available,
                    detail: "Quick screen recording is available. CLI supports screen, region, microphone, webcam, trim planning, and sidecars.",
                    symbolName: "record.circle"
                ),
                DiagnosticModule(
                    name: "Renderer",
                    state: .available,
                    detail: "AVFoundation render planning/export is in DMLessonMeldCore with webcam PiP, cursor/click/shortcut effects, zoom, annotations, and captions.",
                    symbolName: "film.stack"
                )
            ],
            cliSummary: "The Swift package builds the `dmlesson` CLI for local recording, project, annotation, transcript, package, config, and agent workflows.",
            cliCommands: [
                "swift run dmlesson --help",
                "swift run dmlesson permissions status --json",
                "swift run dmlesson record project --duration 5 --output Lesson.dmlm --lesson-title Intro --microphone --webcam",
                "swift run dmlesson annotations init Lesson.dmlm",
                "swift run dmlesson render plan Lesson.dmlm --output Lesson.mp4 --json",
                "swift run dmlesson project inspect <project.dmlm> --json",
                "swift run dmlesson learnhouse package <project.dmlm> --output <directory> --archive",
                "swift run dmlesson config commit ~/.dm-lessonmeld --message \"Backup lesson config\" --json"
            ]
        )
    }
}

struct DiagnosticModule: Identifiable {
    let id = UUID()
    let name: String
    let state: DiagnosticModuleState
    let detail: String
    let symbolName: String
}

enum DiagnosticModuleState {
    case available
    case pending

    var label: String {
        switch self {
        case .available: "Available"
        case .pending: "Pending"
        }
    }

    var tint: Color {
        switch self {
        case .available: .green
        case .pending: .orange
        }
    }
}
