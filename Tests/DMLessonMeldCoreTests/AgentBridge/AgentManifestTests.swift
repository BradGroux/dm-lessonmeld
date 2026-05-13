import DMLessonMeldCore
import Foundation
import Testing

@Suite("Agent manifest")
struct AgentManifestTests {
    @Test("Redacts media paths by default")
    func redactsMediaPathsByDefault() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Agent.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: projectURL.appendingPathComponent("screen.mp4"))
        try Data("transcript".utf8).write(to: projectURL.appendingPathComponent("transcript.md"))

        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Agent Safe"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo),
                transcripts: [ProjectFile(relativePath: "transcript.md", role: .transcript)]
            )
        )
        try ProjectBundle.writeManifest(manifest, to: projectURL)

        let agentManifest = try AgentManifestBuilder.build(projectURL: projectURL)

        #expect(agentManifest.files.count == 2)
        #expect(agentManifest.files.allSatisfy { $0.path == nil })
        #expect(agentManifest.availableCommands.contains { $0.name == "learnhouse package" })
    }

    @Test("Can include media paths by explicit request while keeping transcript references redacted")
    func includesMediaPathsWhenRequested() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Agent.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: projectURL.appendingPathComponent("screen.mp4"))
        try Data("transcript".utf8).write(to: projectURL.appendingPathComponent("transcript.md"))

        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Agent Safe"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo),
                transcripts: [ProjectFile(relativePath: "transcript.md", role: .transcript)]
            )
        )
        try ProjectBundle.writeManifest(manifest, to: projectURL)

        let agentManifest = try AgentManifestBuilder.build(
            projectURL: projectURL,
            options: AgentManifestOptions(includeMediaPaths: true)
        )

        #expect(agentManifest.files.contains { $0.role == .screenVideo && $0.path == "screen.mp4" })
        #expect(agentManifest.files.contains { $0.role == .transcript && $0.path == nil })
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
