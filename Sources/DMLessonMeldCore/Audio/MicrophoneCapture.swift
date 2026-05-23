import AVFoundation
import Foundation

public struct AudioCaptureDevice: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum MicrophonePermission {
    private static let usageDescriptionKey = "NSMicrophoneUsageDescription"

    public static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static var isGranted: Bool {
        authorizationStatus == .authorized
    }

    public static func requestAccess() async -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: usageDescriptionKey) != nil else {
            return false
        }

        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public static var privacySettingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    }
}

public enum MicrophoneCaptureDevices {
    public static var available: [AudioCaptureDevice] {
        discoverySession.devices.map {
            AudioCaptureDevice(id: $0.uniqueID, name: $0.localizedName)
        }
    }

    public static var defaultDevice: AudioCaptureDevice? {
        AVCaptureDevice.default(for: .audio).map {
            AudioCaptureDevice(id: $0.uniqueID, name: $0.localizedName)
        }
    }
}

private extension MicrophoneCaptureDevices {
    static var discoverySession: AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
    }
}

public final class MicrophoneRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let finishWritingTimeoutSeconds: TimeInterval = 15

    private let queue = DispatchQueue(label: "io.digitalmeld.dm-lessonmeld.microphone-recorder", qos: .userInitiated)
    private let lock = NSLock()
    private var session: AVCaptureSession?
    private var writer: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var firstPresentationTime: CMTime?
    private var writerError: Error?
    private var writtenSamples = 0
    private var activeRequest: AudioRecordingRequest?
    private var outputFile: RecordingOutputFile?
    private var isStarting = false
    private var startedAt: Date?
    private var isPaused = false
    private var pauseStartedAt: Date?
    private var totalPausedDuration: TimeInterval = 0

    public override init() {
        super.init()
    }

    public var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStarting || session?.isRunning == true
    }

    public func startRecording(_ request: AudioRecordingRequest) throws {
        try validate(request)
        guard MicrophonePermission.isGranted else {
            throw AudioCaptureError.permissionDenied
        }

        guard case .microphone(let deviceID) = request.source,
              let device = Self.selectDevice(id: deviceID) else {
            throw AudioCaptureError.inputUnavailable
        }

        try reserveStart()
        var outputFile: RecordingOutputFile?
        do {
            outputFile = try RecordingOutputFile.prepare(destinationURL: request.outputURL)
            try startRecording(request, device: device, outputFile: outputFile!)
        } catch {
            outputFile?.discard()
            clearStartReservation()
            throw error
        }
    }

    private func startRecording(
        _ request: AudioRecordingRequest,
        device: AVCaptureDevice,
        outputFile: RecordingOutputFile
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let writer = try AVAssetWriter(outputURL: outputFile.temporaryURL, fileType: Self.avFileType(for: request.options.fileFormat))
        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: Self.fileSettings(for: request.options)
        )
        audioInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(audioInput) else {
            throw AudioCaptureError.recordingFailed("Could not add audio input to the asset writer.")
        }
        writer.add(audioInput)

        let session = AVCaptureSession()
        session.beginConfiguration()
        let deviceInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(deviceInput) else {
            throw AudioCaptureError.inputUnavailable
        }
        session.addInput(deviceInput)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            throw AudioCaptureError.recordingFailed("Could not add microphone output.")
        }
        session.addOutput(output)
        session.commitConfiguration()

        session.startRunning()

        self.session = session
        self.writer = writer
        self.audioInput = audioInput
        self.outputFile = outputFile
        isStarting = false
        firstPresentationTime = nil
        writerError = nil
        writtenSamples = 0
        activeRequest = request
        startedAt = Date()
        isPaused = false
        pauseStartedAt = nil
        totalPausedDuration = 0
    }

    public func pauseRecording() {
        lock.lock()
        defer { lock.unlock() }
        guard session != nil, !isPaused else { return }
        isPaused = true
        pauseStartedAt = Date()
    }

    public func resumeRecording() {
        lock.lock()
        defer { lock.unlock() }
        guard isPaused else { return }
        if let pauseStartedAt {
            totalPausedDuration += Date().timeIntervalSince(pauseStartedAt)
        }
        isPaused = false
        pauseStartedAt = nil
    }

    public func stopRecording() throws -> AudioRecordingResult {
        let state = try takeActiveRecordingState()
        state.session.stopRunning()

        if let writerError = state.writerError {
            state.writer.cancelWriting()
            state.outputFile?.discard()
            throw AudioCaptureError.recordingFailed(writerError.localizedDescription)
        }
        guard state.writtenSamples > 0 else {
            state.writer.cancelWriting()
            state.outputFile?.discard()
            throw AudioCaptureError.inputUnavailable
        }

        state.audioInput.markAsFinished()
        do {
            try Self.finishWriting(state.writer)
        } catch {
            state.outputFile?.discard()
            throw error
        }
        let outputURL: URL
        do {
            outputURL = try state.outputFile?.commit() ?? state.request.outputURL
        } catch {
            state.outputFile?.discard()
            throw AudioCaptureError.recordingFailed(error.localizedDescription)
        }

        let endedAt = Date()
        return AudioRecordingResult(
            source: state.request.source,
            outputURL: outputURL,
            options: state.request.options,
            durationSeconds: max(0, endedAt.timeIntervalSince(state.startedAt) - state.pausedDuration),
            startedAt: state.startedAt,
            endedAt: endedAt
        )
    }

    private func takeActiveRecordingState() throws -> MicrophoneRecordingState {
        lock.lock()
        guard let session, let writer, let audioInput, let request = activeRequest, let startedAt else {
            lock.unlock()
            throw AudioCaptureError.recorderNotRunning
        }
        let pausedDuration = totalPausedDuration + (pauseStartedAt.map { Date().timeIntervalSince($0) } ?? 0)

        session.stopRunning()
        self.session = nil
        self.writer = nil
        self.audioInput = nil
        firstPresentationTime = nil
        activeRequest = nil
        self.startedAt = nil
        isPaused = false
        pauseStartedAt = nil
        totalPausedDuration = 0
        let writerError = self.writerError
        let writtenSamples = self.writtenSamples
        let outputFile = self.outputFile
        self.writerError = nil
        self.writtenSamples = 0
        self.outputFile = nil
        lock.unlock()

        return MicrophoneRecordingState(
            session: session,
            writer: writer,
            audioInput: audioInput,
            request: request,
            startedAt: startedAt,
            pausedDuration: pausedDuration,
            writerError: writerError,
            writtenSamples: writtenSamples,
            outputFile: outputFile
        )
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard sampleBuffer.isValid else { return }

        lock.lock()
        let isPaused = self.isPaused
        let pauseOffset = totalPausedDuration
        let writer = self.writer
        let audioInput = self.audioInput
        lock.unlock()

        guard !isPaused, let writer, let audioInput else { return }

        let sampleBuffer = SampleBufferTiming.adjusted(sampleBuffer, offsetSeconds: pauseOffset)
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        lock.lock()
        if firstPresentationTime == nil {
            firstPresentationTime = presentationTime
            writer.startWriting()
            writer.startSession(atSourceTime: presentationTime)
        }
        guard writerError == nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        guard audioInput.isReadyForMoreMediaData else { return }
        if audioInput.append(sampleBuffer) {
            lock.lock()
            writtenSamples += 1
            lock.unlock()
        } else if let error = writer.error {
            lock.lock()
            writerError = error
            lock.unlock()
        }
    }

    func reserveStart() throws {
        lock.lock()
        defer { lock.unlock() }
        guard session == nil, writer == nil, !isStarting else {
            throw AudioCaptureError.recorderAlreadyRunning
        }
        isStarting = true
    }

    private func clearStartReservation() {
        lock.lock()
        isStarting = false
        lock.unlock()
    }

    private func validate(_ request: AudioRecordingRequest) throws {
        switch request.source {
        case .microphone(let deviceID):
            if let deviceID, !MicrophoneCaptureDevices.available.contains(where: { $0.id == deviceID }) {
                throw AudioCaptureError.unsupportedSource(request.source)
            }
        case .none, .system, .file:
            throw AudioCaptureError.unsupportedSource(request.source)
        }

        guard request.options.sampleRate > 0, request.options.sampleRate.isFinite else {
            throw AudioCaptureError.invalidOptions("sample rate must be finite and greater than zero")
        }
        guard request.options.channelCount > 0 else {
            throw AudioCaptureError.invalidOptions("channel count must be greater than zero")
        }
        guard request.options.bitRate > 0 else {
            throw AudioCaptureError.invalidOptions("bit rate must be greater than zero")
        }
        guard request.options.waveformPeakCount > 0 else {
            throw AudioCaptureError.invalidOptions("waveform peak count must be greater than zero")
        }
    }

    private static func selectDevice(id: String?) -> AVCaptureDevice? {
        if let id {
            return discoverySession.devices.first { $0.uniqueID == id }
        }
        return AVCaptureDevice.default(for: .audio)
    }

    private static var discoverySession: AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
    }

    private static func fileSettings(for options: AudioRecordingOptions) -> [String: Any] {
        let sampleRate = options.sampleRate
        let channelCount = max(1, options.channelCount)

        switch options.fileFormat {
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: options.bitRate
            ]
        case .caf, .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
    }

    private static func avFileType(for format: AudioFileFormat) -> AVFileType {
        switch format {
        case .caf:
            .caf
        case .wav:
            .wav
        case .m4a:
            .m4a
        }
    }

    static func finishWriting(_ writer: AVAssetWriter, timeoutSeconds: TimeInterval = finishWritingTimeoutSeconds) throws {
        let semaphore = DispatchSemaphore(value: 0)
        final class FinishBox: @unchecked Sendable {
            let writer: AVAssetWriter
            var error: Error?

            init(writer: AVAssetWriter) {
                self.writer = writer
            }
        }
        let box = FinishBox(writer: writer)
        writer.finishWriting {
            box.error = box.writer.error
            semaphore.signal()
        }
        let timeoutNanoseconds = Int(max(0.001, timeoutSeconds) * 1_000_000_000)
        let waitResult = semaphore.wait(timeout: .now() + .nanoseconds(timeoutNanoseconds))
        guard waitResult == .success else {
            writer.cancelWriting()
            throw AudioCaptureError.recordingFailed("Timed out finishing audio writer.")
        }
        if let error = box.error {
            throw AudioCaptureError.recordingFailed(error.localizedDescription)
        }
    }
}

private struct MicrophoneRecordingState {
    var session: AVCaptureSession
    var writer: AVAssetWriter
    var audioInput: AVAssetWriterInput
    var request: AudioRecordingRequest
    var startedAt: Date
    var pausedDuration: TimeInterval
    var writerError: Error?
    var writtenSamples: Int
    var outputFile: RecordingOutputFile?
}
