import DMLessonMeldCore
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
}
