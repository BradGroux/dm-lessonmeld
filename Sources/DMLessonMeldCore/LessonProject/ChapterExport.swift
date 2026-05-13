import Foundation

public enum ChapterExportFormat: String, Codable, CaseIterable, Sendable {
    case youtube
    case markdown
    case json
}

public struct ChapterExportEntry: Codable, Equatable, Sendable {
    public var timeSeconds: Double
    public var title: String
    public var notes: String?

    public init(timeSeconds: Double, title: String, notes: String? = nil) {
        self.timeSeconds = max(0, timeSeconds)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes
    }
}

public enum ChapterExporter {
    public static func entries(from manifest: ProjectManifest) -> [ChapterExportEntry] {
        manifest.markers
            .filter { $0.kind == .chapter }
            .sorted { $0.timeSeconds < $1.timeSeconds }
            .map {
                ChapterExportEntry(
                    timeSeconds: $0.timeSeconds,
                    title: $0.title,
                    notes: $0.notes
                )
            }
            .filter { !$0.title.isEmpty }
    }

    public static func render(_ entries: [ChapterExportEntry], format: ChapterExportFormat) throws -> String {
        switch format {
        case .youtube:
            return entries.map { "\(timestamp($0.timeSeconds)) \($0.title)" }.joined(separator: "\n") + "\n"
        case .markdown:
            return entries.map { entry in
                let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let notes, !notes.isEmpty {
                    return "- **\(timestamp(entry.timeSeconds))** \(entry.title) - \(notes)"
                }
                return "- **\(timestamp(entry.timeSeconds))** \(entry.title)"
            }.joined(separator: "\n") + "\n"
        case .json:
            let data = try DMLessonJSON.encoder().encode(entries)
            return String(decoding: data, as: UTF8.self) + "\n"
        }
    }

    private static func timestamp(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
