import DMLessonMeldCore
import Foundation
import Testing

@Suite("LearnHouse packages")
struct LearnHousePackageTests {
    @Test("Builds portable and LearnHouse-native package layers")
    func buildsPackageLayers() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let outputURL = temp.url.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        try Data("video".utf8).write(to: projectURL.appendingPathComponent("screen.mp4"))
        try Data("thumb".utf8).write(to: projectURL.appendingPathComponent("thumbnail.jpg"))
        try Data("WEBVTT".utf8).write(to: projectURL.appendingPathComponent("captions.vtt"))
        try Data("# Transcript".utf8).write(to: projectURL.appendingPathComponent("transcript.md"))

        let manifest = ProjectManifest(
            metadata: LessonMetadata(
                courseTitle: "Course",
                moduleTitle: "Module",
                lessonTitle: "Lesson",
                instructor: "Instructor",
                summary: "Summary",
                tags: ["workshop"]
            ),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                captions: [ProjectFile(relativePath: "captions.vtt", role: .captions, mimeType: "text/vtt")],
                transcripts: [ProjectFile(relativePath: "transcript.md", role: .transcript, mimeType: "text/markdown")],
                thumbnail: ProjectFile(relativePath: "thumbnail.jpg", role: .thumbnail, mimeType: "image/jpeg")
            )
        )
        try ProjectBundle.writeManifest(manifest, to: projectURL)

        let result = try LearnHousePackageBuilder().buildPackage(projectURL: projectURL, outputDirectory: outputURL)
        let packageURL = URL(fileURLWithPath: result.packagePath)

        #expect(result.manifest.schema == "io.digitalmeld.dm-lessonmeld.learnhouse-package")
        #expect(result.manifest.course.title == "Course")
        #expect(result.manifest.artifacts.video?.path == "assets/screen.mp4")
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("assets/screen.mp4").path))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("assets/checksums.sha256").path))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("learnhouse/manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("learnhouse/courses/course-course/course.json").path))
    }

    @Test("Builds zipped LearnHouse archive")
    func buildsArchive() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outputURL = temp.url.appendingPathComponent("exports", isDirectory: true)

        let result = try LearnHousePackageBuilder().buildArchive(projectURL: projectURL, outputDirectory: outputURL)

        let archivePath = try #require(result.archivePath)
        #expect(archivePath.hasSuffix(".learnhouse.zip"))
        #expect(FileManager.default.fileExists(atPath: archivePath))
        #expect((try FileManager.default.attributesOfItem(atPath: archivePath)[.size] as? UInt64) ?? 0 > 0)
    }

    @Test("Writes stable package manifest field names")
    func writesStableManifestFieldNames() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outputURL = temp.url.appendingPathComponent("exports", isDirectory: true)

        let result = try LearnHousePackageBuilder().buildPackage(projectURL: projectURL, outputDirectory: outputURL)
        let manifestURL = URL(fileURLWithPath: result.packagePath).appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let learnHouse = try #require(json["learn_house"] as? [String: Any])
        let lesson = try #require(json["lesson"] as? [String: Any])
        let video = try #require((json["artifacts"] as? [String: Any])?["video"] as? [String: Any])
        let file = try #require((json["files"] as? [[String: Any]])?.first)

        #expect(json["schema_version"] as? Int == 1)
        #expect(json["source_project"] as? String == "Lesson.dmlm")
        #expect(learnHouse["course_uuid"] as? String == "course-course")
        #expect(learnHouse["default_activity_subtype"] as? String == "SUBTYPE_VIDEO_HOSTED")
        #expect(lesson["learning_objectives"] != nil)
        #expect(video["mime_type"] as? String == "video/mp4")
        #expect(file["relative_path"] as? String == "assets/screen.mp4")
        #expect(file["byte_count"] as? Int == 5)
    }

    @Test("Rejects project media paths outside the bundle")
    func rejectsMediaPathsOutsideBundle() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Unsafe.dmlm", isDirectory: true)
        let outputURL = temp.url.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: temp.url.appendingPathComponent("secret.mp4"))
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Unsafe"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "../secret.mp4", role: .screenVideo, mimeType: "video/mp4")
                )
            ),
            to: projectURL
        )

        #expect(throws: ProjectBundleError.self) {
            try LearnHousePackageBuilder().buildPackage(projectURL: projectURL, outputDirectory: outputURL)
        }
    }
}

private func makeProject(in tempURL: URL) throws -> URL {
    let projectURL = tempURL.appendingPathComponent("Lesson.dmlm", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    try Data("video".utf8).write(to: projectURL.appendingPathComponent("screen.mp4"))
    let manifest = ProjectManifest(
        metadata: LessonMetadata(
            courseTitle: "Course",
            moduleTitle: "Module",
            lessonTitle: "Lesson",
            instructor: "Instructor",
            summary: "Summary",
            tags: ["workshop"]
        ),
        media: ProjectMedia(
            screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo, mimeType: "video/mp4")
        )
    )
    try ProjectBundle.writeManifest(manifest, to: projectURL)
    return projectURL
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
