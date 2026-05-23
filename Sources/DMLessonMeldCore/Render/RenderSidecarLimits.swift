import Foundation

public enum RenderSidecarLimits {
    public static let maxSidecarBytes = 10 * 1024 * 1024
    public static let maxAnnotations = 10_000
    public static let maxOverlays = 5_000
    public static let maxCaptionSegments = 20_000
    public static let maxCursorSamples = 300_000
    public static let maxCursorClicks = 50_000
    public static let maxKeystrokes = 50_000

    public static func data(
        contentsOf url: URL,
        displayPath: String,
        fileManager: FileManager = .default
    ) throws -> Data {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let byteCount = attributes[.size] as? NSNumber {
            try checkByteCount(byteCount.int64Value, displayPath: displayPath)
        }
        let data = try Data(contentsOf: url)
        try checkByteCount(Int64(data.count), displayPath: displayPath)
        return data
    }

    public static func checkCount(_ count: Int, limit: Int, displayPath: String, itemName: String) throws {
        if count > limit {
            throw RenderSidecarLimitError.tooManyItems(
                path: displayPath,
                itemName: itemName,
                count: count,
                limit: limit
            )
        }
    }

    private static func checkByteCount(_ byteCount: Int64, displayPath: String) throws {
        if byteCount > maxSidecarBytes {
            throw RenderSidecarLimitError.sidecarTooLarge(
                path: displayPath,
                byteCount: byteCount,
                limit: maxSidecarBytes
            )
        }
    }
}

public enum RenderSidecarLimitError: Error, Equatable, LocalizedError, Sendable {
    case sidecarTooLarge(path: String, byteCount: Int64, limit: Int)
    case tooManyItems(path: String, itemName: String, count: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .sidecarTooLarge(let path, let byteCount, let limit):
            "\(path) is too large to render safely: \(byteCount) bytes exceeds the \(limit) byte limit."
        case .tooManyItems(let path, let itemName, let count, let limit):
            "\(path) contains too many \(itemName): \(count) exceeds the \(limit) item limit."
        }
    }
}
