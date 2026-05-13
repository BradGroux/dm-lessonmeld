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

    public init(
        schemaVersion: Int = 1,
        redactionPolicy: String,
        project: ProjectBundleSummary,
        metadata: LessonMetadata,
        markers: [ProjectTimelineMarker],
        files: [AgentFileReference],
        availableCommands: [AgentCommand]
    ) {
        self.schemaVersion = schemaVersion
        self.redactionPolicy = redactionPolicy
        self.project = project
        self.metadata = metadata
        self.markers = markers
        self.files = files
        self.availableCommands = availableCommands
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

public enum AgentManifestBuilder {
    public static func build(projectURL: URL, options: AgentManifestOptions = AgentManifestOptions()) throws -> AgentProjectManifest {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let summary = try ProjectBundle.inspect(at: projectURL)
        let files = manifest.media.allFiles.compactMap { file -> AgentFileReference? in
            if file.role == .transcript && !options.includeTranscriptReferences {
                return AgentFileReference(role: file.role, path: nil)
            }

            return AgentFileReference(
                role: file.role,
                path: options.includeMediaPaths ? file.relativePath : nil
            )
        }

        return AgentProjectManifest(
            redactionPolicy: options.includeMediaPaths
                ? "media paths included by explicit request; transcript references may still be redacted"
                : "metadata only; media paths and transcript references are redacted by default",
            project: summary,
            metadata: manifest.metadata,
            markers: manifest.markers,
            files: files,
            availableCommands: defaultCommands()
        )
    }

    public static func defaultCommands() -> [AgentCommand] {
        [
            AgentCommand(name: "project inspect", summary: "Validate and summarize a project bundle."),
            AgentCommand(name: "templates list", summary: "List built-in lesson templates."),
            AgentCommand(name: "presets list", summary: "List built-in export presets."),
            AgentCommand(name: "learnhouse package", summary: "Create a LearnHouse-ready local package."),
            AgentCommand(name: "edit decisions", summary: "Read project-local edit decisions."),
            AgentCommand(name: "edit add-cut", summary: "Append a validated cut to the project edit-decision sidecar."),
            AgentCommand(name: "edit validate", summary: "Validate project-local edit decisions."),
            AgentCommand(name: "edit export-decisions", summary: "Export video with saved edit-decision cuts applied."),
            AgentCommand(name: "config plan", summary: "Plan safe Git-backed config/template backup."),
            AgentCommand(name: "config commit", summary: "Commit safe local config/template backups.")
        ]
    }
}
