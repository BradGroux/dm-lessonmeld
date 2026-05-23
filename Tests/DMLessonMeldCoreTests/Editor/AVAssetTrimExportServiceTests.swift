import AVFoundation
import CoreGraphics
import DMLessonMeldCore
import Foundation
import Testing

@Suite("AVAsset edit export service")
struct AVAssetTrimExportServiceTests {
    @Test("Exports synthetic media with enabled cuts removed")
    func exportsCutComposition() async throws {
        let temp = try TemporaryDirectory()
        let sourceURL = temp.url.appendingPathComponent("source.mp4")
        let outputURL = temp.url.appendingPathComponent("output.mp4")
        try await SyntheticVideoWriter.write(
            outputURL: sourceURL,
            size: CGSize(width: 96, height: 54),
            color: (red: 36, green: 92, blue: 160),
            frameCount: 30,
            fps: 30
        )

        let editDecisionList = EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: sourceURL,
            sourceDurationSeconds: 1,
            cuts: [
                TimelineCut(id: "cut-1", range: EditTimeRange(startSeconds: 0.25, endSeconds: 0.5))
            ]
        )
        let plan = try ExportJob(
            id: "export-cut",
            editDecisionList: editDecisionList,
            destinationURL: outputURL,
            preset: ExportPreset(id: "mp4-medium", quality: .medium)
        ).makePlan()

        let exportedURL = try await AVAssetTrimExportService().export(plan: plan)

        let byteCount = try #require(FileManager.default.attributesOfItem(atPath: exportedURL.path)[.size] as? Int64)
        #expect(byteCount > 0)
        let duration = try await AVURLAsset(url: exportedURL).load(.duration).seconds
        #expect(duration > 0.4)
        #expect(duration < 0.9)
    }

    @Test("Cut composition preserves source video orientation")
    func cutCompositionPreservesSourceVideoOrientation() async throws {
        let temp = try TemporaryDirectory()
        let sourceURL = temp.url.appendingPathComponent("rotated-source.mp4")
        let outputURL = temp.url.appendingPathComponent("rotated-output.mp4")
        let rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 54, ty: 0)
        try await SyntheticVideoWriter.write(
            outputURL: sourceURL,
            size: CGSize(width: 96, height: 54),
            color: (red: 80, green: 40, blue: 170),
            frameCount: 30,
            fps: 30,
            transform: rotation
        )

        let editDecisionList = EditDecisionList(
            id: "rotated-edit",
            sourceMediaURL: sourceURL,
            sourceDurationSeconds: 1,
            cuts: [
                TimelineCut(id: "cut-1", range: EditTimeRange(startSeconds: 0.2, endSeconds: 0.4))
            ]
        )
        let plan = try ExportJob(
            id: "rotated-export",
            editDecisionList: editDecisionList,
            destinationURL: outputURL,
            preset: ExportPreset(id: "mp4-medium", quality: .medium)
        ).makePlan()

        _ = try await AVAssetTrimExportService().export(plan: plan)

        let sourceDisplaySize = try await firstVideoDisplaySize(sourceURL)
        let outputDisplaySize = try await firstVideoDisplaySize(outputURL)
        #expect(outputDisplaySize.isApproximatelyEqual(to: sourceDisplaySize))
    }

    private func firstVideoDisplaySize(_ url: URL) async throws -> CGSize {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try #require(tracks.first)
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-editor-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private enum SyntheticVideoWriter {
    static func write(
        outputURL: URL,
        size: CGSize,
        color: (red: UInt8, green: UInt8, blue: UInt8),
        frameCount: Int,
        fps: Int32,
        transform: CGAffineTransform = .identity
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        #expect(writer.canAdd(input))
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let pixelBuffer = try makePixelBuffer(size: size, color: color)
            #expect(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: fps)))
        }

        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error {
            throw error
        }
    }

    private static func makePixelBuffer(
        size: CGSize,
        color: (red: UInt8, green: UInt8, blue: UInt8)
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw SyntheticVideoWriterError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw SyntheticVideoWriterError.pixelBufferBaseAddressMissing
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                buffer[offset] = color.blue
                buffer[offset + 1] = color.green
                buffer[offset + 2] = color.red
                buffer[offset + 3] = 255
            }
        }
        return pixelBuffer
    }
}

private enum SyntheticVideoWriterError: Error {
    case pixelBufferCreationFailed(CVReturn)
    case pixelBufferBaseAddressMissing
}

private extension CGSize {
    func isApproximatelyEqual(to other: CGSize, tolerance: CGFloat = 0.001) -> Bool {
        abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}
