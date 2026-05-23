import DMLessonMeldCore
import Foundation
import Testing

@Suite("Share exports")
struct ShareExportTests {
    @Test("Extracts raw project assets with checksums")
    func extractsRawAssets() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outputURL = temp.url.appendingPathComponent("exports", isDirectory: true)
        let staleURL = outputURL
            .appendingPathComponent("share-lesson-raw-assets", isDirectory: true)
            .appendingPathComponent("stale.txt")
        try FileManager.default.createDirectory(at: staleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: staleURL)

        let result = try RawAssetExtractor().extract(projectURL: projectURL, outputDirectory: outputURL)

        #expect(result.outputDirectoryPath.hasSuffix("share-lesson-raw-assets"))
        #expect(result.checksumPath == "checksums.sha256")
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))
        #expect(result.files.map(\.sourceRelativePath).contains("media/screen.mp4"))
        #expect(result.files.map(\.sourceRelativePath).contains("captions/captions.vtt"))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: result.outputDirectoryPath).appendingPathComponent("media/screen.mp4").path))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: result.outputDirectoryPath).appendingPathComponent("checksums.sha256").path))
        #expect(result.files.allSatisfy { !$0.sha256.isEmpty && $0.byteCount > 0 })
    }

    @Test("Builds local share package with final video, sidecars, and checksums")
    func buildsLocalSharePackage() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outputURL = temp.url.appendingPathComponent("shares", isDirectory: true)
        let finalVideoURL = temp.url.appendingPathComponent("final.mp4")
        let staleURL = outputURL
            .appendingPathComponent("share-lesson.lessonshare", isDirectory: true)
            .appendingPathComponent("raw-assets/stale-secret.txt")
        try FileManager.default.createDirectory(at: staleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: staleURL)
        try Data("final video".utf8).write(to: finalVideoURL)
        try EditorSettingsFile.save(EditorSettings(canvas: EditorCanvasSettings(aspectRatio: .widescreen16x9)), toProject: projectURL)
        try EditDecisionListFile.save(EditDecisionList(id: "edits"), toProject: projectURL)

        let result = try LocalSharePackageBuilder().buildPackage(
            projectURL: projectURL,
            outputDirectory: outputURL,
            finalVideoURL: finalVideoURL
        )
        let packageURL = URL(fileURLWithPath: result.packagePath)

        #expect(result.packagePath.hasSuffix("share-lesson.lessonshare"))
        #expect(result.manifest.finalVideoPath == "exports/final.mp4")
        #expect(result.manifest.checksumPath == "checksums.sha256")
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))
        #expect(result.manifest.files.map(\.relativePath).contains("project/project-manifest.json"))
        #expect(result.manifest.files.map(\.relativePath).contains("project/editor-settings.json"))
        #expect(result.manifest.files.map(\.relativePath).contains("project/edit-decision-list.json"))
        #expect(result.manifest.files.map(\.relativePath).contains("raw-assets/media/screen.mp4"))
        #expect(result.manifest.files.map(\.relativePath).contains("exports/final.mp4"))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("share-package.json").path))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("checksums.sha256").path))
        #expect(result.manifest.notes.contains { $0.contains("Review raw-assets") })
    }

    @Test("Rejects unsupported final video paths")
    func rejectsUnsupportedFinalVideoPaths() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let finalVideoURL = temp.url.appendingPathComponent("notes.txt")
        try Data("not a video".utf8).write(to: finalVideoURL)

        #expect(throws: ShareExportError.self) {
            try LocalSharePackageBuilder().buildPackage(
                projectURL: projectURL,
                outputDirectory: temp.url.appendingPathComponent("shares", isDirectory: true),
                finalVideoURL: finalVideoURL
            )
        }
    }

    @Test("Rejects share package symlink destinations")
    func rejectsSharePackageSymlinkDestinations() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outputURL = temp.url.appendingPathComponent("shares", isDirectory: true)
        let outsideURL = temp.url.appendingPathComponent("outside", isDirectory: true)
        let packageURL = outputURL.appendingPathComponent("share-lesson.lessonshare", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: packageURL, withDestinationURL: outsideURL)

        #expect(throws: ShareExportError.self) {
            try LocalSharePackageBuilder().buildPackage(projectURL: projectURL, outputDirectory: outputURL)
        }
    }

    @Test("Rejects symlinked project sidecars in share packages")
    func rejectsSymlinkedProjectSidecars() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outsideURL = temp.url.appendingPathComponent("outside-edits.json")
        try Data("{}".utf8).write(to: outsideURL)
        try FileManager.default.createSymbolicLink(
            at: projectURL.appendingPathComponent(EditDecisionListFile.defaultFileName),
            withDestinationURL: outsideURL
        )

        #expect(throws: ShareExportError.self) {
            try LocalSharePackageBuilder().buildPackage(
                projectURL: projectURL,
                outputDirectory: temp.url.appendingPathComponent("shares", isDirectory: true)
            )
        }
    }

    private func makeProject(in rootURL: URL) throws -> URL {
        let projectURL = rootURL.appendingPathComponent("Share Lesson.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("media", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("captions", isDirectory: true), withIntermediateDirectories: true)
        try Data("screen".utf8).write(to: projectURL.appendingPathComponent("media/screen.mp4"))
        try Data("caption".utf8).write(to: projectURL.appendingPathComponent("captions/captions.vtt"))
        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Share Lesson"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                captions: [ProjectFile(relativePath: "captions/captions.vtt", role: .captions, mimeType: "text/vtt")]
            )
        )
        try ProjectBundle.writeManifest(manifest, to: projectURL)
        return projectURL
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
