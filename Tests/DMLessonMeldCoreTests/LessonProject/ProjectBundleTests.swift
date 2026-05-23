import DMLessonMeldCore
import Foundation
import Testing

@Suite("Project bundle")
struct ProjectBundleTests {
    @Test("Writes, loads, and inspects a project manifest")
    func writesLoadsAndInspectsManifest() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Sample.dmlm", isDirectory: true)
        let videoURL = projectURL.appendingPathComponent("screen.mp4")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: videoURL)

        let manifest = ProjectManifest(
            metadata: LessonMetadata(courseTitle: "Course", lessonTitle: "Lesson"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo, mimeType: "video/mp4")
            ),
            markers: [
                ProjectTimelineMarker(id: "chapter-1", kind: .chapter, timeSeconds: 0, title: "Start")
            ]
        )

        try ProjectBundle.writeManifest(manifest, to: projectURL)

        let loaded = try ProjectBundle.loadManifest(at: projectURL)
        let summary = try ProjectBundle.inspect(at: projectURL)

        #expect(loaded.metadata.lessonTitle == "Lesson")
        #expect(summary.fileCount == 1)
        #expect(summary.markerCount == 1)
        #expect(summary.issues.isEmpty)
    }

    @Test("Manifest records embedded system audio without a sidecar file")
    func manifestRecordsEmbeddedSystemAudioWithoutSidecarFile() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Embedded Audio.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: projectURL.appendingPathComponent("screen.mp4"))

        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Embedded Audio"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                embeddedAudio: ProjectEmbeddedAudio(screenVideo: [.systemAudio, .systemAudio])
            )
        )

        try ProjectBundle.writeManifest(manifest, to: projectURL)

        let loaded = try ProjectBundle.loadManifest(at: projectURL)
        let summary = try ProjectBundle.inspect(at: projectURL)

        #expect(loaded.media.hasEmbeddedSystemAudio)
        #expect(loaded.media.embeddedAudio?.screenVideo == [.systemAudio])
        #expect(loaded.media.systemAudio == nil)
        #expect(loaded.media.allFiles.map(\.relativePath) == ["screen.mp4"])
        #expect(summary.fileCount == 1)
        #expect(summary.issues.isEmpty)
    }

    @Test("Validation reports missing referenced files as warnings")
    func validationReportsMissingFiles() {
        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Missing File"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo)
            )
        )

        let issues = ProjectBundle.validate(manifest: manifest, projectURL: URL(fileURLWithPath: "/tmp/missing-project"))

        #expect(issues.count == 1)
        #expect(issues.first?.severity == .warning)
    }

    @Test("File URL resolution stays inside project bundles")
    func resolvesProjectFileURLs() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Sample.dmlm", isDirectory: true)
        let externalURL = temp.url.appendingPathComponent("external-screen.mp4")
        try Data("video".utf8).write(to: externalURL)

        let relativeFile = ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo)
        let absoluteFile = ProjectFile(relativePath: externalURL.path, role: .screenVideo)

        #expect(ProjectBundle.fileURL(for: relativeFile, in: projectURL) == projectURL.appendingPathComponent("media/screen.mp4"))
        #expect(ProjectBundle.fileURL(for: absoluteFile, in: projectURL) != externalURL)
        #expect(throws: ProjectBundleError.self) {
            try ProjectBundle.projectLocalFileURL(for: absoluteFile, in: projectURL)
        }

        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Unsafe Attachment"),
            media: ProjectMedia(screen: absoluteFile)
        )
        let issues = ProjectBundle.validate(manifest: manifest, projectURL: projectURL)
        #expect(issues.contains { $0.severity == .error && $0.path == externalURL.path })
    }

    @Test("Validation rejects parent traversal media references")
    func validationRejectsParentTraversalReferences() {
        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Traversal"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "../screen.mp4", role: .screenVideo)
            )
        )

        let issues = ProjectBundle.validate(manifest: manifest, projectURL: URL(fileURLWithPath: "/tmp/Lesson.dmlm"))

        #expect(issues.contains { $0.severity == .error && $0.path == "../screen.mp4" })
    }

    @Test("Validation rejects control characters in media references")
    func validationRejectsControlCharacterReferences() {
        let unsafePath = "media/screen\nforged.mp4"
        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Control Character"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: unsafePath, role: .screenVideo)
            )
        )

        let issues = ProjectBundle.validate(manifest: manifest, projectURL: URL(fileURLWithPath: "/tmp/Lesson.dmlm"))

        #expect(issues.contains { $0.severity == .error && $0.path == unsafePath })
        #expect(throws: ProjectBundleError.self) {
            try ProjectBundle.projectLocalFileURL(
                for: ProjectFile(relativePath: unsafePath, role: .screenVideo),
                in: URL(fileURLWithPath: "/tmp/Lesson.dmlm")
            )
        }
    }

    @Test("Repairs a bundle manifest from recoverable raw media")
    func repairsManifestFromRecoverableMedia() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Recovered Lesson.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try Data("screen".utf8).write(to: projectURL.appendingPathComponent("screen.mp4"))
        try Data("webcam".utf8).write(to: projectURL.appendingPathComponent("webcam.mov"))
        try Data("mic".utf8).write(to: projectURL.appendingPathComponent("microphone.m4a"))
        try Data("{}".utf8).write(to: projectURL.appendingPathComponent("cursor-metadata.json"))
        try Data("{}".utf8).write(to: projectURL.appendingPathComponent("annotations.json"))
        try DMLessonJSON.encoder().encode(OverlayStore(overlays: [
            OverlayItem(
                id: "title",
                kind: .text,
                timeRange: EditTimeRange(startSeconds: 0, durationSeconds: 3)
            )
        ])).write(to: projectURL.appendingPathComponent("overlays.json"))

        let result = try ProjectBundle.repair(at: projectURL)
        let manifest = try ProjectBundle.loadManifest(at: projectURL)

        #expect(result.wroteManifest)
        #expect(result.recoveredFiles.map(\.role).contains(.screenVideo))
        #expect(manifest.metadata.lessonTitle == "Recovered Lesson")
        #expect(manifest.media.screen?.relativePath == "screen.mp4")
        #expect(manifest.media.webcam?.relativePath == "webcam.mov")
        #expect(manifest.media.microphoneAudio?.relativePath == "microphone.m4a")
        #expect(manifest.media.cursorMetadata?.relativePath == "cursor-metadata.json")
        #expect(manifest.media.annotations?.relativePath == "annotations.json")
        #expect(manifest.media.overlays?.relativePath == "overlays.json")
        #expect(manifest.tracks.map(\.kind).contains(.screen))
        #expect(manifest.tracks.map(\.kind).contains(.cursor))
        #expect(manifest.tracks.map(\.kind).contains(.overlays))
        #expect(result.issues.isEmpty)
    }

    @Test("Repair is non-mutating when manifest already exists")
    func repairSkipsExistingManifest() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Existing.dmlm", isDirectory: true)
        try ProjectBundle.writeManifest(
            ProjectManifest(metadata: LessonMetadata(lessonTitle: "Existing")),
            to: projectURL
        )

        let result = try ProjectBundle.repair(at: projectURL, lessonTitle: "Changed")

        #expect(!result.wroteManifest)
        #expect(result.manifest.metadata.lessonTitle == "Existing")
        #expect(result.recoveredFiles.isEmpty)
    }

    @Test("Repair attaches recoverable media to an incomplete manifest")
    func repairAttachesRecoverableMediaToExistingManifest() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Interrupted.dmlm", isDirectory: true)
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Interrupted"),
                capture: ProjectCaptureSettings(captureMicrophone: true, captureWebcam: true)
            ),
            to: projectURL
        )
        try Data("screen".utf8).write(to: projectURL.appendingPathComponent("screen.mp4"))
        try Data("webcam".utf8).write(to: projectURL.appendingPathComponent("webcam.mov"))

        let result = try ProjectBundle.repair(at: projectURL)
        let manifest = try ProjectBundle.loadManifest(at: projectURL)

        #expect(result.wroteManifest)
        #expect(result.recoveredFiles.map(\.relativePath).contains("screen.mp4"))
        #expect(manifest.metadata.lessonTitle == "Interrupted")
        #expect(manifest.capture?.captureWebcam == true)
        #expect(manifest.media.screen?.relativePath == "screen.mp4")
        #expect(manifest.media.webcam?.relativePath == "webcam.mov")
        #expect(manifest.tracks.map(\.kind).contains(.screen))
        #expect(manifest.tracks.map(\.kind).contains(.webcam))
        #expect(result.issues.isEmpty)
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
