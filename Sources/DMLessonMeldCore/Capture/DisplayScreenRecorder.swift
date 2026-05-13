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
    private let queue = DispatchQueue(label: "io.digitalmeld.dm-lessonmeld.display-recorder", qos: .userInitiated)
    private let lock = NSLock()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var firstPresentationTime: CMTime?
    private var writtenFrames = 0
    private var writtenAudioSamples = 0
    private var writerError: Error?
    private var outputURL: URL?
    private var outputSize: CGSize = .zero
    private var isPaused = false
    private var pauseStartedAt: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var firstFrameHandler: (@Sendable () -> Void)?

    public override init() {
        super.init()
    }

    public func setFirstFrameHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        firstFrameHandler = handler
        lock.unlock()
    }

    public func record(_ request: DisplayRecordingRequest) async throws -> RecordingResult {
        guard request.durationSeconds > 0 else {
            throw CaptureError.recordingFailed("Duration must be greater than zero.")
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
        guard sourceRect.width > 0, sourceRect.height > 0 else {
            throw CaptureError.invalidSourceRect
        }
        let pixelSize = ScreenCaptureSession.outputPixelSize(
            for: sourceRect.size,
            displayScale: 1,
            retinaCapture: request.options.retinaCapture
        )

        try prepareWriter(
            outputURL: request.outputURL,
            width: pixelSize.width,
            height: pixelSize.height,
            includeAudio: request.options.captureSystemAudio
        )

        let filter = if let window {
            SCContentFilter(desktopIndependentWindow: window)
        } else {
            SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }
        let configuration = ScreenCaptureSession.configuration(
            sourceRect: sourceRect,
            displayScale: 1,
            options: request.options
        )
        configuration.capturesAudio = request.options.captureSystemAudio

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if request.options.captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        try await stream.startCapture()

        self.stream = stream

        do {
            try await Task.sleep(nanoseconds: UInt64(request.durationSeconds * 1_000_000_000))
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
        lock.lock()
        defer { lock.unlock() }
        guard stream != nil, !isPaused else { return }
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

    public func stopRecording(fps: Int, captureQuality: CaptureQuality, isHDR: Bool) async throws -> RecordingResult {
        guard let stream else {
            throw CaptureError.streamNotRunning
        }

        try await stream.stopCapture()
        self.stream = nil
        isPaused = false
        pauseStartedAt = nil
        totalPausedDuration = 0

        let outputURL = try await finishWriter()
        guard writtenFrames > 0 else {
            throw DisplayScreenRecorderError.noFramesRecorded
        }

        return RecordingResult(
            screenVideoURL: outputURL,
            systemAudioURL: writtenAudioSamples > 0 ? outputURL : nil,
            screenSize: outputSize,
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

        lock.lock()
        defer { lock.unlock() }

        guard !isPaused else {
            return
        }

        guard writerError == nil, let writer else {
            return
        }

        let sampleBuffer = adjustedSampleBuffer(sampleBuffer, offsetSeconds: totalPausedDuration)

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

    private func adjustedSampleBuffer(_ sampleBuffer: CMSampleBuffer, offsetSeconds: TimeInterval) -> CMSampleBuffer {
        guard offsetSeconds > 0 else {
            return sampleBuffer
        }

        var timingCount = 0
        var status = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingCount
        )
        guard status == noErr, timingCount > 0 else {
            return sampleBuffer
        }

        var timing = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: timingCount
        )
        status = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: timingCount,
            arrayToFill: &timing,
            entriesNeededOut: &timingCount
        )
        guard status == noErr else {
            return sampleBuffer
        }

        let offset = CMTime(seconds: offsetSeconds, preferredTimescale: 600)
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, offset)
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, offset)
            }
        }

        var adjustedBuffer: CMSampleBuffer?
        status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingCount,
            sampleTimingArray: &timing,
            sampleBufferOut: &adjustedBuffer
        )
        return status == noErr ? adjustedBuffer ?? sampleBuffer : sampleBuffer
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.lock()
        writerError = error
        lock.unlock()
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
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
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

        lock.lock()
        self.writer = writer
        videoInput = input
        self.audioInput = audioInput
        firstPresentationTime = nil
        writtenFrames = 0
        writtenAudioSamples = 0
        writerError = nil
        self.outputURL = outputURL
        outputSize = CGSize(width: width, height: height)
        lock.unlock()
    }

    private func finishWriter() async throws -> URL {
        let state = takeWriterState()

        if let writerError = state.writerError {
            throw DisplayScreenRecorderError.writerFailed(writerError.localizedDescription)
        }
        guard let writer = state.writer, let input = state.input, let outputURL = state.outputURL else {
            throw DisplayScreenRecorderError.writerFailed("Writer was not initialized.")
        }

        input.markAsFinished()
        state.audioInput?.markAsFinished()
        let writerBox = AssetWriterBox(writer)

        return try await withCheckedThrowingContinuation { continuation in
            writerBox.writer.finishWriting {
                if let error = writerBox.writer.error {
                    continuation.resume(throwing: DisplayScreenRecorderError.writerFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: outputURL)
                }
            }
        }
    }

    private func takeWriterState() -> WriterState {
        let writer: AVAssetWriter?
        let input: AVAssetWriterInput?
        let outputURL: URL?
        let writerError: Error?

        lock.lock()
        writer = self.writer
        input = videoInput
        let audioInput = self.audioInput
        outputURL = self.outputURL
        writerError = self.writerError
        self.writer = nil
        videoInput = nil
        self.audioInput = nil
        self.outputURL = nil
        lock.unlock()

        return WriterState(writer: writer, input: input, audioInput: audioInput, outputURL: outputURL, writerError: writerError)
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
    var outputURL: URL?
    var writerError: Error?
}

private final class AssetWriterBox: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}
