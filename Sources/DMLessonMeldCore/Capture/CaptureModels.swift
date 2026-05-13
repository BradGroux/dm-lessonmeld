import CoreGraphics
import Foundation

public enum CaptureMode: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case entireScreen
    case selectedWindow
    case selectedArea
    case device

    public static func cameraMaxDimensions(for resolution: String) -> (width: Int, height: Int) {
        switch resolution {
        case "720p":
            (1280, 720)
        case "4K":
            (3840, 2160)
        default:
            (1920, 1080)
        }
    }
}

public enum CaptureTarget: Codable, Equatable, Sendable {
    case display(id: CGDirectDisplayID)
    case window(id: UInt32, displayID: CGDirectDisplayID?)
    case region(SelectionRect)

    public var mode: CaptureMode {
        switch self {
        case .display:
            .entireScreen
        case .window:
            .selectedWindow
        case .region:
            .selectedArea
        }
    }

    public var displayID: CGDirectDisplayID? {
        switch self {
        case .display(let id):
            id
        case .window(_, let displayID):
            displayID
        case .region(let selection):
            selection.displayID
        }
    }
}

public enum CaptureQuality: String, Codable, CaseIterable, Equatable, Sendable {
    case standard
    case high
    case veryHigh

    public var isProRes: Bool {
        self == .high || self == .veryHigh
    }
}

public struct RecordingOptions: Codable, Equatable, Sendable {
    public var fps: Int
    public var timerDelaySeconds: Int
    public var captureQuality: CaptureQuality
    public var captureSystemAudio: Bool
    public var microphoneDeviceID: String?
    public var cameraDeviceID: String?
    public var cameraResolution: String
    public var includeCursor: Bool
    public var retinaCapture: Bool
    public var hdrCapture: Bool

    public init(
        fps: Int = 60,
        timerDelaySeconds: Int = 0,
        captureQuality: CaptureQuality = .standard,
        captureSystemAudio: Bool = false,
        microphoneDeviceID: String? = nil,
        cameraDeviceID: String? = nil,
        cameraResolution: String = "1080p",
        includeCursor: Bool = true,
        retinaCapture: Bool = false,
        hdrCapture: Bool = false
    ) {
        self.fps = fps
        self.timerDelaySeconds = timerDelaySeconds
        self.captureQuality = captureQuality
        self.captureSystemAudio = captureSystemAudio
        self.microphoneDeviceID = microphoneDeviceID
        self.cameraDeviceID = cameraDeviceID
        self.cameraResolution = cameraResolution
        self.includeCursor = includeCursor
        self.retinaCapture = retinaCapture
        self.hdrCapture = hdrCapture
    }
}

public struct RecordingResult: Codable, Equatable, Sendable {
    public var screenVideoURL: URL
    public var webcamVideoURL: URL?
    public var systemAudioURL: URL?
    public var microphoneAudioURL: URL?
    public var cursorMetadataURL: URL?
    public var screenSize: CGSize
    public var webcamSize: CGSize?
    public var fps: Int
    public var captureQuality: CaptureQuality
    public var isHDR: Bool
    public var startedAt: Date?
    public var endedAt: Date?

    public init(
        screenVideoURL: URL,
        webcamVideoURL: URL? = nil,
        systemAudioURL: URL? = nil,
        microphoneAudioURL: URL? = nil,
        cursorMetadataURL: URL? = nil,
        screenSize: CGSize,
        webcamSize: CGSize? = nil,
        fps: Int,
        captureQuality: CaptureQuality = .standard,
        isHDR: Bool = false,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.screenVideoURL = screenVideoURL
        self.webcamVideoURL = webcamVideoURL
        self.systemAudioURL = systemAudioURL
        self.microphoneAudioURL = microphoneAudioURL
        self.cursorMetadataURL = cursorMetadataURL
        self.screenSize = screenSize
        self.webcamSize = webcamSize
        self.fps = fps
        self.captureQuality = captureQuality
        self.isHDR = isHDR
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum CaptureState: Codable, Equatable, Sendable {
    case idle
    case selecting
    case countdown(remaining: Int)
    case recording(startedAt: Date)
    case paused(elapsedSeconds: TimeInterval)
    case stopping
    case processing
    case completed(RecordingResult)
    case failed(message: String)
}

public enum CaptureError: LocalizedError, Equatable {
    case displayNotFound
    case invalidSourceRect
    case permissionDenied
    case streamNotRunning
    case recordingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .displayNotFound:
            "Could not find the target display."
        case .invalidSourceRect:
            "The selected capture region is empty or invalid."
        case .permissionDenied:
            "Screen recording permission is required."
        case .streamNotRunning:
            "No active screen capture stream is running."
        case .recordingFailed(let reason):
            "Recording failed: \(reason)"
        }
    }
}
