import Foundation

public enum AudioSource: Codable, Equatable, Sendable {
    case none
    case microphone(deviceID: String?)
    case system
    case file(URL)

    public var isLiveCapture: Bool {
        switch self {
        case .microphone, .system:
            true
        case .none, .file:
            false
        }
    }
}

public enum AudioFileFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case caf
    case wav
    case m4a
}

public enum AudioSampleFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case pcmFloat32
    case aac
}

public struct AudioRecordingOptions: Codable, Equatable, Sendable {
    public var sampleRate: Double
    public var channelCount: Int
    public var fileFormat: AudioFileFormat
    public var sampleFormat: AudioSampleFormat
    public var bitRate: Int
    public var meteringEnabled: Bool
    public var waveformPeakCount: Int

    public init(
        sampleRate: Double = 48_000,
        channelCount: Int = 1,
        fileFormat: AudioFileFormat = .caf,
        sampleFormat: AudioSampleFormat = .pcmFloat32,
        bitRate: Int = 128_000,
        meteringEnabled: Bool = true,
        waveformPeakCount: Int = 1_024
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.fileFormat = fileFormat
        self.sampleFormat = sampleFormat
        self.bitRate = bitRate
        self.meteringEnabled = meteringEnabled
        self.waveformPeakCount = waveformPeakCount
    }
}

public struct AudioRecordingRequest: Equatable, Sendable {
    public var source: AudioSource
    public var outputURL: URL
    public var options: AudioRecordingOptions

    public init(
        source: AudioSource = .microphone(deviceID: nil),
        outputURL: URL,
        options: AudioRecordingOptions = AudioRecordingOptions()
    ) {
        self.source = source
        self.outputURL = outputURL
        self.options = options
    }
}

public struct AudioRecordingResult: Codable, Equatable, Sendable {
    public var source: AudioSource
    public var outputURL: URL
    public var options: AudioRecordingOptions
    public var durationSeconds: TimeInterval
    public var startedAt: Date
    public var endedAt: Date
    public var waveform: [WaveformPeak]

    public init(
        source: AudioSource,
        outputURL: URL,
        options: AudioRecordingOptions,
        durationSeconds: TimeInterval,
        startedAt: Date,
        endedAt: Date,
        waveform: [WaveformPeak] = []
    ) {
        self.source = source
        self.outputURL = outputURL
        self.options = options
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.waveform = waveform
    }
}

public struct AudioRegion: Codable, Equatable, Sendable {
    public var startSeconds: TimeInterval
    public var durationSeconds: TimeInterval
    public var label: String?

    public init(startSeconds: TimeInterval, durationSeconds: TimeInterval, label: String? = nil) {
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.label = label
    }

    public var endSeconds: TimeInterval {
        startSeconds + durationSeconds
    }

    public func validated(totalDurationSeconds: TimeInterval? = nil) throws -> Self {
        guard startSeconds.isFinite, durationSeconds.isFinite else {
            throw AudioRegionValidationError.nonFiniteTime
        }
        guard startSeconds >= 0 else {
            throw AudioRegionValidationError.negativeStart
        }
        guard durationSeconds > 0 else {
            throw AudioRegionValidationError.nonPositiveDuration
        }
        if let totalDurationSeconds {
            guard totalDurationSeconds.isFinite, totalDurationSeconds >= 0 else {
                throw AudioRegionValidationError.invalidTotalDuration
            }
            guard endSeconds <= totalDurationSeconds else {
                throw AudioRegionValidationError.exceedsTotalDuration
            }
        }
        return self
    }

    public func overlaps(_ other: AudioRegion) -> Bool {
        startSeconds < other.endSeconds && other.startSeconds < endSeconds
    }
}

public enum AudioRegionValidationError: Error, Equatable, LocalizedError {
    case nonFiniteTime
    case negativeStart
    case nonPositiveDuration
    case invalidTotalDuration
    case exceedsTotalDuration

    public var errorDescription: String? {
        switch self {
        case .nonFiniteTime:
            "Audio region times must be finite."
        case .negativeStart:
            "Audio region start must be zero or greater."
        case .nonPositiveDuration:
            "Audio region duration must be greater than zero."
        case .invalidTotalDuration:
            "Audio total duration must be finite and zero or greater."
        case .exceedsTotalDuration:
            "Audio region extends beyond the audio duration."
        }
    }
}

public enum AudioCaptureError: Error, Equatable, LocalizedError {
    case permissionDenied
    case unsupportedSource(AudioSource)
    case inputUnavailable
    case recorderAlreadyRunning
    case recorderNotRunning
    case invalidOptions(String)
    case recordingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Microphone permission is required."
        case .unsupportedSource(let source):
            "Unsupported audio source: \(source)."
        case .inputUnavailable:
            "No microphone input is available."
        case .recorderAlreadyRunning:
            "An audio recording is already running."
        case .recorderNotRunning:
            "No audio recording is running."
        case .invalidOptions(let reason):
            "Invalid audio recording options: \(reason)"
        case .recordingFailed(let reason):
            "Audio recording failed: \(reason)"
        }
    }
}
