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
