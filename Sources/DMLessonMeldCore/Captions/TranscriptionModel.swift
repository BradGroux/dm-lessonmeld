import Foundation

public struct TranscriptionPreferences: Codable, Equatable, Sendable {
    public static let defaultModelDirectoryPath = "~/Library/Application Support/DMLessonMeld/Models"
    public static let defaultModelFilePath = "\(defaultModelDirectoryPath)/ggml-base.en.bin"

    public var enabled: Bool
    public var runtime: TranscriptionRuntime
    public var modelPath: String
    public var language: String
    public var autoTranscribeAfterRecording: Bool
    public var writeCaptionSidecars: Bool

    public init(
        enabled: Bool = false,
        runtime: TranscriptionRuntime = .whisperCPP,
        modelPath: String = TranscriptionPreferences.defaultModelFilePath,
        language: String = "en",
        autoTranscribeAfterRecording: Bool = false,
        writeCaptionSidecars: Bool = true
    ) {
        self.enabled = enabled
        self.runtime = runtime
        self.modelPath = modelPath
        self.language = language
        self.autoTranscribeAfterRecording = autoTranscribeAfterRecording
        self.writeCaptionSidecars = writeCaptionSidecars
    }

    public func normalized() -> TranscriptionPreferences {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptionPreferences(
            enabled: enabled,
            runtime: runtime,
            modelPath: trimmedPath.isEmpty ? Self.defaultModelFilePath : trimmedPath,
            language: trimmedLanguage.isEmpty ? "en" : trimmedLanguage.lowercased(),
            autoTranscribeAfterRecording: enabled && autoTranscribeAfterRecording,
            writeCaptionSidecars: writeCaptionSidecars
        )
    }
}

public enum TranscriptionRuntime: String, Codable, CaseIterable, Identifiable, Sendable {
    case whisperCPP = "whisper.cpp"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .whisperCPP:
            "Whisper.cpp"
        }
    }
}

public struct TranscriptionModelStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var runtime: TranscriptionRuntime
    public var language: String
    public var modelPath: String
    public var expandedModelPath: String
    public var state: TranscriptionModelState
    public var isReady: Bool
    public var message: String
    public var recommendedDirectory: String

    public init(
        enabled: Bool,
        runtime: TranscriptionRuntime,
        language: String,
        modelPath: String,
        expandedModelPath: String,
        state: TranscriptionModelState,
        recommendedDirectory: String
    ) {
        self.enabled = enabled
        self.runtime = runtime
        self.language = language
        self.modelPath = modelPath
        self.expandedModelPath = expandedModelPath
        self.state = state
        self.isReady = state == .ready
        self.message = state.message
        self.recommendedDirectory = recommendedDirectory
    }
}

public enum TranscriptionModelState: String, Codable, Equatable, Sendable {
    case disabled
    case missingModelPath
    case modelNotFound
    case modelIsDirectory
    case modelUnreadable
    case ready

    public var message: String {
        switch self {
        case .disabled:
            "Local transcription is disabled."
        case .missingModelPath:
            "Local transcription needs a model file path."
        case .modelNotFound:
            "The configured transcription model file was not found."
        case .modelIsDirectory:
            "The configured transcription model path points to a directory, not a model file."
        case .modelUnreadable:
            "The configured transcription model file is not readable."
        case .ready:
            "Local transcription model is ready."
        }
    }
}

public enum TranscriptionModelInspector {
    public static func status(
        for preferences: TranscriptionPreferences,
        fileManager: FileManager = .default
    ) -> TranscriptionModelStatus {
        let normalized = preferences.normalized()
        let expandedModelPath = expandedPath(normalized.modelPath)
        let recommendedDirectory = expandedPath(TranscriptionPreferences.defaultModelDirectoryPath)
        let state: TranscriptionModelState

        if !normalized.enabled {
            state = .disabled
        } else if normalized.modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .missingModelPath
        } else {
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: expandedModelPath, isDirectory: &isDirectory) {
                state = .modelNotFound
            } else if isDirectory.boolValue {
                state = .modelIsDirectory
            } else if !fileManager.isReadableFile(atPath: expandedModelPath) {
                state = .modelUnreadable
            } else {
                state = .ready
            }
        }

        return TranscriptionModelStatus(
            enabled: normalized.enabled,
            runtime: normalized.runtime,
            language: normalized.language,
            modelPath: normalized.modelPath,
            expandedModelPath: expandedModelPath,
            state: state,
            recommendedDirectory: recommendedDirectory
        )
    }

    public static func expandedPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}
