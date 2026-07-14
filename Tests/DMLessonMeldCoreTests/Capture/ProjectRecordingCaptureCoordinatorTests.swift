import DMLessonMeldCore
import Foundation
import Testing

@Suite("Project recording capture coordinator")
struct ProjectRecordingCaptureCoordinatorTests {
    @Test("Collects all requested capture results")
    func collectsRequestedCaptureResults() async throws {
        let screen = RecordingResult(
            screenVideoURL: URL(fileURLWithPath: "/tmp/screen.mp4"),
            screenSize: CGSize(width: 1_920, height: 1_080),
            fps: 60
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let microphone = AudioRecordingResult(
            source: .microphone(deviceID: "microphone-id"),
            outputURL: URL(fileURLWithPath: "/tmp/microphone.m4a"),
            options: AudioRecordingOptions(fileFormat: .m4a, sampleFormat: .aac),
            durationSeconds: 1,
            startedAt: now,
            endedAt: now.addingTimeInterval(1)
        )
        let webcam = CameraRecordingResult(
            outputURL: URL(fileURLWithPath: "/tmp/webcam.mov"),
            deviceID: "camera-id",
            durationSeconds: 1,
            resolution: "1080p",
            videoSize: CGSize(width: 1_920, height: 1_080),
            startedAt: now,
            endedAt: now.addingTimeInterval(1)
        )

        let result = try await ProjectRecordingCaptureCoordinator.capture(
            ProjectRecordingCaptureOperations(
                recordScreen: { screen },
                recordMicrophone: { microphone },
                recordWebcam: { webcam }
            )
        )

        #expect(result.screen == screen)
        #expect(result.microphone == microphone)
        #expect(result.webcam == webcam)
    }

    @Test("Screen failure cancels and settles side captures")
    func screenFailureCancelsSideCaptures() async {
        let probe = CaptureCancellationProbe()
        let operations = ProjectRecordingCaptureOperations(
            recordScreen: {
                await probe.waitUntilStarted(["microphone", "webcam"])
                throw InjectedCaptureFailure.screen
            },
            recordMicrophone: {
                await probe.markStarted("microphone")
                return try await waitUntilCancelled(name: "microphone", probe: probe)
            },
            recordWebcam: {
                await probe.markStarted("webcam")
                return try await waitUntilCancelled(name: "webcam", probe: probe)
            }
        )

        do {
            _ = try await ProjectRecordingCaptureCoordinator.capture(operations)
            Issue.record("Capture unexpectedly completed")
        } catch let error as InjectedCaptureFailure {
            #expect(error == .screen)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await probe.cancelledNames() == ["microphone", "webcam"])
    }
}

private enum InjectedCaptureFailure: Error, Equatable {
    case screen
}

private actor CaptureCancellationProbe {
    private var started: Set<String> = []
    private var cancelled: Set<String> = []
    private var waiters: [(Set<String>, CheckedContinuation<Void, Never>)] = []

    func markStarted(_ name: String) {
        started.insert(name)
        let ready = waiters.filter { $0.0.isSubset(of: started) }
        waiters.removeAll { $0.0.isSubset(of: started) }
        ready.forEach { $0.1.resume() }
    }

    func waitUntilStarted(_ names: Set<String>) async {
        guard !names.isSubset(of: started) else { return }
        await withCheckedContinuation { continuation in
            waiters.append((names, continuation))
        }
    }

    func markCancelled(_ name: String) {
        cancelled.insert(name)
    }

    func cancelledNames() -> Set<String> {
        cancelled
    }
}

private func waitUntilCancelled<Result>(
    name: String,
    probe: CaptureCancellationProbe
) async throws -> Result {
    do {
        try await Task.sleep(for: .seconds(30))
        throw CancellationError()
    } catch is CancellationError {
        await probe.markCancelled(name)
        throw CancellationError()
    }
}
