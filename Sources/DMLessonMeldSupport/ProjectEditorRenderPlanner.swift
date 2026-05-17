import DMLessonMeldCore
import Foundation

public enum ProjectEditorRenderPlanner {
    public static func makePlan(
        projectURL: URL,
        manifest: ProjectManifest,
        destinationURL: URL,
        preset: RenderPreset,
        fallbackWebcamPlacement: PictureInPicturePlacement? = nil
    ) throws -> RenderPlan {
        let editDecisionList = EditDecisionListFile.exists(in: projectURL)
            ? try EditDecisionListFile.load(fromProject: projectURL)
            : nil
        let editorSettings = try EditorSettingsFile.loadIfPresent(fromProject: projectURL)
        var plan = try RenderPlan.make(
            manifest: manifest,
            projectURL: projectURL,
            destinationURL: destinationURL,
            preset: preset,
            editDecisionList: editDecisionList,
            editorSettings: editorSettings
        )
        if let fallbackWebcamPlacement,
           plan.webcamOverlay != nil,
           manifest.capture == nil,
           editorSettings?.camera == nil {
            plan.webcamOverlay?.placement = fallbackWebcamPlacement
        }
        return plan
    }
}
