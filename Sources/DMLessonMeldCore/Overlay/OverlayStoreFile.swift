import Foundation

public enum OverlayStoreFile {
    public static let defaultFileName = "overlays.json"

    public static func url(inProject projectURL: URL) -> URL {
        projectURL.appendingPathComponent(defaultFileName)
    }

    public static func exists(in projectURL: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: url(inProject: projectURL).path)
    }

    public static func loadIfPresent(fromProject projectURL: URL, fileManager: FileManager = .default) throws -> OverlayStore? {
        guard exists(in: projectURL, fileManager: fileManager) else { return nil }
        return try load(fromProject: projectURL)
    }

    public static func load(fromProject projectURL: URL) throws -> OverlayStore {
        let data = try RenderSidecarLimits.data(contentsOf: url(inProject: projectURL), displayPath: defaultFileName)
        let store = try DMLessonJSON.decoder().decode(OverlayStore.self, from: data)
        try RenderSidecarLimits.checkOverlayStore(store, displayPath: defaultFileName)
        return store
    }

    public static func save(_ store: OverlayStore, toProject projectURL: URL) throws {
        let destination = url(inProject: projectURL)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let data = try DMLessonJSON.encoder().encode(store)
        try data.write(to: destination, options: [.atomic])
    }
}
