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
        var lines: [String] = []
        if let title = transcript.title, !title.isEmpty {
            lines.append("# \(title)")
            lines.append("")
        }
        for segment in transcript.segments {
            lines.append("**\(timestamp(segment.startSeconds))** \(segment.text)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func plainText(_ transcript: TranscriptDocument) -> String {
        transcript.segments.map(\.text).joined(separator: "\n") + "\n"
    }

    public static func vtt(_ transcript: TranscriptDocument) -> String {
        var lines = ["WEBVTT", ""]
        for segment in transcript.segments {
            lines.append("\(webVTTSimestamp(segment.startSeconds)) --> \(webVTTSimestamp(segment.endSeconds))")
            lines.append(segment.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func srt(_ transcript: TranscriptDocument) -> String {
        var lines: [String] = []
        for (index, segment) in transcript.segments.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(srtTimestamp(segment.startSeconds)) --> \(srtTimestamp(segment.endSeconds))")
            lines.append(segment.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
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

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "Unsupported caption format: \(format)."
        case .noSegments:
            "No caption segments were found."
        }
    }
}

public enum TranscriptImporter {
    public static func transcript(from data: Data, fileName: String) throws -> TranscriptDocument {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if ext == "json" {
            return try DMLessonJSON.decoder().decode(TranscriptDocument.self, from: data)
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
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        let segments = blocks.compactMap { block -> TranscriptSegment? in
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("WEBVTT") && !$0.hasPrefix("NOTE") }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let timing = lines[timingIndex]
            let textLines = lines.dropFirst(timingIndex + 1)
            return segment(timingLine: timing, text: textLines.joined(separator: " "))
        }
        guard !segments.isEmpty else { throw TranscriptImportError.noSegments }
        return TranscriptDocument(segments: segments)
    }

    public static func srt(_ text: String) throws -> TranscriptDocument {
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        let segments = blocks.compactMap { block -> TranscriptSegment? in
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let timing = lines[timingIndex]
            let textLines = lines.dropFirst(timingIndex + 1)
            return segment(timingLine: timing, text: textLines.joined(separator: " "))
        }
        guard !segments.isEmpty else { throw TranscriptImportError.noSegments }
        return TranscriptDocument(segments: segments)
    }

    public static func plainText(_ text: String, title: String? = nil) throws -> TranscriptDocument {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

    private static func segment(timingLine: String, text: String) -> TranscriptSegment? {
        let parts = timingLine.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = parseTimestamp(parts[0]),
              let end = parseTimestamp(parts[1]),
              end > start else {
            return nil
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
        let timeAndMillis = normalized.split(separator: ".", maxSplits: 1).map(String.init)
        let timeParts = timeAndMillis[0].split(separator: ":").compactMap { Double($0) }
        guard timeParts.count == 2 || timeParts.count == 3 else { return nil }
        let milliseconds = timeAndMillis.count > 1 ? (Double("0.\(timeAndMillis[1])") ?? 0) : 0
        if timeParts.count == 3 {
            return timeParts[0] * 3600 + timeParts[1] * 60 + timeParts[2] + milliseconds
        }
        return timeParts[0] * 60 + timeParts[1] + milliseconds
    }
}
