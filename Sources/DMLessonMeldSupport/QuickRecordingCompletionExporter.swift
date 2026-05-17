import DMLessonMeldCore
import Foundation

public struct CaptionSidecarWriteResult: Codable, Equatable, Sendable {
    public var transcriptJSONURL: URL
    public var captionsVTTURL: URL
    public var captionsSRTURL: URL
    public var transcriptTextURL: URL

    public init(transcriptJSONURL: URL, captionsVTTURL: URL, captionsSRTURL: URL, transcriptTextURL: URL) {
        self.transcriptJSONURL = transcriptJSONURL
        self.captionsVTTURL = captionsVTTURL
        self.captionsSRTURL = captionsSRTURL
        self.transcriptTextURL = transcriptTextURL
    }
}

public enum QuickRecordingCompletionExportError: Error, Equatable, LocalizedError, Sendable {
    case noTranscriptSidecar

    public var errorDescription: String? {
        switch self {
        case .noTranscriptSidecar:
            "This recording does not have a JSON transcript or caption sidecar to export."
        }
    }
}

public enum QuickRecordingCompletionExporter {
    public static func writeProjectCaptionSidecars(
        transcript: TranscriptDocument,
        projectURL: URL,
        fileManager: FileManager = .default
    ) throws -> CaptionSidecarWriteResult {
        let jsonURL = projectURL.appendingPathComponent("transcript.json")
        let vttURL = projectURL.appendingPathComponent("captions.vtt")
        let srtURL = projectURL.appendingPathComponent("captions.srt")
        let textURL = projectURL.appendingPathComponent("transcript.txt")

        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try DMLessonJSON.encoder().encode(transcript).write(to: jsonURL, options: [.atomic])
        try Data(TranscriptExporter.vtt(transcript).utf8).write(to: vttURL, options: [.atomic])
        try Data(TranscriptExporter.srt(transcript).utf8).write(to: srtURL, options: [.atomic])
        try Data(TranscriptExporter.plainText(transcript).utf8).write(to: textURL, options: [.atomic])

        return CaptionSidecarWriteResult(
            transcriptJSONURL: jsonURL,
            captionsVTTURL: vttURL,
            captionsSRTURL: srtURL,
            transcriptTextURL: textURL
        )
    }

    public static func exportCompletionCaptionSidecars(
        projectURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        guard let transcriptFile = jsonTranscriptSource(in: manifest) else {
            throw QuickRecordingCompletionExportError.noTranscriptSidecar
        }

        let transcriptURL = try ProjectBundle.projectLocalFileURL(for: transcriptFile, in: projectURL)
        let transcriptData = try Data(contentsOf: transcriptURL)
        let transcript = try DMLessonJSON.decoder().decode(TranscriptDocument.self, from: transcriptData)
        let outputDirectory = completionCaptionExportDirectory(for: projectURL)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try Data(TranscriptExporter.vtt(transcript).utf8).write(to: outputDirectory.appendingPathComponent("captions.vtt"), options: [.atomic])
        try Data(TranscriptExporter.srt(transcript).utf8).write(to: outputDirectory.appendingPathComponent("captions.srt"), options: [.atomic])
        try Data(TranscriptExporter.markdown(transcript).utf8).write(to: outputDirectory.appendingPathComponent("transcript.md"), options: [.atomic])
        try Data(TranscriptExporter.plainText(transcript).utf8).write(to: outputDirectory.appendingPathComponent("transcript.txt"), options: [.atomic])
        return outputDirectory
    }

    public static func jsonTranscriptSource(in manifest: ProjectManifest) -> ProjectFile? {
        manifest.media.transcripts.first(where: isJSONSidecar)
            ?? manifest.media.captions.first(where: isJSONSidecar)
    }

    public static func completionCaptionExportDirectory(for projectURL: URL) -> URL {
        projectURL
            .deletingLastPathComponent()
            .appendingPathComponent("Caption Exports", isDirectory: true)
            .appendingPathComponent(projectURL.deletingPathExtension().lastPathComponent, isDirectory: true)
    }

    private static func isJSONSidecar(_ file: ProjectFile) -> Bool {
        file.mimeType == "application/json" || file.relativePath.lowercased().hasSuffix(".json")
    }
}
