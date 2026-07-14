import DMLessonMeldCore

public struct QuickRecordingCameraControlAvailability: Equatable, Sendable {
    public let isRecording: Bool
    public let captureWebcam: Bool
    public let frameShape: WebcamFrameShape

    public init(isRecording: Bool, captureWebcam: Bool, frameShape: WebcamFrameShape) {
        self.isRecording = isRecording
        self.captureWebcam = captureWebcam
        self.frameShape = frameShape
    }

    public var canEditCaptureConfiguration: Bool {
        !isRecording
    }

    public var canEditAspectRatio: Bool {
        canEditCaptureConfiguration && frameShape != .circle
    }

    public var canToggleFloatingPreview: Bool {
        captureWebcam
    }
}
