import DMLessonMeldCore
import DMLessonMeldSupport
import Testing

@Suite("Quick recording camera control availability")
struct QuickRecordingCameraControlAvailabilityTests {
    @Test("Locks capture configuration for the full recording lifecycle")
    func locksCaptureConfigurationWhileRecording() {
        let availability = QuickRecordingCameraControlAvailability(
            isRecording: true,
            captureWebcam: true,
            frameShape: .roundedRectangle
        )

        #expect(!availability.canEditCaptureConfiguration)
        #expect(!availability.canEditAspectRatio)
        #expect(availability.canToggleFloatingPreview)
    }

    @Test("Keeps setup controls available and respects circle geometry")
    func setupAvailabilityRespectsFrameShape() {
        let rounded = QuickRecordingCameraControlAvailability(
            isRecording: false,
            captureWebcam: true,
            frameShape: .roundedRectangle
        )
        let circle = QuickRecordingCameraControlAvailability(
            isRecording: false,
            captureWebcam: false,
            frameShape: .circle
        )

        #expect(rounded.canEditCaptureConfiguration)
        #expect(rounded.canEditAspectRatio)
        #expect(rounded.canToggleFloatingPreview)
        #expect(circle.canEditCaptureConfiguration)
        #expect(!circle.canEditAspectRatio)
        #expect(!circle.canToggleFloatingPreview)
    }
}
