import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

public struct ScreenCaptureSessionMetrics: Codable, Equatable, Sendable {
    public var receivedScreenFrames: Int

    public init(receivedScreenFrames: Int = 0) {
        self.receivedScreenFrames = receivedScreenFrames
    }
}

public final class ScreenCaptureSession: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    private var stream: SCStream?

    public private(set) var state: CaptureState = .idle
    public private(set) var metrics = ScreenCaptureSessionMetrics()

    public override init() {
        super.init()
    }

    public func start(
        filter: SCContentFilter,
        sourceRect: CGRect,
        displayScale: CGFloat,
        options: RecordingOptions = RecordingOptions()
    ) async throws {
        guard sourceRect.width > 0, sourceRect.height > 0 else {
            throw CaptureError.invalidSourceRect
        }

        let configuration = Self.configuration(
            sourceRect: sourceRect,
            displayScale: displayScale,
            options: options
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()

        self.stream = stream
        metrics = ScreenCaptureSessionMetrics()
        state = .recording(startedAt: Date())
    }

    public func stop() async throws {
        guard let stream else {
            throw CaptureError.streamNotRunning
        }

        state = .stopping
        try await stream.stopCapture()
        self.stream = nil
        state = .idle
    }

    public static func configuration(
        sourceRect: CGRect,
        displayScale: CGFloat,
        options: RecordingOptions = RecordingOptions()
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let pixelSize = outputPixelSize(for: sourceRect.size, displayScale: displayScale, retinaCapture: options.retinaCapture)

        configuration.sourceRect = sourceRect
        configuration.width = pixelSize.width
        configuration.height = pixelSize.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, options.fps)))
        configuration.showsCursor = options.includeCursor
        configuration.capturesAudio = options.captureSystemAudio
        configuration.queueDepth = 8
        configuration.scalesToFit = options.retinaCapture

        if options.hdrCapture {
            configuration.colorSpaceName = CGColorSpace.displayP3 as CFString
            configuration.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            configuration.captureDynamicRange = .hdrLocalDisplay
        } else {
            configuration.colorSpaceName = CGColorSpace.sRGB as CFString
            configuration.pixelFormat = options.captureQuality.isProRes
                ? kCVPixelFormatType_32BGRA
                : kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
        }

        return configuration
    }

    public static func outputPixelSize(
        for sourceSize: CGSize,
        displayScale: CGFloat,
        retinaCapture: Bool
    ) -> (width: Int, height: Int) {
        let scale = max(displayScale, 1)
        var width = Int((sourceSize.width * scale).rounded()) & ~1
        var height = Int((sourceSize.height * scale).rounded()) & ~1

        if retinaCapture {
            width = (width * 2) & ~1
            height = (height * 2) & ~1
        }

        return (max(width, 2), max(height, 2))
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, type == .screen else {
            return
        }

        metrics.receivedScreenFrames += 1
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        state = .failed(message: error.localizedDescription)
        self.stream = nil
    }
}
