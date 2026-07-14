@testable import DMLessonMeldCore
import AVFoundation
import Foundation
import Testing

@Suite("Microphone recorder")
struct MicrophoneRecorderTests {
    @Test("Stop detaches recorder state before stopping the capture session once")
    func stopDetachesStateBeforeStoppingSessionOnce() throws {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        let session = StopObservingCaptureSession()
        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .caf)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        let request = AudioRecordingRequest(outputURL: destinationURL)
        let stateLock = NSLock()
        let recorder = MicrophoneRecorder(
            activeSession: session,
            writer: writer,
            audioInput: audioInput,
            request: request,
            startedAt: Date(),
            stateLock: stateLock
        )
        session.onStop = {
            let lockWasAvailable = stateLock.try()
            if lockWasAvailable {
                stateLock.unlock()
            }
            return (
                lockWasAvailable,
                lockWasAvailable ? recorder.isRecording : nil
            )
        }

        do {
            _ = try recorder.stopRecording()
            Issue.record("Expected an empty recording to report unavailable input.")
        } catch AudioCaptureError.inputUnavailable {
        } catch {
            Issue.record("Expected AudioCaptureError.inputUnavailable, got \(error).")
        }

        #expect(session.stopObservations == [
            StopObservation(lockWasAvailable: true, recorderWasActive: false)
        ])
    }
}

private struct StopObservation: Equatable, Sendable {
    var lockWasAvailable: Bool
    var recorderWasActive: Bool?
}

private final class StopObservingCaptureSession: AVCaptureSession, @unchecked Sendable {
    private let observationLock = NSLock()
    private var observations: [StopObservation] = []
    var onStop: (@Sendable () -> (lockWasAvailable: Bool, recorderWasActive: Bool?))?

    var stopObservations: [StopObservation] {
        observationLock.withLock { observations }
    }

    override var isRunning: Bool { true }

    override func stopRunning() {
        let observation: (lockWasAvailable: Bool, recorderWasActive: Bool?)
        if let onStop {
            observation = onStop()
        } else {
            observation = (lockWasAvailable: true, recorderWasActive: nil)
        }
        observationLock.withLock {
            observations.append(StopObservation(
                lockWasAvailable: observation.lockWasAvailable,
                recorderWasActive: observation.recorderWasActive
            ))
        }
    }
}
