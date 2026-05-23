@testable import DMLessonMeldCore
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

    @Test("Numeric validation rejects unsafe capture and editor values")
    func numericValidationRejectsUnsafeValues() throws {
        #expect(throws: NumericInputValidationError.self) {
            try NumericInputValidation.recordingDuration(.infinity)
        }
        #expect(throws: NumericInputValidationError.self) {
            try NumericInputValidation.recordingDuration(NumericInputValidation.maxRecordingDurationSeconds + 1)
        }
        #expect(throws: NumericInputValidationError.self) {
            try NumericInputValidation.captureFPS(Int.max)
        }
        #expect(throws: NumericInputValidationError.self) {
            try NumericInputValidation.captureRect(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10))
        }
        #expect(throws: NumericInputValidationError.self) {
            try NumericInputValidation.captureRect(CGRect(x: 10, y: 10, width: -5, height: 10))
        }
        #expect(throws: NumericInputValidationError.self) {
            try NumericInputValidation.canvasDimension(NumericInputValidation.maxCanvasDimension + 2, label: "Canvas width")
        }

        #expect(try NumericInputValidation.sleepNanoseconds(forRecordingDuration: 1) == 1_000_000_000)
        #expect(try NumericInputValidation.canvasDimension(1920, label: "Canvas width") == 1920)
    }

    @Test("Camera recorder rejects invalid duration and FPS before permissions")
    func cameraRecorderRejectsInvalidDurationAndFPSBeforePermissions() async {
        let recorder = CameraRecorder()

        do {
            _ = try await recorder.record(CameraRecordingRequest(
                outputURL: URL(fileURLWithPath: "/tmp/webcam.mov"),
                durationSeconds: .infinity
            ))
            Issue.record("Expected invalid camera duration to be rejected.")
        } catch CameraRecordingError.invalidDuration {
        } catch {
            Issue.record("Expected CameraRecordingError.invalidDuration, got \(error).")
        }

        do {
            _ = try await recorder.record(CameraRecordingRequest(
                outputURL: URL(fileURLWithPath: "/tmp/webcam.mov"),
                durationSeconds: 1,
                fps: Int.max
            ))
            Issue.record("Expected invalid camera FPS to be rejected.")
        } catch CameraRecordingError.invalidFrameRate(_) {
        } catch {
            Issue.record("Expected CameraRecordingError.invalidFrameRate, got \(error).")
        }
    }

    @Test("Recording output files replace destinations only after commit")
    func recordingOutputFilesReplaceDestinationsOnlyAfterCommit() throws {
        let temp = try TemporaryDirectory()
        let outputURL = temp.url.appendingPathComponent("recording.mov")
        try Data("original".utf8).write(to: outputURL)

        let outputFile = try RecordingOutputFile.prepare(destinationURL: outputURL)
        try Data("replacement".utf8).write(to: outputFile.temporaryURL)

        #expect(try String(contentsOf: outputURL, encoding: .utf8) == "original")
        #expect(FileManager.default.fileExists(atPath: outputFile.temporaryURL.path))

        let committedURL = try outputFile.commit()

        #expect(committedURL == outputURL)
        #expect(try String(contentsOf: outputURL, encoding: .utf8) == "replacement")
        #expect(!FileManager.default.fileExists(atPath: outputFile.temporaryURL.path))
    }

    @Test("Discarding recording output files keeps existing destinations")
    func discardingRecordingOutputFilesKeepsExistingDestinations() throws {
        let temp = try TemporaryDirectory()
        let outputURL = temp.url.appendingPathComponent("recording.m4a")
        try Data("original".utf8).write(to: outputURL)

        let outputFile = try RecordingOutputFile.prepare(destinationURL: outputURL)
        try Data("partial".utf8).write(to: outputFile.temporaryURL)
        outputFile.discard()

        #expect(try String(contentsOf: outputURL, encoding: .utf8) == "original")
        #expect(!FileManager.default.fileExists(atPath: outputFile.temporaryURL.path))
    }

    @Test("Camera recorder reserves active starts")
    func cameraRecorderReservesActiveStarts() throws {
        let recorder = CameraRecorder()
        try recorder.reserveActiveCapture()
        defer { recorder.clearActiveCapture() }

        #expect(throws: CameraRecordingError.recorderAlreadyRunning) {
            try recorder.reserveActiveCapture()
        }
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

    @Test("Window size labels ignore non-finite dimensions")
    func windowSizeLabelsIgnoreNonFiniteDimensions() {
        #expect(WindowCaptureSource(
            id: 123,
            title: "Bad",
            ownerName: "App",
            bounds: WindowCaptureBounds(x: 0, y: 0, width: Double.infinity, height: 720)
        ).sizeLabel == nil)
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

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
