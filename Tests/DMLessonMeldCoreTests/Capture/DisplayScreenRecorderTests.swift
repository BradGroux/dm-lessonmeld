import DMLessonMeldCore
import Foundation
import Testing

@Suite("Display screen recorder")
struct DisplayScreenRecorderTests {
    @Test("Stop without active stream reports stream not running")
    func stopWithoutActiveStreamReportsStreamNotRunning() async {
        let recorder = DisplayScreenRecorder()

        do {
            _ = try await recorder.stopRecording(fps: 60, captureQuality: .standard, isHDR: false)
            Issue.record("Expected stopRecording to reject an inactive stream.")
        } catch CaptureError.streamNotRunning {
        } catch {
            Issue.record("Expected CaptureError.streamNotRunning, got \(error).")
        }
    }

    @Test("Invalid display recording duration is rejected before permissions")
    func invalidDurationRejectedBeforePermissions() async {
        let recorder = DisplayScreenRecorder()

        do {
            _ = try await recorder.record(DisplayRecordingRequest(
                outputURL: URL(fileURLWithPath: "/tmp/screen.mp4"),
                durationSeconds: .infinity
            ))
            Issue.record("Expected invalid display duration to be rejected.")
        } catch CaptureError.recordingFailed(let message) {
            #expect(message.contains("finite"))
        } catch {
            Issue.record("Expected CaptureError.recordingFailed, got \(error).")
        }
    }

    @Test("Screen capture pixel sizing rejects non-finite and huge values")
    func screenCapturePixelSizingRejectsUnsafeValues() throws {
        #expect(throws: NumericInputValidationError.self) {
            try ScreenCaptureSession.validatedOutputPixelSize(
                for: CGSize(width: CGFloat.infinity, height: 720),
                displayScale: 1,
                retinaCapture: false
            )
        }
        #expect(throws: NumericInputValidationError.self) {
            try ScreenCaptureSession.validatedOutputPixelSize(
                for: CGSize(width: 10_000, height: 10_000),
                displayScale: 2,
                retinaCapture: true
            )
        }

        let safeConfiguration = ScreenCaptureSession.configuration(
            sourceRect: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 720),
            displayScale: CGFloat.infinity,
            options: RecordingOptions(fps: Int.max)
        )
        #expect(safeConfiguration.width == 2)
        #expect(safeConfiguration.height == 2)
        #expect(safeConfiguration.minimumFrameInterval.timescale == 60)
    }
}
