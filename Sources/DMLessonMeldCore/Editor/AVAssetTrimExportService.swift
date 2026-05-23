import AVFoundation
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

        try await insertTracks(from: asset, mediaType: .video, retainedRanges: retainedRanges, into: composition)
        try await insertTracks(from: asset, mediaType: .audio, retainedRanges: retainedRanges, into: composition)

        guard let session = AVAssetExportSession(asset: composition, presetName: exportSessionPresetName(for: plan.preset.quality)) else {
            throw AVAssetTrimExportServiceError.unableToCreateExportSession
        }

        try await TrimExportSessionRunner.export(
            session: session,
            to: plan.destinationURL,
            as: outputFileType(for: plan.preset.fileType)
        )
        return plan.destinationURL
    }

    private func insertTracks(
        from asset: AVAsset,
        mediaType: AVMediaType,
        retainedRanges: [EditTimeRange],
        into composition: AVMutableComposition
    ) async throws {
        let sourceTracks = try await asset.loadTracks(withMediaType: mediaType)
        for sourceTrack in sourceTracks {
            try Task.checkCancellation()
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: mediaType,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw AVAssetTrimExportServiceError.unableToCreateExportSession
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
        }
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
