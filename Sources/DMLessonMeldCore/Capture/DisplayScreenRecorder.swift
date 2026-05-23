import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public struct DisplayRecordingRequest: Sendable {
    public var displayID: CGDirectDisplayID?
    public var outputURL: URL
    public var durationSeconds: TimeInterval
    public var options: RecordingOptions
    public var sourceRect: CGRect?
    public var windowID: UInt32?

    public init(
        displayID: CGDirectDisplayID? = nil,
        outputURL: URL,
        durationSeconds: TimeInterval,
        options: RecordingOptions = RecordingOptions(),
        sourceRect: CGRect? = nil,
        windowID: UInt32? = nil
    ) {
        self.displayID = displayID
        self.outputURL = outputURL
        self.durationSeconds = durationSeconds
        self.options = options
        self.sourceRect = sourceRect
        self.windowID = windowID
    }
}

public enum DisplayScreenRecorderError: Error, LocalizedError {
    case noDisplayAvailable
    case requestedDisplayNotFound(CGDirectDisplayID)
    case alreadyRecording
    case cannotAddWriterInput
    case cannotAddAudioInput
    case writerFailed(String)
    case noFramesRecorded
    case requestedWindowNotFound(UInt32)

    public var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            "No capturable display is available."
        case .requestedDisplayNotFound(let displayID):
            "Requested display was not found: \(displayID)."
        case .alreadyRecording:
            "A display recording is already in progress."
        case .cannotAddWriterInput:
            "Could not add video input to the asset writer."
        case .cannotAddAudioInput:
            "Could not add audio input to the asset writer."
        case .writerFailed(let reason):
            "Screen recording writer failed: \(reason)"
        case .noFramesRecorded:
            "Screen recording completed without receiving any frames."
        case .requestedWindowNotFound(let windowID):
            "Requested window was not found: \(windowID)."
        }
    }
}

public final class DisplayScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "io.digitalmeld.dm-lessonmeld.display-recorder", qos: .userInitiated)
    private let stateQueueKey = DispatchSpecificKey<Void>()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var firstPresentationTime: CMTime?
    private var writtenFrames = 0
    private var writtenAudioSamples = 0
    private var writerError: Error?
    private var outputFile: RecordingOutputFile?
    private var outputSize: CGSize = .zero
    private var isStarting = false
    private var isPaused = false
    private var pauseStartedAt: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var firstFrameHandler: (@Sendable () -> Void)?

    public override init() {
        super.init()
        stateQueue.setSpecific(key: stateQueueKey, value: ())
    }

    public func setFirstFrameHandler(_ handler: (@Sendable () -> Void)?) {
        syncState {
            firstFrameHandler = handler
        }
    }

    public func record(_ request: DisplayRecordingRequest) async throws -> RecordingResult {
        let durationSeconds: TimeInterval
        do {
            durationSeconds = try NumericInputValidation.recordingDuration(request.durationSeconds)
        } catch {
            throw CaptureError.recordingFailed(error.localizedDescription)
        }
        guard ScreenCapturePermission.isGranted else {
            throw CaptureError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = try selectDisplay(from: content.displays, displayID: request.displayID)
        let window = try request.windowID.map { try selectWindow(from: content.windows, windowID: $0) }
        let sourceRect = request.sourceRect ?? window.map {
            CGRect(x: 0, y: 0, width: $0.frame.width, height: $0.frame.height)
        } ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        guard let validatedSourceRect = try? NumericInputValidation.captureRect(sourceRect) else {
            throw CaptureError.invalidSourceRect
        }
        let pixelSize = try ScreenCaptureSession.validatedOutputPixelSize(
            for: validatedSourceRect.size,
            displayScale: 1,
            retinaCapture: request.options.retinaCapture
        )

        try reserveStart()
        do {
            try prepareWriter(
                outputURL: request.outputURL,
                width: pixelSize.width,
                height: pixelSize.height,
                includeAudio: request.options.captureSystemAudio
            )
        } catch {
            resetStateAfterFailedStart()
            throw error
        }

        let filter = if let window {
            SCContentFilter(desktopIndependentWindow: window)
        } else {
            SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }
        let configuration = ScreenCaptureSession.configuration(
            sourceRect: validatedSourceRect,
            displayScale: 1,
            options: request.options
        )
        configuration.capturesAudio = request.options.captureSystemAudio

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: stateQueue)
            if request.options.captureSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: stateQueue)
            }
            try await stream.startCapture()

            syncState {
                self.stream = stream
                isStarting = false
            }
        } catch {
            resetStateAfterFailedStart()
            throw error
        }

        do {
            try await Task.sleep(nanoseconds: try NumericInputValidation.sleepNanoseconds(forRecordingDuration: durationSeconds))
            return try await stopRecording(
                fps: request.options.fps,
                captureQuality: request.options.captureQuality,
                isHDR: request.options.hdrCapture
            )
        } catch is CancellationError {
            return try await stopRecording(
                fps: request.options.fps,
                captureQuality: request.options.captureQuality,
                isHDR: request.options.hdrCapture
            )
        } catch {
            _ = try? await stopRecording(
                fps: request.options.fps,
                captureQuality: request.options.captureQuality,
                isHDR: request.options.hdrCapture
            )
            throw error
        }
    }

    public func pauseRecording() {
        syncState {
            guard stream != nil, !isPaused else { return }
            isPaused = true
            pauseStartedAt = Date()
        }
    }

    public func resumeRecording() {
        syncState {
            guard isPaused else { return }
            if let pauseStartedAt {
                totalPausedDuration += Date().timeIntervalSince(pauseStartedAt)
            }
            isPaused = false
            pauseStartedAt = nil
        }
    }

    public func stopRecording(fps: Int, captureQuality: CaptureQuality, isHDR: Bool) async throws -> RecordingResult {
        let stream = try activeStream()

        do {
            try await stream.stopCapture()
        } catch {
            clearStreamState()
            let writerState = takeWriterState()
            writerState.writer?.cancelWriting()
            writerState.outputFile?.discard()
            throw error
        }
        clearStreamState()

        let writerState = takeWriterState()
        guard writerState.writtenFrames > 0 else {
            writerState.writer?.cancelWriting()
            writerState.outputFile?.discard()
            throw DisplayScreenRecorderError.noFramesRecorded
        }
        let outputURL = try await finishWriter(writerState)

        return RecordingResult(
            screenVideoURL: outputURL,
            systemAudioURL: writerState.writtenAudioSamples > 0 ? outputURL : nil,
            screenSize: writerState.outputSize,
            fps: fps,
            captureQuality: captureQuality,
            isHDR: isHDR,
            endedAt: Date()
        )
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else {
            return
        }

        guard !isPaused else {
            return
        }

        guard writerError == nil, let writer else {
            return
        }

        let sampleBuffer = SampleBufferTiming.adjusted(sampleBuffer, offsetSeconds: totalPausedDuration)

        switch type {
        case .screen:
            guard frameIsComplete(sampleBuffer), let videoInput else {
                return
            }
            startWriterIfNeeded(writer, sampleBuffer: sampleBuffer)
            guard videoInput.isReadyForMoreMediaData else {
                return
            }
            if videoInput.append(sampleBuffer) {
                writtenFrames += 1
            } else if let error = writer.error {
                writerError = error
            }
        case .audio, .microphone:
            guard let audioInput else {
                return
            }
            startWriterIfNeeded(writer, sampleBuffer: sampleBuffer)
            guard audioInput.isReadyForMoreMediaData else {
                return
            }
            if audioInput.append(sampleBuffer) {
                writtenAudioSamples += 1
            } else if let error = writer.error {
                writerError = error
            }
        @unknown default:
            return
        }
    }

    private func startWriterIfNeeded(_ writer: AVAssetWriter, sampleBuffer: CMSampleBuffer) {
        if firstPresentationTime == nil {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            firstPresentationTime = pts
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            firstFrameHandler?()
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        syncState {
            writerError = error
        }
    }

    private func selectDisplay(from displays: [SCDisplay], displayID: CGDirectDisplayID?) throws -> SCDisplay {
        guard let displayID else {
            guard let display = displays.first else {
                throw DisplayScreenRecorderError.noDisplayAvailable
            }
            return display
        }

        guard let display = displays.first(where: { $0.displayID == displayID }) else {
            throw DisplayScreenRecorderError.requestedDisplayNotFound(displayID)
        }
        return display
    }

    private func selectWindow(from windows: [SCWindow], windowID: UInt32) throws -> SCWindow {
        guard let window = windows.first(where: { $0.windowID == windowID }) else {
            throw DisplayScreenRecorderError.requestedWindowNotFound(windowID)
        }
        return window
    }

    private func prepareWriter(outputURL: URL, width: Int, height: Int, includeAudio: Bool) throws {
        let outputFile = try RecordingOutputFile.prepare(destinationURL: outputURL)

        do {
            let writer = try AVAssetWriter(outputURL: outputFile.temporaryURL, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true

            guard writer.canAdd(input) else {
                throw DisplayScreenRecorderError.cannotAddWriterInput
            }

            writer.add(input)

            let audioInput: AVAssetWriterInput?
            if includeAudio {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 48_000,
                    AVEncoderBitRateKey: 192_000
                ]
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else {
                    throw DisplayScreenRecorderError.cannotAddAudioInput
                }
                writer.add(input)
                audioInput = input
            } else {
                audioInput = nil
            }

            try syncState {
                guard stream == nil, self.writer == nil else {
                    throw DisplayScreenRecorderError.alreadyRecording
                }
                self.writer = writer
                videoInput = input
                self.audioInput = audioInput
                firstPresentationTime = nil
                writtenFrames = 0
                writtenAudioSamples = 0
                writerError = nil
                self.outputFile = outputFile
                outputSize = CGSize(width: width, height: height)
            }
        } catch {
            outputFile.discard()
            throw error
        }
    }

    private func finishWriter(_ state: WriterState) async throws -> URL {
        if let writerError = state.writerError {
            state.writer?.cancelWriting()
            state.outputFile?.discard()
            throw DisplayScreenRecorderError.writerFailed(writerError.localizedDescription)
        }
        guard let writer = state.writer, let input = state.input, let outputFile = state.outputFile else {
            state.outputFile?.discard()
            throw DisplayScreenRecorderError.writerFailed("Writer was not initialized.")
        }

        input.markAsFinished()
        state.audioInput?.markAsFinished()
        let writerBox = AssetWriterBox(writer)

        return try await withCheckedThrowingContinuation { continuation in
            writerBox.writer.finishWriting {
                if let error = writerBox.writer.error {
                    outputFile.discard()
                    continuation.resume(throwing: DisplayScreenRecorderError.writerFailed(error.localizedDescription))
                } else {
                    do {
                        continuation.resume(returning: try outputFile.commit())
                    } catch {
                        outputFile.discard()
                        continuation.resume(throwing: DisplayScreenRecorderError.writerFailed(error.localizedDescription))
                    }
                }
            }
        }
    }

    private func takeWriterState() -> WriterState {
        syncState {
            let writer = self.writer
            let input = videoInput
            let audioInput = self.audioInput
            let outputFile = self.outputFile
            let writerError = self.writerError
            let writtenFrames = self.writtenFrames
            let writtenAudioSamples = self.writtenAudioSamples
            let outputSize = self.outputSize

            self.writer = nil
            videoInput = nil
            self.audioInput = nil
            self.outputFile = nil

            return WriterState(
                writer: writer,
                input: input,
                audioInput: audioInput,
                outputFile: outputFile,
                writerError: writerError,
                writtenFrames: writtenFrames,
                writtenAudioSamples: writtenAudioSamples,
                outputSize: outputSize
            )
        }
    }

    private func activeStream() throws -> SCStream {
        try syncState {
            guard let stream else {
                throw CaptureError.streamNotRunning
            }
            return stream
        }
    }

    private func clearStreamState() {
        syncState {
            stream = nil
            isStarting = false
            isPaused = false
            pauseStartedAt = nil
            totalPausedDuration = 0
        }
    }

    func reserveStart() throws {
        try syncState {
            guard stream == nil, writer == nil, !isStarting else {
                throw DisplayScreenRecorderError.alreadyRecording
            }
            isStarting = true
        }
    }

    private func resetStateAfterFailedStart() {
        syncState {
            writer?.cancelWriting()
            outputFile?.discard()
            stream = nil
            writer = nil
            videoInput = nil
            audioInput = nil
            firstPresentationTime = nil
            writtenFrames = 0
            writtenAudioSamples = 0
            writerError = nil
            outputFile = nil
            outputSize = .zero
            isStarting = false
            isPaused = false
            pauseStartedAt = nil
            totalPausedDuration = 0
        }
    }

    private func syncState<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            return try work()
        }
        return try stateQueue.sync(execute: work)
    }

    private func frameIsComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusValue) else {
            return false
        }
        return status == .complete
    }
}

private struct WriterState {
    var writer: AVAssetWriter?
    var input: AVAssetWriterInput?
    var audioInput: AVAssetWriterInput?
    var outputFile: RecordingOutputFile?
    var writerError: Error?
    var writtenFrames: Int
    var writtenAudioSamples: Int
    var outputSize: CGSize
}

private final class AssetWriterBox: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}
