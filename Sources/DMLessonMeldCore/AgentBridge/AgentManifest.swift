import Foundation

public struct AgentManifestOptions: Codable, Equatable, Sendable {
    public var includeMediaPaths: Bool
    public var includeTranscriptReferences: Bool

    public init(includeMediaPaths: Bool = false, includeTranscriptReferences: Bool = false) {
        self.includeMediaPaths = includeMediaPaths
        self.includeTranscriptReferences = includeTranscriptReferences
    }
}

public struct AgentProjectManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var redactionPolicy: String
    public var project: ProjectBundleSummary
    public var metadata: LessonMetadata
    public var markers: [ProjectTimelineMarker]
    public var files: [AgentFileReference]
    public var availableCommands: [AgentCommand]
    public var workflows: [AgentWorkflow]

    public init(
        schemaVersion: Int = 2,
        redactionPolicy: String,
        project: ProjectBundleSummary,
        metadata: LessonMetadata,
        markers: [ProjectTimelineMarker],
        files: [AgentFileReference],
        availableCommands: [AgentCommand],
        workflows: [AgentWorkflow] = AgentWorkflowCatalog.defaultWorkflows()
    ) {
        self.schemaVersion = schemaVersion
        self.redactionPolicy = redactionPolicy
        self.project = project
        self.metadata = metadata
        self.markers = markers
        self.files = files
        self.availableCommands = availableCommands
        self.workflows = workflows
    }
}

public struct AgentFileReference: Codable, Equatable, Sendable {
    public var role: ProjectFileRole
    public var path: String?

    public init(role: ProjectFileRole, path: String?) {
        self.role = role
        self.path = path
    }
}

public struct AgentCommand: Codable, Equatable, Sendable {
    public var name: String
    public var summary: String

    public init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }
}

public struct AgentWorkflow: Codable, Equatable, Sendable {
    public var target: AgentTarget
    public var targetSlug: String
    public var summary: String
    public var steps: [AgentWorkflowStep]

    public init(target: AgentTarget, summary: String, steps: [AgentWorkflowStep]) {
        self.target = target
        self.targetSlug = target.slug
        self.summary = summary
        self.steps = steps
    }
}

public struct AgentWorkflowStep: Codable, Equatable, Sendable {
    public var command: String
    public var purpose: String
    public var safeByDefault: Bool

    public init(command: String, purpose: String, safeByDefault: Bool = true) {
        self.command = command
        self.purpose = purpose
        self.safeByDefault = safeByDefault
    }
}

public enum AgentWorkflowCatalog {
    public static func defaultWorkflows(target: AgentTarget? = nil) -> [AgentWorkflow] {
        let workflows = [
            AgentWorkflow(
                target: .openClaw,
                summary: "Inspect lesson metadata and package local course-ready artifacts without exposing media paths.",
                steps: [
                    AgentWorkflowStep(command: "agent manifest <project> --include-transcript-references", purpose: "Read redacted lesson metadata and transcript sidecar references."),
                    AgentWorkflowStep(command: "edit validate <project> --json", purpose: "Check saved edit decisions before packaging."),
                    AgentWorkflowStep(command: "render plan <project> --output <video.mp4> --json", purpose: "Inspect render readiness without exporting media."),
                    AgentWorkflowStep(command: "learnhouse package <project> --output <directory> --archive --json", purpose: "Build a local LearnHouse package for handoff.")
                ]
            ),
            AgentWorkflow(
                target: .codex,
                summary: "Use stable JSON to audit, edit, validate, and package local lesson bundles.",
                steps: [
                    AgentWorkflowStep(command: "agent manifest <project>", purpose: "Read safe project metadata and command affordances."),
                    AgentWorkflowStep(command: "project inspect <project> --json", purpose: "Validate bundle structure and manifest references."),
                    AgentWorkflowStep(command: "transcript model-status --settings <settings.json> --json", purpose: "Check local transcription model readiness before attempting transcript work."),
                    AgentWorkflowStep(command: "render plan <project> --output <video.mp4> --json", purpose: "Inspect render issues before export."),
                    AgentWorkflowStep(command: "share package <project> --output <directory> --final-video <video.mp4> --json", purpose: "Build a local share package after a final render exists.")
                ]
            ),
            AgentWorkflow(
                target: .veritasKanban,
                summary: "Convert lesson project state into checklist-friendly validation, chapter, and package steps.",
                steps: [
                    AgentWorkflowStep(command: "agent manifest <project> --include-transcript-references", purpose: "Read lesson metadata, markers, and transcript references for task planning."),
                    AgentWorkflowStep(command: "chapters export <project> --format json --output <chapters.json> --json", purpose: "Create structured chapter checkpoints."),
                    AgentWorkflowStep(command: "edit validate <project> --json", purpose: "Capture remaining edit-decision blockers."),
                    AgentWorkflowStep(command: "share package <project> --output <directory> --final-video <video.mp4> --json", purpose: "Create a local deliverable package for review.")
                ]
            )
        ]

        guard let target else { return workflows }
        return workflows.filter { $0.target == target }
    }
}

public enum AgentManifestBuilder {
    public static func build(projectURL: URL, options: AgentManifestOptions = AgentManifestOptions()) throws -> AgentProjectManifest {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let summary = try ProjectBundle.inspect(at: projectURL)
        let files = manifest.media.allFiles.compactMap { file -> AgentFileReference? in
            let shouldIncludePath = file.role == .transcript
                ? options.includeTranscriptReferences
                : options.includeMediaPaths

            return AgentFileReference(
                role: file.role,
                path: shouldIncludePath ? file.relativePath : nil
            )
        }

        return AgentProjectManifest(
            redactionPolicy: redactionPolicy(for: options),
            project: summary,
            metadata: manifest.metadata,
            markers: manifest.markers,
            files: files,
            availableCommands: defaultCommands(),
            workflows: AgentWorkflowCatalog.defaultWorkflows()
        )
    }

    private static func redactionPolicy(for options: AgentManifestOptions) -> String {
        switch (options.includeMediaPaths, options.includeTranscriptReferences) {
        case (true, true):
            return "media paths and transcript references included by explicit request"
        case (true, false):
            return "media paths included by explicit request; transcript references are redacted"
        case (false, true):
            return "metadata only except transcript references included by explicit request"
        case (false, false):
            return "metadata only; media paths and transcript references are redacted by default"
        }
    }

    public static func defaultCommands() -> [AgentCommand] {
        [
            AgentCommand(name: "project inspect", summary: "Validate and summarize a project bundle."),
            AgentCommand(name: "templates list", summary: "List built-in lesson templates."),
            AgentCommand(name: "presets list", summary: "List built-in export presets."),
            AgentCommand(name: "learnhouse package", summary: "Create a LearnHouse-ready local package."),
            AgentCommand(name: "share package", summary: "Create a local share package with sidecars and checksums."),
            AgentCommand(name: "transcript model-status", summary: "Report local transcription model readiness."),
            AgentCommand(name: "chapters export", summary: "Export project chapters as YouTube text, Markdown, or JSON."),
            AgentCommand(name: "edit decisions", summary: "Read project-local edit decisions."),
            AgentCommand(name: "edit add-cut", summary: "Append a validated cut to the project edit-decision sidecar."),
            AgentCommand(name: "edit validate", summary: "Validate project-local edit decisions."),
            AgentCommand(name: "edit export-decisions", summary: "Export video with saved edit-decision cuts applied."),
            AgentCommand(name: "config plan", summary: "Plan safe Git-backed config/template backup."),
            AgentCommand(name: "config commit", summary: "Commit safe local config/template backups.")
        ]
    }
}

public extension AgentTarget {
    var slug: String {
        switch self {
        case .openClaw:
            "openclaw"
        case .codex:
            "codex"
        case .veritasKanban:
            "veritas-kanban"
        }
    }

    static func matching(_ value: String) -> AgentTarget? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { target in
            target.slug == normalized || target.rawValue.lowercased() == normalized
        }
    }
}
