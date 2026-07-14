import DMLessonMeldCore
import Foundation
import Testing

@Suite("Connector packages")
struct ConnectorPackageTests {
    @Test("Builds Common Cartridge package and archive")
    func buildsCommonCartridgePackage() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outputURL = temp.url.appendingPathComponent("connectors", isDirectory: true)

        let result = try CommonCartridgePackageBuilder().buildPackage(projectURL: projectURL, outputDirectory: outputURL)
        let packageURL = URL(fileURLWithPath: result.packagePath)

        #expect(result.archivePath?.hasSuffix(".imscc") == true)
        #expect(result.manifest.kind == .commonCartridge)
        #expect(result.manifest.primaryLaunchPath == "lesson/index.html")
        #expect(result.manifest.files.map(\.relativePath).contains("imsmanifest.xml"))
        #expect(result.manifest.files.map(\.relativePath).contains("lesson/index.html"))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("imsmanifest.xml").path))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: try #require(result.archivePath)).path))
    }

    @Test("Builds SCORM package with launch resource")
    func buildsSCORMPackage() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outputURL = temp.url.appendingPathComponent("connectors", isDirectory: true)

        let result = try SCORMPackageBuilder().buildPackage(projectURL: projectURL, outputDirectory: outputURL)
        let packageURL = URL(fileURLWithPath: result.packagePath)
        let manifest = try String(contentsOf: packageURL.appendingPathComponent("imsmanifest.xml"), encoding: .utf8)

        #expect(result.archivePath?.hasSuffix(".scorm.zip") == true)
        #expect(result.manifest.kind == .scorm)
        #expect(result.manifest.primaryLaunchPath == "scorm/index.html")
        #expect(manifest.contains("adlcp:scormType=\"sco\""))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("scorm/index.html").path))
    }

    @Test("Builds xAPI activity package")
    func buildsXAPIPackage() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outputURL = temp.url.appendingPathComponent("connectors", isDirectory: true)

        let result = try XAPIPackageBuilder().buildPackage(projectURL: projectURL, outputDirectory: outputURL)
        let packageURL = URL(fileURLWithPath: result.packagePath)
        let activityData = try Data(contentsOf: packageURL.appendingPathComponent("xapi/activity.json"))
        let activity = try #require(JSONSerialization.jsonObject(with: activityData) as? [String: Any])

        #expect(result.archivePath?.hasSuffix(".xapi.zip") == true)
        #expect(result.manifest.kind == .xapi)
        #expect((activity["id"] as? String)?.contains("lessonmeld.local/activity") == true)
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("xapi/statements.fixture.json").path))
    }

    @Test("Builds video host handoff metadata profiles")
    func buildsVideoHostHandoff() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outputURL = temp.url.appendingPathComponent("connectors", isDirectory: true)

        let result = try VideoHostHandoffBuilder().buildPackage(projectURL: projectURL, outputDirectory: outputURL)
        let packageURL = URL(fileURLWithPath: result.packagePath)
        let metadataData = try Data(contentsOf: packageURL.appendingPathComponent("video-host/metadata.json"))
        let metadata = try #require(JSONSerialization.jsonObject(with: metadataData) as? [String: Any])

        #expect(result.archivePath == nil)
        #expect(result.manifest.kind == .videoHost)
        #expect(metadata["primary_video"] as? String == "assets/media/screen.mp4")
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("video-host/youtube.json").path))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("checksums.sha256").path))

        let resultData = try JSONEncoder().encode(result)
        let resultJSON = try #require(JSONSerialization.jsonObject(with: resultData) as? [String: Any])
        #expect(resultJSON.keys.contains("archive_path"))
        #expect(resultJSON["archive_path"] is NSNull)
    }

    @Test("Re-export removes stale files from an existing connector package")
    func reexportRemovesStaleConnectorFiles() throws {
        let temp = try TemporaryDirectory()
        let projectURL = try makeProject(in: temp.url)
        let outputURL = temp.url.appendingPathComponent("connectors", isDirectory: true)
        let firstResult = try CommonCartridgePackageBuilder().buildPackage(
            projectURL: projectURL,
            outputDirectory: outputURL,
            archive: false
        )
        let staleURL = URL(fileURLWithPath: firstResult.packagePath)
            .appendingPathComponent("stale-secret.txt")
        try Data("stale".utf8).write(to: staleURL)

        let secondResult = try CommonCartridgePackageBuilder().buildPackage(
            projectURL: projectURL,
            outputDirectory: outputURL,
            archive: false
        )

        #expect(secondResult.packagePath == firstResult.packagePath)
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))
        #expect(!secondResult.manifest.files.map(\.relativePath).contains("stale-secret.txt"))
    }

    @Test("Rejects connector package without primary video")
    func rejectsMissingPrimaryVideo() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("No Video.dmlm", isDirectory: true)
        try ProjectBundle.writeManifest(
            ProjectManifest(metadata: LessonMetadata(lessonTitle: "No Video")),
            to: projectURL
        )

        #expect(throws: ConnectorPackageError.self) {
            try CommonCartridgePackageBuilder().buildPackage(
                projectURL: projectURL,
                outputDirectory: temp.url.appendingPathComponent("connectors", isDirectory: true)
            )
        }
    }

    private func makeProject(in rootURL: URL) throws -> URL {
        let projectURL = rootURL.appendingPathComponent("Connector Lesson.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("media", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("captions", isDirectory: true), withIntermediateDirectories: true)
        try Data("screen".utf8).write(to: projectURL.appendingPathComponent("media/screen.mp4"))
        try Data("WEBVTT".utf8).write(to: projectURL.appendingPathComponent("captions/captions.vtt"))
        try Data("Transcript".utf8).write(to: projectURL.appendingPathComponent("captions/transcript.txt"))
        let manifest = ProjectManifest(
            metadata: LessonMetadata(
                courseTitle: "Course",
                moduleTitle: "Module",
                lessonTitle: "Connector Lesson",
                instructor: "Instructor",
                summary: "Summary",
                tags: ["connector", "lesson"]
            ),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                captions: [ProjectFile(relativePath: "captions/captions.vtt", role: .captions, mimeType: "text/vtt")],
                transcripts: [ProjectFile(relativePath: "captions/transcript.txt", role: .transcript, mimeType: "text/plain")]
            ),
            markers: [
                ProjectTimelineMarker(id: "intro", kind: .chapter, timeSeconds: 0, title: "Intro")
            ]
        )
        try ProjectBundle.writeManifest(manifest, to: projectURL)
        return projectURL
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-connector-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
