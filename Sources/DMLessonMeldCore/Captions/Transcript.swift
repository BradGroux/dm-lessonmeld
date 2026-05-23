import Foundation

public struct TranscriptDocument: Codable, Equatable, Sendable {
    public var language: String
    public var title: String?
    public var segments: [TranscriptSegment]

    public init(language: String = "en", title: String? = nil, segments: [TranscriptSegment] = []) {
        self.language = language
        self.title = title
        self.segments = segments
    }
}

public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startSeconds: Double
    public var endSeconds: Double
    public var text: String
    public var words: [TranscriptWord]

    public init(
        id: String,
        startSeconds: Double,
        endSeconds: Double,
        text: String,
        words: [TranscriptWord] = []
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.words = words
    }
}

public struct TranscriptWord: Codable, Equatable, Sendable {
    public var startSeconds: Double
    public var endSeconds: Double
    public var text: String

    public init(startSeconds: Double, endSeconds: Double, text: String) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
    }
}

public enum TranscriptExporter {
    public static func markdown(_ transcript: TranscriptDocument) -> String {
        var output = ""
        output.reserveCapacity(max(128, transcript.segments.count * 80))
        if let title = transcript.title, !title.isEmpty {
            output += "# \(title)\n\n"
        }
        for segment in transcript.segments {
            output += "**\(timestamp(segment.startSeconds))** \(segment.text)\n"
        }
        return output.isEmpty ? "\n" : output
    }

    public static func plainText(_ transcript: TranscriptDocument) -> String {
        var output = ""
        output.reserveCapacity(max(128, transcript.segments.count * 80))
        for segment in transcript.segments {
            output += "\(segment.text)\n"
        }
        return output.isEmpty ? "\n" : output
    }

    public static func vtt(_ transcript: TranscriptDocument) -> String {
        var output = "WEBVTT\n"
        output.reserveCapacity(max(128, transcript.segments.count * 96))
        if !transcript.segments.isEmpty {
            output += "\n"
        }
        for (index, segment) in transcript.segments.enumerated() {
            output += "\(webVTTSimestamp(segment.startSeconds)) --> \(webVTTSimestamp(segment.endSeconds))\n"
            output += "\(segment.text)\n"
            if index < transcript.segments.count - 1 {
                output += "\n"
            }
        }
        return output
    }

    public static func srt(_ transcript: TranscriptDocument) -> String {
        var output = ""
        output.reserveCapacity(max(128, transcript.segments.count * 104))
        for (index, segment) in transcript.segments.enumerated() {
            output += "\(index + 1)\n"
            output += "\(srtTimestamp(segment.startSeconds)) --> \(srtTimestamp(segment.endSeconds))\n"
            output += "\(segment.text)\n"
            if index < transcript.segments.count - 1 {
                output += "\n"
            }
        }
        return output
    }

    private static func timestamp(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private static func webVTTSimestamp(_ seconds: Double) -> String {
        timestamp(seconds, separator: ".")
    }

    private static func srtTimestamp(_ seconds: Double) -> String {
        timestamp(seconds, separator: ",")
    }

    private static func timestamp(_ seconds: Double, separator: String) -> String {
        let clamped = max(0, seconds)
        let totalMilliseconds = Int((clamped * 1000).rounded())
        let milliseconds = totalMilliseconds % 1000
        let totalSeconds = totalMilliseconds / 1000
        let secs = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, separator, milliseconds)
    }
}

public enum TranscriptImportError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedFormat(String)
    case noSegments
    case malformedTimestamp(String)
    case importTooLarge(byteCount: Int, limit: Int)
    case tooManySegments(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "Unsupported caption format: \(format)."
        case .noSegments:
            "No caption segments were found."
        case .malformedTimestamp(let value):
            "Malformed caption timestamp: \(value)."
        case .importTooLarge(let byteCount, let limit):
            "Transcript import is too large: \(byteCount) bytes exceeds the \(limit) byte limit."
        case .tooManySegments(let limit):
            "Transcript import contains more than \(limit) segments."
        }
    }
}

public enum TranscriptImporter {
    public static let maxImportBytes = 10 * 1024 * 1024
    public static let maxSegments = 20_000

    public static func transcript(from data: Data, fileName: String) throws -> TranscriptDocument {
        try validateImportByteCount(data.count)
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if ext == "json" {
            let transcript = try DMLessonJSON.decoder().decode(TranscriptDocument.self, from: data)
            try validateSegmentCount(transcript.segments.count)
            return transcript
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw TranscriptImportError.unsupportedFormat(ext.isEmpty ? fileName : ext)
        }
        switch ext {
        case "vtt":
            return try webVTT(text)
        case "srt":
            return try srt(text)
        case "txt", "text", "md", "markdown":
            return try plainText(text, title: URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent)
        default:
            throw TranscriptImportError.unsupportedFormat(ext.isEmpty ? fileName : ext)
        }
    }

    public static func webVTT(_ text: String) throws -> TranscriptDocument {
        try validateImportByteCount(text.utf8.count)
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        var segments: [TranscriptSegment] = []
        for block in blocks {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("WEBVTT") && !$0.hasPrefix("NOTE") }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timing = lines[timingIndex]
            let textLines = lines.dropFirst(timingIndex + 1)
            if let segment = try segment(timingLine: timing, text: textLines.joined(separator: " ")) {
                segments.append(segment)
                try validateSegmentCount(segments.count)
            }
        }
        guard !segments.isEmpty else { throw TranscriptImportError.noSegments }
        return TranscriptDocument(segments: segments)
    }

    public static func srt(_ text: String) throws -> TranscriptDocument {
        try validateImportByteCount(text.utf8.count)
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        var segments: [TranscriptSegment] = []
        for block in blocks {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timing = lines[timingIndex]
            let textLines = lines.dropFirst(timingIndex + 1)
            if let segment = try segment(timingLine: timing, text: textLines.joined(separator: " ")) {
                segments.append(segment)
                try validateSegmentCount(segments.count)
            }
        }
        guard !segments.isEmpty else { throw TranscriptImportError.noSegments }
        return TranscriptDocument(segments: segments)
    }

    public static func plainText(_ text: String, title: String? = nil) throws -> TranscriptDocument {
        try validateImportByteCount(text.utf8.count)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        try validateSegmentCount(lines.count)
        let segments = lines.enumerated().map { index, line in
            let start = Double(index) * 3
            return TranscriptSegment(
                id: "caption-\(index + 1)",
                startSeconds: start,
                endSeconds: start + 3,
                text: line
            )
        }
        guard !segments.isEmpty else { throw TranscriptImportError.noSegments }
        return TranscriptDocument(title: title, segments: segments)
    }

    private static func segment(timingLine: String, text: String) throws -> TranscriptSegment? {
        let parts = timingLine.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = parseTimestamp(parts[0]),
              let end = parseTimestamp(parts[1]),
              end > start else {
            throw TranscriptImportError.malformedTimestamp(timingLine)
        }
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return nil }
        return TranscriptSegment(
            id: "caption-\(UUID().uuidString)",
            startSeconds: start,
            endSeconds: end,
            text: cleanedText
        )
    }

    private static func parseTimestamp(_ raw: String) -> Double? {
        let token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
        let normalized = token.replacingOccurrences(of: ",", with: ".")
        let timeAndMillis = normalized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard !timeAndMillis.isEmpty, !timeAndMillis[0].isEmpty else { return nil }

        let rawTimeParts = timeAndMillis[0].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard rawTimeParts.count == 2 || rawTimeParts.count == 3 else { return nil }
        let timeParts = rawTimeParts.compactMap(Double.init)
        guard timeParts.count == rawTimeParts.count,
              timeParts.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return nil
        }
        guard timeParts.count == 2 || timeParts.count == 3 else { return nil }
        let milliseconds: Double
        if timeAndMillis.count > 1 {
            let fraction = timeAndMillis[1]
            guard !fraction.isEmpty, fraction.allSatisfy(\.isNumber) else { return nil }
            milliseconds = Double("0.\(fraction)") ?? 0
        } else {
            milliseconds = 0
        }
        if timeParts.count == 3 {
            guard timeParts[1] < 60, timeParts[2] < 60 else { return nil }
            return timeParts[0] * 3600 + timeParts[1] * 60 + timeParts[2] + milliseconds
        }
        guard timeParts[1] < 60 else { return nil }
        return timeParts[0] * 60 + timeParts[1] + milliseconds
    }

    private static func validateImportByteCount(_ byteCount: Int) throws {
        guard byteCount <= maxImportBytes else {
            throw TranscriptImportError.importTooLarge(byteCount: byteCount, limit: maxImportBytes)
        }
    }

    private static func validateSegmentCount(_ count: Int) throws {
        guard count <= maxSegments else {
            throw TranscriptImportError.tooManySegments(limit: maxSegments)
        }
    }
}
