import AVFoundation
import CoreGraphics
import Foundation

public protocol ExportService: Sendable {
    func export(plan: ExportPlan) async throws -> URL
}

public enum AVAssetTrimExportServiceError: Error, Equatable, Sendable {
    case unsupportedPlan(String)
    case unableToCreateExportSession
    case exportFailed(String)
    case exportCancelled
}

public final class AVAssetTrimExportService: ExportService, @unchecked Sendable {
    public init() {}

    public func export(plan: ExportPlan) async throws -> URL {
        guard plan.speedRegions.isEmpty else {
            throw AVAssetTrimExportServiceError.unsupportedPlan(
                "AVAssetTrimExportService does not support speed regions yet."
            )
        }

        if !plan.cuts.isEmpty {
            return try await exportCutComposition(plan: plan)
        }

        let asset = AVURLAsset(url: plan.sourceMediaURL)
        let presetName = exportSessionPresetName(for: plan.preset.quality)

        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw AVAssetTrimExportServiceError.unableToCreateExportSession
        }

        session.outputURL = plan.destinationURL
        session.outputFileType = outputFileType(for: plan.preset.fileType)
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: plan.sourceTimeRange.startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: plan.sourceTimeRange.durationSeconds, preferredTimescale: 600)
        )

        try await TrimExportSessionRunner.export(
            session: session,
            to: plan.destinationURL,
            as: outputFileType(for: plan.preset.fileType)
        )
        return plan.destinationURL
    }

    private func exportCutComposition(plan: ExportPlan) async throws -> URL {
        let retainedRanges = EditTimelineCompiler.retainedRanges(
            sourceRange: plan.sourceTimeRange,
            cuts: plan.cuts
        )
        guard !retainedRanges.isEmpty else {
            throw AVAssetTrimExportServiceError.unsupportedPlan("Enabled cuts remove the entire source range.")
        }

        let asset = AVURLAsset(url: plan.sourceMediaURL)
        let composition = AVMutableComposition()

        let insertedVideoTracks = try await insertTracks(from: asset, mediaType: .video, retainedRanges: retainedRanges, into: composition)
        try await insertTracks(from: asset, mediaType: .audio, retainedRanges: retainedRanges, into: composition)

        guard let session = AVAssetExportSession(asset: composition, presetName: exportSessionPresetName(for: plan.preset.quality)) else {
            throw AVAssetTrimExportServiceError.unableToCreateExportSession
        }
        if plan.preset.quality != .passthrough,
           let firstVideoTrack = insertedVideoTracks.first {
            session.videoComposition = try await videoComposition(
                for: firstVideoTrack,
                duration: composition.duration
            )
        }

        try await TrimExportSessionRunner.export(
            session: session,
            to: plan.destinationURL,
            as: outputFileType(for: plan.preset.fileType)
        )
        return plan.destinationURL
    }

    @discardableResult
    private func insertTracks(
        from asset: AVAsset,
        mediaType: AVMediaType,
        retainedRanges: [EditTimeRange],
        into composition: AVMutableComposition
    ) async throws -> [InsertedTrimTrack] {
        let sourceTracks = try await asset.loadTracks(withMediaType: mediaType)
        var insertedTracks: [InsertedTrimTrack] = []
        for sourceTrack in sourceTracks {
            try Task.checkCancellation()
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: mediaType,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw AVAssetTrimExportServiceError.unableToCreateExportSession
            }
            if mediaType == .video {
                compositionTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
            }

            var outputCursor = CMTime.zero
            for retainedRange in retainedRanges {
                try Task.checkCancellation()
                let sourceTimeRange = CMTimeRange(
                    start: CMTime(seconds: retainedRange.startSeconds, preferredTimescale: 600),
                    duration: CMTime(seconds: retainedRange.durationSeconds, preferredTimescale: 600)
                )
                try compositionTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: outputCursor)
                outputCursor = outputCursor + sourceTimeRange.duration
            }
            insertedTracks.append(InsertedTrimTrack(source: sourceTrack, composition: compositionTrack))
        }
        return insertedTracks
    }

    private func videoComposition(
        for insertedTrack: InsertedTrimTrack,
        duration: CMTime
    ) async throws -> AVMutableVideoComposition {
        let naturalSize = try await insertedTrack.source.load(.naturalSize)
        let preferredTransform = try await insertedTrack.source.load(.preferredTransform)
        let nominalFrameRate = try await insertedTrack.source.load(.nominalFrameRate)
        let display = displayGeometry(naturalSize: naturalSize, preferredTransform: preferredTransform)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: insertedTrack.composition)
        layerInstruction.setTransform(display.transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = evenSize(display.size)
        videoComposition.frameDuration = frameDuration(sourceFrameRate: Double(nominalFrameRate))
        videoComposition.instructions = [instruction]
        return videoComposition
    }

    private func displayGeometry(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> DisplayGeometry {
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let normalize = CGAffineTransform(translationX: -transformed.minX, y: -transformed.minY)
        return DisplayGeometry(
            size: CGSize(width: abs(transformed.width), height: abs(transformed.height)),
            transform: preferredTransform.concatenating(normalize)
        )
    }

    private func evenSize(_ size: CGSize) -> CGSize {
        CGSize(width: evenDimension(size.width), height: evenDimension(size.height))
    }

    private func evenDimension(_ value: CGFloat) -> CGFloat {
        let rounded = Int(value.rounded())
        return CGFloat(rounded.isMultiple(of: 2) ? rounded : rounded + 1)
    }

    private func frameDuration(sourceFrameRate: Double) -> CMTime {
        let framesPerSecond = sourceFrameRate.isFinite && sourceFrameRate > 0 ? sourceFrameRate : 30
        return CMTime(seconds: 1 / framesPerSecond, preferredTimescale: 60_000)
    }

    private func exportSessionPresetName(for quality: ExportQuality) -> String {
        switch quality {
        case .passthrough:
            AVAssetExportPresetPassthrough
        case .medium:
            AVAssetExportPresetMediumQuality
        case .highest:
            AVAssetExportPresetHighestQuality
        }
    }

    private func outputFileType(for fileType: ExportFileType) -> AVFileType {
        switch fileType {
        case .mp4:
            .mp4
        case .mov:
            .mov
        }
    }
}

private struct InsertedTrimTrack {
    var source: AVAssetTrack
    var composition: AVMutableCompositionTrack
}

private struct DisplayGeometry {
    var size: CGSize
    var transform: CGAffineTransform
}

private enum TrimExportSessionRunner {
    static func export(
        session: AVAssetExportSession,
        to destinationURL: URL,
        as fileType: AVFileType
    ) async throws {
        let sessionBox = TrimExportSessionBox(session)

        do {
            try Task.checkCancellation()
            try await withTaskCancellationHandler {
                try await sessionBox.session.export(to: destinationURL, as: fileType)
            } onCancel: {
                sessionBox.session.cancelExport()
            }
        } catch is CancellationError {
            session.cancelExport()
            throw AVAssetTrimExportServiceError.exportCancelled
        } catch {
            throw AVAssetTrimExportServiceError.exportFailed(error.localizedDescription)
        }
    }
}

private final class TrimExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
