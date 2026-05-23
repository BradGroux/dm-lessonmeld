import Foundation

public enum EditDecisionListFile {
    public static let defaultFileName = "edit-decision-list.json"

    public static func defaultURL(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(defaultFileName)
    }

    public static func exists(in projectURL: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: defaultURL(in: projectURL).path)
    }

    public static func load(from url: URL) throws -> EditDecisionList {
        let data = try RenderSidecarLimits.data(contentsOf: url, displayPath: url.lastPathComponent)
        return try decoder().decode(EditDecisionList.self, from: data)
    }

    public static func load(fromProject projectURL: URL) throws -> EditDecisionList {
        try load(from: defaultURL(in: projectURL))
    }

    public static func save(_ editDecisionList: EditDecisionList, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder().encode(editDecisionList)
        try data.write(to: url, options: [.atomic])
    }

    public static func save(_ editDecisionList: EditDecisionList, toProject projectURL: URL) throws {
        try save(editDecisionList, to: defaultURL(in: projectURL))
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
