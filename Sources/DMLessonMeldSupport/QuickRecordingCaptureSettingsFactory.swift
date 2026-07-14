import DMLessonMeldCore
import Foundation

public enum QuickRecordingCaptureSettingsFactory {
    public static func make(
        preferences: LessonMeldPreferences,
        target: ProjectCaptureTarget,
        displayID: UInt32?,
        sourceRect: CGRect?,
        windowID: UInt32?,
        captureInteractionMetadata: Bool,
        captureMicrophone: Bool,
        captureWebcam: Bool,
        captureSystemAudio: Bool,
        microphoneDeviceID: String?,
        cameraDeviceID: String?
    ) -> ProjectCaptureSettings {
        ProjectCaptureSettings(
            target: target,
            displayID: displayID,
            windowID: windowID,
            region: sourceRect.map(ProjectCaptureRegion.init),
            screenFPS: preferences.capture.fps,
            includeCursor: preferences.capture.includeCursor,
            captureInteractionMetadata: captureInteractionMetadata,
            captureMicrophone: captureMicrophone,
            microphoneDeviceID: microphoneDeviceID,
            captureWebcam: captureWebcam,
            captureSystemAudio: captureSystemAudio,
            webcam: ProjectWebcamCaptureSettings(
                cameraID: cameraDeviceID,
                resolution: preferences.capture.cameraResolution,
                fps: preferences.capture.webcamFPS,
                aspectRatio: preferences.capture.webcamAspectRatio,
                frameShape: preferences.capture.webcamFrameShape,
                cornerRadius: preferences.capture.webcamCornerRadius,
                relativeSize: preferences.capture.webcamRelativeSize,
                isMirrored: preferences.capture.webcamMirror,
                borderEnabled: preferences.capture.webcamBorderEnabled,
                shadowEnabled: preferences.capture.webcamShadowEnabled
            )
        )
    }
}
