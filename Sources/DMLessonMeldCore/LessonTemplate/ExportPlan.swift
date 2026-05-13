import Foundation

public struct LessonTemplateExportPlan: Codable, Equatable, Sendable {
    public var projectPath: String
    public var lessonTitle: String
    public var preset: LessonTemplateExportPreset
    public var status: LessonTemplateExportPlanStatus
    public var requiredModule: String

    public init(
        projectPath: String,
        lessonTitle: String,
        preset: LessonTemplateExportPreset,
        status: LessonTemplateExportPlanStatus = .rendererPending,
        requiredModule: String = "DMLessonMeldCore"
    ) {
        self.projectPath = projectPath
        self.lessonTitle = lessonTitle
        self.preset = preset
        self.status = status
        self.requiredModule = requiredModule
    }
}

public enum LessonTemplateExportPlanStatus: String, Codable, Sendable {
    case rendererPending
    case ready
}

public enum ExportPlanner {
    public static func plan(projectURL: URL, presetID: String) throws -> LessonTemplateExportPlan {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        guard let preset = LessonTemplateLibrary.exportPreset(id: presetID) else {
            throw ExportPlannerError.unknownPreset(presetID)
        }

        return LessonTemplateExportPlan(
            projectPath: projectURL.path,
            lessonTitle: manifest.metadata.lessonTitle,
            preset: preset
        )
    }
}

public enum ExportPlannerError: Error, LocalizedError {
    case unknownPreset(String)

    public var errorDescription: String? {
        switch self {
        case .unknownPreset(let id):
            "Unknown export preset: \(id)"
        }
    }
}
