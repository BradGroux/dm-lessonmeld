import DMLessonMeldCore
import Foundation
import Testing

@Suite("Project video import service")
struct ProjectVideoImportServiceTests {
    @Test("Imports video into a new project bundle")
    func importsVideoIntoNewProjectBundle() throws {
        let temp = try TemporaryDirectory()
        let sourceURL = temp.url.appendingPathComponent("Intro Video.mp4")
        try Data("video".utf8).write(to: sourceURL)
        let template = try #require(LessonTemplateLibrary.defaultTemplates.first)

        let result = try ProjectVideoImportService.importVideo(
            ProjectVideoImportRequest(
                sourceURL: sourceURL,
                defaultProjectDirectory: temp.url.path,
                defaultTemplateID: template.id
            )
        )
        let loaded = try ProjectBundle.loadManifest(at: result.projectURL)

        #expect(result.projectURL.lastPathComponent == "intro-video.dmlm")
        #expect(loaded.media.screen?.relativePath == "screen.mp4")
        #expect(loaded.media.screen?.mimeType == "video/mp4")
        #expect(loaded.tracks.map(\.kind).contains(.screen))
        #expect(FileManager.default.fileExists(atPath: result.projectURL.appendingPathComponent("screen.mp4").path))
    }

    @Test("Attaches imported video to current project without a screen track")
    func attachesImportedVideoToCurrentProjectWithoutScreenTrack() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Existing.dmlm", isDirectory: true)
        let sourceURL = temp.url.appendingPathComponent("Clip.mov")
        try Data("video".utf8).write(to: sourceURL)
        let existingManifest = ProjectManifest(metadata: LessonMetadata(lessonTitle: "Existing"))
        try ProjectBundle.writeManifest(existingManifest, to: projectURL)
        let template = try #require(LessonTemplateLibrary.defaultTemplates.first)

        let result = try ProjectVideoImportService.importVideo(
            ProjectVideoImportRequest(
                sourceURL: sourceURL,
                defaultProjectDirectory: temp.url.path,
                defaultTemplateID: template.id,
                existingProjectURL: projectURL,
                existingManifest: existingManifest
            )
        )

        #expect(result.projectURL == projectURL)
        #expect(result.manifest.metadata.lessonTitle == "Existing")
        #expect(result.manifest.media.screen?.relativePath == "screen.mov")
        #expect(result.manifest.media.screen?.mimeType == "video/quicktime")
        #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("screen.mov").path))
    }

    @Test("Rejects unsupported import formats")
    func rejectsUnsupportedImportFormats() throws {
        let temp = try TemporaryDirectory()
        let sourceURL = temp.url.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: sourceURL)
        let template = try #require(LessonTemplateLibrary.defaultTemplates.first)

        #expect(throws: ProjectVideoImportError.unsupportedVideoType("notes.txt")) {
            try ProjectVideoImportService.importVideo(
                ProjectVideoImportRequest(
                    sourceURL: sourceURL,
                    defaultProjectDirectory: temp.url.path,
                    defaultTemplateID: template.id
                )
            )
        }
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
