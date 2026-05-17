import AVFoundation
import Foundation

enum RenderExportSessionRunner {
    static func export(
        session: AVAssetExportSession,
        to destinationURL: URL,
        as fileType: RenderFileType,
        progress: RenderProgressHandler?
    ) async throws {
        let sessionBox = ExportSessionBox(session)
        let progressTask = Task { @MainActor in
            guard let progress else { return }
            progress(Double(sessionBox.session.progress))
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                progress(Double(sessionBox.session.progress))
            }
        }
        defer { progressTask.cancel() }

        do {
            try await session.export(to: destinationURL, as: avFileType(for: fileType))
            await progress?(1)
        } catch is CancellationError {
            session.cancelExport()
            throw RenderExportError.exportCancelled
        } catch {
            throw RenderExportError.exportFailed(error.localizedDescription)
        }
    }

    private static func avFileType(for fileType: RenderFileType) -> AVFileType {
        switch fileType {
        case .mp4:
            .mp4
        case .mov:
            .mov
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
