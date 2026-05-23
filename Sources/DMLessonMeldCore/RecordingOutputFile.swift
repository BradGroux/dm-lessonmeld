import Foundation

struct RecordingOutputFile: Sendable {
    let destinationURL: URL
    let temporaryURL: URL

    static func prepare(destinationURL: URL) throws -> Self {
        let directoryURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let baseName = destinationURL.deletingPathExtension().lastPathComponent
        let pathExtension = destinationURL.pathExtension
        let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        var temporaryURL: URL
        repeat {
            temporaryURL = directoryURL.appendingPathComponent(".\(baseName).\(UUID().uuidString).recording\(suffix)")
        } while FileManager.default.fileExists(atPath: temporaryURL.path)

        return Self(destinationURL: destinationURL, temporaryURL: temporaryURL)
    }

    func commit() throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
        return destinationURL
    }

    func discard() {
        try? FileManager.default.removeItem(at: temporaryURL)
    }
}
