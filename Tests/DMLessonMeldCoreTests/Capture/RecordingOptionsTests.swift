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

    @Test("Window capture source keeps stable JSON fields")
    func windowCaptureSourceJSONFields() throws {
        let source = WindowCaptureSource(
            id: 123,
            title: "Lesson Browser",
            ownerName: "Safari",
            bounds: WindowCaptureBounds(x: 10, y: 20, width: 1280, height: 720)
        )

        let data = try DMLessonJSON.encoder().encode(source)
        let decoded = try DMLessonJSON.decoder().decode(WindowCaptureSource.self, from: data)

        #expect(decoded == source)
        #expect(decoded.sizeLabel == "1280x720")
    }

    @Test("Window capture source redacts titles for automation")
    func windowCaptureSourceRedactsTitlesForAutomation() {
        let source = WindowCaptureSource(
            id: 123,
            title: "Client Lesson Plan",
            ownerName: "Safari",
            bounds: WindowCaptureBounds(x: 10, y: 20, width: 1280, height: 720)
        )

        let redacted = source.redactedForAutomation()

        #expect(redacted.id == source.id)
        #expect(redacted.title == WindowCaptureSource.redactedTitle)
        #expect(redacted.ownerName == source.ownerName)
        #expect(redacted.bounds == source.bounds)
        #expect(source.redactedForAutomation(includeTitle: true) == source)
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
