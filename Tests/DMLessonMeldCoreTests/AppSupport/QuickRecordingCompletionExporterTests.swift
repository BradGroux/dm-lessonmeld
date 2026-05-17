import DMLessonMeldCore
import DMLessonMeldSupport
import Foundation
import Testing

@Suite("Quick recording completion exporter")
struct QuickRecordingCompletionExporterTests {
    @Test("Writes project caption sidecars from a transcript")
    func writesProjectCaptionSidecars() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let transcript = TranscriptDocument(segments: [
            TranscriptSegment(id: "one", startSeconds: 1, endSeconds: 2, text: "Welcome.")
        ])

        let result = try QuickRecordingCompletionExporter.writeProjectCaptionSidecars(
            transcript: transcript,
            projectURL: projectURL
        )

        #expect(FileManager.default.fileExists(atPath: result.transcriptJSONURL.path))
        #expect(try String(contentsOf: result.captionsVTTURL, encoding: .utf8).contains("WEBVTT"))
        #expect(try String(contentsOf: result.captionsSRTURL, encoding: .utf8).contains("00:00:01,000"))
        #expect(try String(contentsOf: result.transcriptTextURL, encoding: .utf8) == "Welcome.\n")
    }

    @Test("Exports completion sidecars from a project transcript")
    func exportsCompletionSidecars() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let transcript = TranscriptDocument(segments: [
            TranscriptSegment(id: "one", startSeconds: 1, endSeconds: 2, text: "Welcome.")
        ])
        try DMLessonJSON.encoder()
            .encode(transcript)
            .write(to: projectURL.appendingPathComponent("transcript.json"), options: [.atomic])

        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Lesson"),
            media: ProjectMedia(
                transcripts: [ProjectFile(relativePath: "transcript.json", role: .transcript, mimeType: "application/json")]
            )
        )
        try ProjectBundle.writeManifest(manifest, to: projectURL)

        let outputDirectory = try QuickRecordingCompletionExporter.exportCompletionCaptionSidecars(projectURL: projectURL)

        #expect(outputDirectory.lastPathComponent == "Lesson")
        #expect(try String(contentsOf: outputDirectory.appendingPathComponent("transcript.md"), encoding: .utf8).contains("Welcome."))
        #expect(try String(contentsOf: outputDirectory.appendingPathComponent("captions.vtt"), encoding: .utf8).contains("WEBVTT"))
    }
}

@Suite("Quick recording completion service")
struct QuickRecordingCompletionServiceTests {
    @Test("Creates stable unique render destinations")
    func createsUniqueRenderDestinations() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson Bundle.dmlm", isDirectory: true)

        let first = try QuickRecordingCompletionService.uniqueRenderDestination(
            projectURL: projectURL,
            lessonTitle: "Intro & Setup",
            fileType: .mp4
        )
        try Data("existing".utf8).write(to: first, options: [.atomic])
        let second = try QuickRecordingCompletionService.uniqueRenderDestination(
            projectURL: projectURL,
            lessonTitle: "Intro & Setup",
            fileType: .mp4
        )

        #expect(first.lastPathComponent == "intro-setup.mp4")
        #expect(second.lastPathComponent == "intro-setup-2.mp4")
    }

    @Test("Builds completion render presets from preferences")
    func buildsRenderPresetFromPreferences() {
        var preferences = ExportPreferences()
        preferences.defaultFileType = .mov
        preferences.defaultRenderQuality = .medium

        let preset = QuickRecordingCompletionService.renderPreset(from: preferences)

        #expect(preset.fileType == .mov)
        #expect(preset.quality == .medium)
    }

    @Test("Planner applies fallback webcam placement for legacy recording projects")
    func plannerAppliesFallbackWebcamPlacement() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let destinationURL = temp.url.appendingPathComponent("lesson.mp4")
        let fallback = PictureInPicturePlacement(
            corner: .topLeading,
            widthRatio: 0.31,
            marginRatio: 0.06,
            aspectRatio: .square1x1,
            frameShape: .circle,
            cornerRadius: 20,
            isMirrored: true,
            borderEnabled: true,
            shadowEnabled: false
        )
        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Legacy Camera"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                webcam: ProjectFile(relativePath: "webcam.mov", role: .webcamVideo, mimeType: "video/quicktime")
            )
        )

        let plan = try ProjectEditorRenderPlanner.makePlan(
            projectURL: projectURL,
            manifest: manifest,
            destinationURL: destinationURL,
            preset: RenderPreset(),
            fallbackWebcamPlacement: fallback
        )

        #expect(plan.webcamOverlay?.placement == fallback)
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-completion-exporter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
