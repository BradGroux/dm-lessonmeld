import DMLessonMeldCore
import Foundation
import Testing

@Suite("Recording options")
struct RecordingOptionsTests {
    @Test("Defaults are conservative screen recording settings")
    func defaults() {
        let options = RecordingOptions()

        #expect(options.fps == 60)
        #expect(options.timerDelaySeconds == 0)
        #expect(options.captureQuality == .standard)
        #expect(options.captureSystemAudio == false)
        #expect(options.microphoneDeviceID == nil)
        #expect(options.cameraDeviceID == nil)
        #expect(options.cameraResolution == "1080p")
        #expect(options.includeCursor)
        #expect(options.retinaCapture == false)
        #expect(options.hdrCapture == false)
    }

    @Test("Camera resolution helper matches expected caps")
    func cameraResolutionCaps() {
        #expect(CaptureMode.cameraMaxDimensions(for: "720p").width == 1280)
        #expect(CaptureMode.cameraMaxDimensions(for: "4K").height == 2160)
        #expect(CaptureMode.cameraMaxDimensions(for: "1080p").width == 1920)
    }

    @Test("Camera recording requests are explicit and local")
    func cameraRecordingRequests() {
        let request = CameraRecordingRequest(
            outputURL: URL(fileURLWithPath: "/tmp/webcam.mov"),
            durationSeconds: 3,
            deviceID: "camera-1",
            resolution: "720p",
            fps: 30
        )

        #expect(request.outputURL.lastPathComponent == "webcam.mov")
        #expect(request.durationSeconds == 3)
        #expect(request.deviceID == "camera-1")
        #expect(request.resolution == "720p")
        #expect(request.fps == 30)
        #expect(CameraPermission.privacySettingsURL.scheme == "x-apple.systempreferences")
    }

    @Test("Camera permission request does not crash without bundled usage description")
    func cameraPermissionRequestNeedsUsageDescription() async {
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") == nil else {
            return
        }
        let granted = await CameraPermission.requestAccess()
        #expect(granted == false)
    }
}
