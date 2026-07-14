import Foundation

public struct ProjectRecordingCaptureOperations: Sendable {
    public var recordScreen: @Sendable () async throws -> RecordingResult
    public var recordMicrophone: (@Sendable () async throws -> AudioRecordingResult)?
    public var recordWebcam: (@Sendable () async throws -> CameraRecordingResult)?

    public init(
        recordScreen: @escaping @Sendable () async throws -> RecordingResult,
        recordMicrophone: (@Sendable () async throws -> AudioRecordingResult)? = nil,
        recordWebcam: (@Sendable () async throws -> CameraRecordingResult)? = nil
    ) {
        self.recordScreen = recordScreen
        self.recordMicrophone = recordMicrophone
        self.recordWebcam = recordWebcam
    }
}

public struct ProjectRecordingCaptureResult: Sendable {
    public var screen: RecordingResult
    public var microphone: AudioRecordingResult?
    public var webcam: CameraRecordingResult?

    public init(
        screen: RecordingResult,
        microphone: AudioRecordingResult?,
        webcam: CameraRecordingResult?
    ) {
        self.screen = screen
        self.microphone = microphone
        self.webcam = webcam
    }
}

public enum ProjectRecordingCaptureCoordinator {
    public static func capture(
        _ operations: ProjectRecordingCaptureOperations
    ) async throws -> ProjectRecordingCaptureResult {
        try await withThrowingTaskGroup(
            of: ProjectRecordingPartialResult.self,
            returning: ProjectRecordingCaptureResult.self
        ) { group in
            group.addTask {
                .screen(try await operations.recordScreen())
            }
            if let recordMicrophone = operations.recordMicrophone {
                group.addTask {
                    .microphone(try await recordMicrophone())
                }
            }
            if let recordWebcam = operations.recordWebcam {
                group.addTask {
                    .webcam(try await recordWebcam())
                }
            }

            var screen: RecordingResult?
            var microphone: AudioRecordingResult?
            var webcam: CameraRecordingResult?
            do {
                for try await result in group {
                    switch result {
                    case .screen(let value):
                        screen = value
                    case .microphone(let value):
                        microphone = value
                    case .webcam(let value):
                        webcam = value
                    }
                }
            } catch {
                group.cancelAll()
                throw error
            }

            guard let screen else {
                throw ProjectRecordingCaptureCoordinatorError.missingScreenResult
            }
            return ProjectRecordingCaptureResult(
                screen: screen,
                microphone: microphone,
                webcam: webcam
            )
        }
    }
}

public enum ProjectRecordingCaptureCoordinatorError: Error, Equatable, LocalizedError, Sendable {
    case missingScreenResult

    public var errorDescription: String? {
        switch self {
        case .missingScreenResult:
            "Project recording completed without a screen capture result."
        }
    }
}

private enum ProjectRecordingPartialResult: Sendable {
    case screen(RecordingResult)
    case microphone(AudioRecordingResult)
    case webcam(CameraRecordingResult)
}
