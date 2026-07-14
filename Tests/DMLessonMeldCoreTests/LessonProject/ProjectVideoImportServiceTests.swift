@testable import DMLessonMeldCore
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
        #expect(result.manifest.metadata.lessonTitle == "Intro Video")
        #expect(loaded.media.screen?.relativePath == "screen.mp4")
        #expect(loaded.media.screen?.mimeType == "video/mp4")
        #expect(loaded.media.screen?.byteCount == 5)
        #expect(loaded.tracks.map(\.kind).contains(.screen))
        #expect(loaded.exportPresets.contains("learnhouse-1080p"))
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
        let preexistingMediaURL = projectURL.appendingPathComponent("screen.mov")
        try Data("keep".utf8).write(to: preexistingMediaURL)
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
        #expect(result.manifest.media.screen?.relativePath == "screen-2.mov")
        #expect(result.manifest.media.screen?.mimeType == "video/quicktime")
        #expect(result.manifest.tracks.map(\.kind).contains(.screen))
        #expect(result.manifest.exportPresets.contains("learnhouse-1080p"))
        #expect(try Data(contentsOf: preexistingMediaURL) == Data("keep".utf8))
        #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("screen-2.mov").path))
    }

    @Test("Missing sources leave no partial project bundle")
    func missingSourcesLeaveNoPartialProjectBundle() throws {
        let temp = try TemporaryDirectory()
        let template = try #require(LessonTemplateLibrary.defaultTemplates.first)
        let request = ProjectVideoImportRequest(
            sourceURL: temp.url.appendingPathComponent("Missing Video.mp4"),
            defaultProjectDirectory: temp.url.path,
            defaultTemplateID: template.id
        )

        #expect(throws: ProjectVideoImportError.mediaCopyFailed(cleanupIncomplete: false)) {
            try ProjectVideoImportService.importVideo(request)
        }
        #expect(!FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("missing-video.dmlm").path))
        #expect(try importArtifacts(in: temp.url).isEmpty)
    }

    @Test("Partial copy failures remove staging artifacts")
    func partialCopyFailuresRemoveStagingArtifacts() throws {
        let temp = try TemporaryDirectory()
        let sourceURL = temp.url.appendingPathComponent("Copy Failure.mp4")
        try Data("video".utf8).write(to: sourceURL)
        let template = try #require(LessonTemplateLibrary.defaultTemplates.first)
        var operations = ProjectVideoImportOperations.live
        operations.copyItem = { _, destination in
            try Data("partial".utf8).write(to: destination)
            throw InjectedImportFailure.expected
        }

        #expect(throws: ProjectVideoImportError.mediaCopyFailed(cleanupIncomplete: false)) {
            try ProjectVideoImportService.importVideo(
                ProjectVideoImportRequest(
                    sourceURL: sourceURL,
                    defaultProjectDirectory: temp.url.path,
                    defaultTemplateID: template.id
                ),
                operations: operations
            )
        }
        #expect(!FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("copy-failure.dmlm").path))
        #expect(try importArtifacts(in: temp.url).isEmpty)
    }

    @Test("New project manifest failures remove the staged bundle")
    func newProjectManifestFailuresRemoveStagedBundle() throws {
        let temp = try TemporaryDirectory()
        let sourceURL = temp.url.appendingPathComponent("Manifest Failure.mp4")
        try Data("video".utf8).write(to: sourceURL)
        let template = try #require(LessonTemplateLibrary.defaultTemplates.first)
        var operations = ProjectVideoImportOperations.live
        operations.writeManifest = { _, _ in throw InjectedImportFailure.expected }

        #expect(throws: ProjectVideoImportError.manifestWriteFailed(cleanupIncomplete: false)) {
            try ProjectVideoImportService.importVideo(
                ProjectVideoImportRequest(
                    sourceURL: sourceURL,
                    defaultProjectDirectory: temp.url.path,
                    defaultTemplateID: template.id
                ),
                operations: operations
            )
        }
        #expect(!FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("manifest-failure.dmlm").path))
        #expect(try importArtifacts(in: temp.url).isEmpty)
    }

    @Test("Attach manifest failures preserve the complete existing project")
    func attachManifestFailuresPreserveExistingProject() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Existing.dmlm", isDirectory: true)
        let sourceURL = temp.url.appendingPathComponent("Attach Failure.mov")
        try Data("video".utf8).write(to: sourceURL)
        let manifest = ProjectManifest(metadata: LessonMetadata(lessonTitle: "Existing"))
        try ProjectBundle.writeManifest(manifest, to: projectURL)
        try Data("notes".utf8).write(to: projectURL.appendingPathComponent("notes.md"))
        let originalSnapshot = try projectSnapshot(at: projectURL)
        let template = try #require(LessonTemplateLibrary.defaultTemplates.first)
        var operations = ProjectVideoImportOperations.live
        operations.writeManifest = { _, _ in throw InjectedImportFailure.expected }

        #expect(throws: ProjectVideoImportError.manifestWriteFailed(cleanupIncomplete: false)) {
            try ProjectVideoImportService.importVideo(
                ProjectVideoImportRequest(
                    sourceURL: sourceURL,
                    defaultProjectDirectory: temp.url.path,
                    defaultTemplateID: template.id,
                    existingProjectURL: projectURL,
                    existingManifest: manifest
                ),
                operations: operations
            )
        }
        #expect(try projectSnapshot(at: projectURL) == originalSnapshot)
        #expect(try importArtifacts(in: projectURL).isEmpty)
    }

    @Test("Destination collisions preserve the competing project and remove staging")
    func destinationCollisionsPreserveCompetingProject() throws {
        let temp = try TemporaryDirectory()
        let sourceURL = temp.url.appendingPathComponent("Collision.mp4")
        try Data("video".utf8).write(to: sourceURL)
        let destinationURL = temp.url.appendingPathComponent("collision.dmlm", isDirectory: true)
        let markerURL = destinationURL.appendingPathComponent("owner.txt")
        let template = try #require(LessonTemplateLibrary.defaultTemplates.first)
        var operations = ProjectVideoImportOperations.live
        operations.moveItem = { _, destination in
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            try Data("competing project".utf8).write(to: destination.appendingPathComponent("owner.txt"))
            throw InjectedImportFailure.expected
        }

        #expect(throws: ProjectVideoImportError.destinationChanged(cleanupIncomplete: false)) {
            try ProjectVideoImportService.importVideo(
                ProjectVideoImportRequest(
                    sourceURL: sourceURL,
                    defaultProjectDirectory: temp.url.path,
                    defaultTemplateID: template.id
                ),
                operations: operations
            )
        }
        #expect(try Data(contentsOf: markerURL) == Data("competing project".utf8))
        #expect(try importArtifacts(in: temp.url).isEmpty)
    }

    @Test("Attach collisions preserve the existing manifest and competing media")
    func attachCollisionsPreserveExistingProject() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Existing.dmlm", isDirectory: true)
        let sourceURL = temp.url.appendingPathComponent("Attach Collision.mp4")
        try Data("video".utf8).write(to: sourceURL)
        let manifest = ProjectManifest(metadata: LessonMetadata(lessonTitle: "Existing"))
        try ProjectBundle.writeManifest(manifest, to: projectURL)
        let template = try #require(LessonTemplateLibrary.defaultTemplates.first)
        let competingMediaURL = projectURL.appendingPathComponent("screen.mp4")
        var operations = ProjectVideoImportOperations.live
        operations.moveItem = { _, destination in
            try Data("competing media".utf8).write(to: destination)
            throw InjectedImportFailure.expected
        }

        #expect(throws: ProjectVideoImportError.destinationChanged(cleanupIncomplete: false)) {
            try ProjectVideoImportService.importVideo(
                ProjectVideoImportRequest(
                    sourceURL: sourceURL,
                    defaultProjectDirectory: temp.url.path,
                    defaultTemplateID: template.id,
                    existingProjectURL: projectURL,
                    existingManifest: manifest
                ),
                operations: operations
            )
        }
        #expect(try ProjectBundle.loadManifest(at: projectURL).media.screen == nil)
        #expect(try Data(contentsOf: competingMediaURL) == Data("competing media".utf8))
        #expect(try importArtifacts(in: projectURL).isEmpty)
    }

    @Test("Cleanup failures are surfaced without exposing local paths")
    func cleanupFailuresAreSurfacedWithoutLocalPaths() throws {
        let temp = try TemporaryDirectory()
        let sourceURL = temp.url.appendingPathComponent("Cleanup Failure.mp4")
        try Data("video".utf8).write(to: sourceURL)
        let template = try #require(LessonTemplateLibrary.defaultTemplates.first)
        var operations = ProjectVideoImportOperations.live
        operations.copyItem = { _, destination in
            try Data("partial".utf8).write(to: destination)
            throw InjectedImportFailure.expected
        }
        operations.removeItem = { _ in throw InjectedImportFailure.expected }
        let expectedError = ProjectVideoImportError.mediaCopyFailed(cleanupIncomplete: true)

        #expect(throws: expectedError) {
            try ProjectVideoImportService.importVideo(
                ProjectVideoImportRequest(
                    sourceURL: sourceURL,
                    defaultProjectDirectory: temp.url.path,
                    defaultTemplateID: template.id
                ),
                operations: operations
            )
        }
        #expect(expectedError.localizedDescription.contains("could not be fully removed"))
        #expect(!expectedError.localizedDescription.contains(temp.url.path))
        #expect(!(try importArtifacts(in: temp.url)).isEmpty)
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

    private func importArtifacts(in rootURL: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
            .filter { $0.hasPrefix(".dm-lessonmeld-import-") }
            .sorted()
    }

    private func projectSnapshot(at projectURL: URL) throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return [:]
        }
        var snapshot: [String: Data] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = String(url.path.dropFirst(projectURL.path.count + 1))
            snapshot[relativePath] = try Data(contentsOf: url)
        }
        return snapshot
    }
}

private enum InjectedImportFailure: Error {
    case expected
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
