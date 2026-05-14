import DMLessonMeldCore
import Foundation
import Testing

@Suite("Lesson presets")
struct LessonPresetTests {
    @Test("Creates a reusable preset from a project without copying media or metadata")
    func createsPresetFromProjectSettings() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Source.dmlm", isDirectory: true)
        let settings = EditorSettings(
            canvas: EditorCanvasSettings(aspectRatio: .portrait9x16),
            captions: EditorCaptionSettings(fontName: "Helvetica", fontSize: 42)
        )
        let preferences = LessonMeldPreferences(
            capture: CapturePreferences(fps: 30, captureWebcam: false),
            annotation: AnnotationPreferences(defaultColorHex: "#22D3EE"),
            export: ExportPreferences(defaultRenderQuality: .medium, defaultFileType: .mov)
        )
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Private Metadata"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo)
                ),
                exportPresets: ["learnhouse-1080p", "web-1080p"]
            ),
            to: projectURL
        )
        try EditorSettingsFile.save(settings, toProject: projectURL)

        let preset = try LessonPreset.make(
            fromProject: projectURL,
            preferences: preferences,
            name: "Workshop vertical",
            summary: "Reusable lesson style",
            id: "workshop-vertical",
            createdAt: Date(timeIntervalSince1970: 10)
        )

        #expect(preset.id == "workshop-vertical")
        #expect(preset.name == "Workshop vertical")
        #expect(preset.summary == "Reusable lesson style")
        #expect(try #require(preset.editorSettings) == settings)
        #expect(preset.capturePreferences?.fps == 30)
        #expect(preset.annotationPreferences?.defaultColorHex == "#22D3EE")
        #expect(preset.exportPreferences?.defaultFileType == .mov)
        #expect(preset.exportPresetIDs == ["learnhouse-1080p", "web-1080p"])
    }

    @Test("Applies a preset without overwriting project media, transcripts, or metadata")
    func appliesPresetWithoutOverwritingProjectContent() throws {
        let temp = try TemporaryDirectory()
        let sourceURL = temp.url.appendingPathComponent("Preset.dmlpreset")
        let projectURL = temp.url.appendingPathComponent("Target.dmlm", isDirectory: true)
        let originalManifest = ProjectManifest(
            metadata: LessonMetadata(courseTitle: "Course", lessonTitle: "Keep Me"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo),
                captions: [ProjectFile(relativePath: "captions.vtt", role: .captions)],
                transcripts: [ProjectFile(relativePath: "transcript.json", role: .transcript)]
            ),
            capture: ProjectCaptureSettings(screenFPS: 60, captureWebcam: true),
            markers: [ProjectTimelineMarker(id: "marker-1", kind: .chapter, timeSeconds: 1, title: "Intro")],
            exportPresets: ["old-preset"]
        )
        let preset = LessonPreset(
            id: "support-lessons",
            name: "Support lessons",
            editorSettings: EditorSettings(
                canvas: EditorCanvasSettings(aspectRatio: .widescreen16x9),
                cursor: EditorCursorSettings(pointerVisible: false)
            ),
            capturePreferences: CapturePreferences(
                fps: 30,
                includeCursor: false,
                captureSystemAudio: true,
                captureWebcam: false
            ),
            exportPreferences: ExportPreferences(defaultRenderQuality: .medium),
            exportPresetIDs: ["web-1080p"]
        )
        try ProjectBundle.writeManifest(originalManifest, to: projectURL)
        try LessonPresetFile.save(preset, to: sourceURL)

        let loaded = try LessonPresetFile.load(from: sourceURL)
        let preview = try LessonPresetApplier.apply(loaded, toProject: projectURL)
        let updated = try ProjectBundle.loadManifest(at: projectURL)

        #expect(preview.writesEditorSettings)
        #expect(preview.updatesCaptureSettings)
        #expect(preview.updatesExportPresets)
        #expect(try EditorSettingsFile.load(fromProject: projectURL) == #require(preset.editorSettings))
        #expect(updated.metadata == originalManifest.metadata)
        #expect(updated.media == originalManifest.media)
        #expect(updated.markers == originalManifest.markers)
        #expect(updated.capture?.screenFPS == 30)
        #expect(updated.capture?.includeCursor == false)
        #expect(updated.capture?.captureSystemAudio == true)
        #expect(updated.capture?.captureWebcam == false)
        #expect(updated.exportPresets == ["web-1080p"])
    }

    @Test("Applies preset preferences to app settings")
    func appliesPresetPreferences() {
        let preset = LessonPreset(
            name: "Voiceover",
            capturePreferences: CapturePreferences(captureMicrophone: false, captureWebcam: false),
            annotationPreferences: AnnotationPreferences(defaultColorHex: "#ef4444"),
            exportPreferences: ExportPreferences(defaultFileType: .mov)
        )

        let updated = LessonPresetApplier.applyPreferences(preset, to: LessonMeldPreferences())

        #expect(updated.capture.captureMicrophone == false)
        #expect(updated.capture.captureWebcam == false)
        #expect(updated.annotation.defaultColorHex == "#EF4444")
        #expect(updated.export.defaultFileType == .mov)
    }

    @Test("App settings presets do not write project editor settings")
    func settingsPresetDoesNotWriteEditorSettings() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Target.dmlm", isDirectory: true)
        try ProjectBundle.writeManifest(
            ProjectManifest(metadata: LessonMetadata(lessonTitle: "Target")),
            to: projectURL
        )
        let preset = LessonPreset(
            name: "App defaults",
            capturePreferences: CapturePreferences(fps: 30),
            exportPreferences: ExportPreferences(defaultFileType: .mov)
        )

        let preview = try LessonPresetApplier.apply(preset, toProject: projectURL)

        #expect(!preview.writesEditorSettings)
        #expect(!EditorSettingsFile.exists(in: projectURL))
        #expect(try ProjectBundle.loadManifest(at: projectURL).capture?.screenFPS == 30)
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
