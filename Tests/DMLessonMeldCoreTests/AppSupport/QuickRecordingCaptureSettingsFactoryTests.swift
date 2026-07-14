import DMLessonMeldCore
import DMLessonMeldSupport
import Foundation
import Testing

@Suite("Quick recording capture settings")
struct QuickRecordingCaptureSettingsFactoryTests {
    @Test("Persists the recording metadata opt-out instead of the saved preference")
    func persistsActualMetadataCaptureState() {
        var preferences = LessonMeldPreferences()
        preferences.capture.captureInteractionMetadata = true

        let settings = QuickRecordingCaptureSettingsFactory.make(
            preferences: preferences,
            target: .screen,
            displayID: 42,
            sourceRect: CGRect(x: 10, y: 20, width: 1280, height: 720),
            windowID: nil,
            captureInteractionMetadata: false,
            captureMicrophone: true,
            captureWebcam: false,
            captureSystemAudio: true,
            microphoneDeviceID: "microphone-id",
            cameraDeviceID: nil
        )

        #expect(settings.captureInteractionMetadata == false)
        #expect(settings.captureInteractionMetadata != preferences.capture.captureInteractionMetadata)
    }
}
