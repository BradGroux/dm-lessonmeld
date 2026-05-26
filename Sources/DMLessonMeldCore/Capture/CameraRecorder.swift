@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

public struct CameraCaptureDevice: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public final class CameraPreviewSessionBox: @unchecked Sendable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }
}

public enum CameraPermission {
    private static let usageDescriptionKey = "NSCameraUsageDescription"

    public static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    public static var isGranted: Bool {
        authorizationStatus == .authorized || canCreateDefaultInput
    }

    public static func requestAccess() async -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: usageDescriptionKey) != nil else {
            return false
        }

        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public static var privacySettingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
    }

    private static var canCreateDefaultInput: Bool {
        guard let device = AVCaptureDevice.default(for: .video) else {
            return false
        }
        return (try? AVCaptureDeviceInput(device: device)) != nil
    }
}

public enum CameraCaptureDevices {
    public static var available: [CameraCaptureDevice] {
        discoverySession.devices.map {
            CameraCaptureDevice(id: $0.uniqueID, name: $0.localizedName)
        }
    }

    public static var defaultDevice: CameraCaptureDevice? {
        AVCaptureDevice.default(for: .video).map {
            CameraCaptureDevice(id: $0.uniqueID, name: $0.localizedName)
        }
    }
}

public struct CameraRecordingRequest: Equatable, Sendable {
    public var outputURL: URL
    public var durationSeconds: TimeInterval
    public var deviceID: String?
    public var resolution: String
    public var fps: Int?

    public init(
        outputURL: URL,
        durationSeconds: TimeInterval,
        deviceID: String? = nil,
        resolution: String = "1080p",
        fps: Int? = nil
    ) {
        self.outputURL = outputURL
        self.durationSeconds = durationSeconds
        self.deviceID = deviceID
        self.resolution = resolution
        self.fps = fps
    }
}

public struct CameraRecordingResult: Codable, Equatable, Sendable {
    public var outputURL: URL
    public var deviceID: String?
    public var durationSeconds: TimeInterval
    public var resolution: String
    public var videoSize: CGSize
    public var startedAt: Date
    public var endedAt: Date

    public init(
        outputURL: URL,
        deviceID: String?,
        durationSeconds: TimeInterval,
        resolution: String,
        videoSize: CGSize,
        startedAt: Date,
        endedAt: Date
    ) {
        self.outputURL = outputURL
        self.deviceID = deviceID
        self.durationSeconds = durationSeconds
        self.resolution = resolution
        self.videoSize = videoSize
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum CameraRecordingError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case noCameraAvailable
    case requestedCameraNotFound(String)
    case invalidDuration
    case invalidFrameRate(String)
    case recorderAlreadyRunning
    case cannotAddCameraInput
    case cannotAddMovieOutput
    case recordingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Camera permission is required."
        case .noCameraAvailable:
            "No camera is available."
        case .requestedCameraNotFound(let id):
            "Requested camera was not found: \(id)."
        case .invalidDuration:
            "Camera recording duration must be finite, greater than zero, and no more than \(Int(NumericInputValidation.maxRecordingDurationSeconds)) seconds."
        case .invalidFrameRate(let reason):
            reason
        case .recorderAlreadyRunning:
            "A camera recording is already in progress."
        case .cannotAddCameraInput:
            "Could not add camera input to the capture session."
        case .cannotAddMovieOutput:
            "Could not add movie output to the capture session."
        case .recordingFailed(let reason):
            "Camera recording failed: \(reason)"
        }
    }
}

public final class CameraRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var activeSession: AVCaptureSession?
    private var activeOutput: AVCaptureMovieFileOutput?
    private var isStarting = false
    public var previewSessionHandler: (@Sendable (CameraPreviewSessionBox?) -> Void)?

    public init() {}

    public func pauseRecording() {
        lock.lock()
        let output = activeOutput
        lock.unlock()
        output?.pauseRecording()
    }

    public func resumeRecording() {
        lock.lock()
        let output = activeOutput
        lock.unlock()
        output?.resumeRecording()
    }

    public func stopRecording() {
        lock.lock()
        let output = activeOutput
        lock.unlock()
        if let output {
            Self.stopOutputIfRecording(output)
        }
    }

    public func record(_ request: CameraRecordingRequest) async throws -> CameraRecordingResult {
        let durationSeconds: TimeInterval
        do {
            durationSeconds = try NumericInputValidation.recordingDuration(request.durationSeconds, label: "Camera recording duration")
        } catch {
            throw CameraRecordingError.invalidDuration
        }
        let fps: Int?
        do {
            fps = try NumericInputValidation.optionalCaptureFPS(request.fps, label: "Camera FPS")
        } catch {
            throw CameraRecordingError.invalidFrameRate(error.localizedDescription)
        }

        try reserveActiveCapture()
        var outputFile: RecordingOutputFile?
        var session: AVCaptureSession?
        var output: AVCaptureMovieFileOutput?
        var delegate: CameraMovieFileDelegate?

        do {
            guard CameraPermission.isGranted else {
                throw CameraRecordingError.permissionDenied
            }

            let device = try Self.selectDevice(id: request.deviceID)
            try Self.configureFrameRate(fps, on: device)
            outputFile = try RecordingOutputFile.prepare(destinationURL: request.outputURL)

            let captureSession = AVCaptureSession()
            session = captureSession
            captureSession.beginConfiguration()
            captureSession.sessionPreset = Self.sessionPreset(for: request.resolution)

            let input = try AVCaptureDeviceInput(device: device)
            guard captureSession.canAddInput(input) else {
                captureSession.commitConfiguration()
                throw CameraRecordingError.cannotAddCameraInput
            }
            captureSession.addInput(input)

            let movieOutput = AVCaptureMovieFileOutput()
            output = movieOutput
            guard captureSession.canAddOutput(movieOutput) else {
                captureSession.commitConfiguration()
                throw CameraRecordingError.cannotAddMovieOutput
            }
            captureSession.addOutput(movieOutput)
            captureSession.commitConfiguration()

            let dimensions = CaptureMode.cameraMaxDimensions(for: request.resolution)
            let movieDelegate = CameraMovieFileDelegate(
                outputFile: outputFile!,
                deviceID: device.uniqueID,
                resolution: request.resolution,
                videoSize: CGSize(width: dimensions.width, height: dimensions.height)
            )
            delegate = movieDelegate

            captureSession.startRunning()
            movieOutput.startRecording(to: outputFile!.temporaryURL, recordingDelegate: movieDelegate)
            setActiveCapture(session: captureSession, output: movieOutput)

            try await Task.sleep(nanoseconds: try NumericInputValidation.sleepNanoseconds(forRecordingDuration: durationSeconds, label: "Camera recording duration"))
            Self.stopOutputIfRecording(movieOutput)
            let result = try await movieDelegate.waitForFinish()
            captureSession.stopRunning()
            clearActiveCapture()
            return result
        } catch is CancellationError {
            if let output {
                Self.stopOutputIfRecording(output)
            }
            if let delegate {
                do {
                    let result = try await delegate.waitForFinish()
                    session?.stopRunning()
                    clearActiveCapture()
                    return result
                } catch {
                    outputFile?.discard()
                    session?.stopRunning()
                    clearActiveCapture()
                    throw error
                }
            }
            outputFile?.discard()
            session?.stopRunning()
            clearActiveCapture()
            throw CancellationError()
        } catch {
            if let output {
                Self.stopOutputIfRecording(output)
            }
            session?.stopRunning()
            clearActiveCapture()
            outputFile?.discard()
            throw error
        }
    }

    private static func stopOutputIfRecording(_ output: AVCaptureMovieFileOutput) {
        guard output.isRecording else { return }
        output.stopRecording()
    }

    func clearActiveCapture() {
        lock.lock()
        activeOutput = nil
        activeSession = nil
        isStarting = false
        lock.unlock()
        previewSessionHandler?(nil)
    }

    private func setActiveCapture(session: AVCaptureSession, output: AVCaptureMovieFileOutput) {
        lock.lock()
        activeSession = session
        activeOutput = output
        isStarting = false
        lock.unlock()
        previewSessionHandler?(CameraPreviewSessionBox(session: session))
    }

    func reserveActiveCapture() throws {
        lock.lock()
        defer { lock.unlock() }
        guard activeSession == nil, activeOutput == nil, !isStarting else {
            throw CameraRecordingError.recorderAlreadyRunning
        }
        isStarting = true
    }

    private static func configureFrameRate(_ fps: Int?, on device: AVCaptureDevice) throws {
        guard let fps else { return }
        let validatedFPS = try NumericInputValidation.captureFPS(fps, label: "Camera FPS")
        let requestedFPS = Double(validatedFPS)
        guard device.activeFormat.videoSupportedFrameRateRanges.contains(where: { range in
            range.minFrameRate <= requestedFPS && requestedFPS <= range.maxFrameRate
        }) else {
            return
        }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(validatedFPS))
        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
        device.unlockForConfiguration()
    }

    private static func selectDevice(id: String?) throws -> AVCaptureDevice {
        if let id {
            guard let device = CameraCaptureDevices.discoverySession.devices.first(where: { $0.uniqueID == id }) else {
                throw CameraRecordingError.requestedCameraNotFound(id)
            }
            return device
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraRecordingError.noCameraAvailable
        }
        return device
    }

    private static func sessionPreset(for resolution: String) -> AVCaptureSession.Preset {
        switch resolution {
        case "720p":
            .hd1280x720
        case "4K":
            .hd4K3840x2160
        default:
            .hd1920x1080
        }
    }
}

private extension CameraCaptureDevices {
    static var discoverySession: AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
    }
}

private final class CameraMovieFileDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let outputFile: RecordingOutputFile
    private let deviceID: String
    private let resolution: String
    private let videoSize: CGSize

    private var startedAt: Date?
    private var result: Result<CameraRecordingResult, Error>?
    private var continuation: CheckedContinuation<CameraRecordingResult, Error>?

    init(outputFile: RecordingOutputFile, deviceID: String, resolution: String, videoSize: CGSize) {
        self.outputFile = outputFile
        self.deviceID = deviceID
        self.resolution = resolution
        self.videoSize = videoSize
    }

    func waitForFinish() async throws -> CameraRecordingResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        lock.lock()
        startedAt = Date()
        lock.unlock()
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        if let error {
            outputFile.discard()
            complete(.failure(CameraRecordingError.recordingFailed(error.localizedDescription)))
            return
        }

        let endedAt = Date()
        lock.lock()
        let startedAt = self.startedAt ?? endedAt
        lock.unlock()

        do {
            let outputURL = try outputFile.commit()
            complete(.success(CameraRecordingResult(
                outputURL: outputURL,
                deviceID: deviceID,
                durationSeconds: endedAt.timeIntervalSince(startedAt),
                resolution: resolution,
                videoSize: videoSize,
                startedAt: startedAt,
                endedAt: endedAt
            )))
        } catch {
            outputFile.discard()
            complete(.failure(CameraRecordingError.recordingFailed(error.localizedDescription)))
        }
    }

    private func complete(_ result: Result<CameraRecordingResult, Error>) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.result = result
            lock.unlock()
        }
    }
}
