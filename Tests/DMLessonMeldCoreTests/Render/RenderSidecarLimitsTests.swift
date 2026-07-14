import Darwin
import DMLessonMeldCore
import Foundation
import Testing

@Suite("Render sidecar file trust")
struct RenderSidecarLimitsTests {
    @Test("Reads regular sidecars")
    func readsRegularSidecars() throws {
        let temp = try TemporarySidecarDirectory()
        let sidecarURL = temp.url.appendingPathComponent("annotations.json")
        let expected = Data("trusted sidecar".utf8)
        try expected.write(to: sidecarURL)

        let data = try RenderSidecarLimits.data(contentsOf: sidecarURL, displayPath: "annotations.json")

        #expect(data == expected)
    }

    @Test("Rejects symlinked sidecars before reading their targets")
    func rejectsSymlinkedSidecars() throws {
        let temp = try TemporarySidecarDirectory()
        let targetURL = temp.url.appendingPathComponent("outside.json")
        let sidecarURL = temp.url.appendingPathComponent("annotations.json")
        try Data("private target".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: sidecarURL, withDestinationURL: targetURL)

        #expect(throws: RenderSidecarLimitError.unsafeFile(path: "annotations.json")) {
            try RenderSidecarLimits.data(contentsOf: sidecarURL, displayPath: "annotations.json")
        }
    }

    @Test("Rejects directories as sidecars")
    func rejectsDirectorySidecars() throws {
        let temp = try TemporarySidecarDirectory()
        let sidecarURL = temp.url.appendingPathComponent("annotations.json", isDirectory: true)
        try FileManager.default.createDirectory(at: sidecarURL, withIntermediateDirectories: false)

        #expect(throws: RenderSidecarLimitError.unsafeFile(path: "annotations.json")) {
            try RenderSidecarLimits.data(contentsOf: sidecarURL, displayPath: "annotations.json")
        }
    }

    @Test("Rejects FIFOs without blocking")
    func rejectsFIFOSidecars() throws {
        let temp = try TemporarySidecarDirectory()
        let sidecarURL = temp.url.appendingPathComponent("annotations.json")
        try #require(mkfifo(sidecarURL.path, S_IRUSR | S_IWUSR) == 0)

        #expect(throws: RenderSidecarLimitError.unsafeFile(path: "annotations.json")) {
            try RenderSidecarLimits.data(contentsOf: sidecarURL, displayPath: "annotations.json")
        }
    }
}

private final class TemporarySidecarDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
