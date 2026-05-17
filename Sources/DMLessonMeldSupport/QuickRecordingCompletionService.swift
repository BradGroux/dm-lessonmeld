import DMLessonMeldCore
import Foundation

public enum QuickRecordingCompletionService {
    public static func packageForLearnHouse(
        projectURL: URL,
        preferences: LessonMeldPreferences,
        builder: LearnHousePackageBuilder = LearnHousePackageBuilder()
    ) throws -> LearnHousePackageResult {
        try builder.buildPackage(
            projectURL: projectURL,
            outputDirectory: learnHouseExportDirectory(for: projectURL),
            archive: preferences.export.createArchiveByDefault
        )
    }

    public static func learnHouseExportDirectory(for projectURL: URL) -> URL {
        projectURL
            .deletingLastPathComponent()
            .appendingPathComponent("LearnHouse Exports", isDirectory: true)
    }

    public static func renderVideo(
        projectURL: URL,
        preferences: LessonMeldPreferences,
        progress: RenderProgressHandler? = nil
    ) async throws -> URL {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let destinationURL = try uniqueRenderDestination(
            projectURL: projectURL,
            lessonTitle: manifest.metadata.lessonTitle,
            fileType: preferences.export.defaultFileType
        )
        let plan = try ProjectEditorRenderPlanner.makePlan(
            projectURL: projectURL,
            manifest: manifest,
            destinationURL: destinationURL,
            preset: renderPreset(from: preferences.export),
            fallbackWebcamPlacement: webcamPlacement(from: preferences.capture)
        )
        return try await AVFoundationRenderService().export(plan: plan, progress: progress)
    }

    public static func uniqueRenderDestination(
        projectURL: URL,
        lessonTitle: String,
        fileType: RenderFileTypeID,
        fileManager: FileManager = .default
    ) throws -> URL {
        let exportDirectory = projectURL.appendingPathComponent("Exports", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let baseName = slug(lessonTitle.isEmpty ? projectURL.deletingPathExtension().lastPathComponent : lessonTitle)
        let fileExtension = fileType.rawValue
        var candidate = exportDirectory.appendingPathComponent("\(baseName).\(fileExtension)")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = exportDirectory.appendingPathComponent("\(baseName)-\(index).\(fileExtension)")
            index += 1
        }
        return candidate
    }

    public static func renderPreset(from preferences: ExportPreferences) -> RenderPreset {
        RenderPreset(
            fileType: RenderFileType(rawValue: preferences.defaultFileType.rawValue) ?? .mp4,
            quality: RenderQuality(rawValue: preferences.defaultRenderQuality.rawValue) ?? .highest
        )
    }

    public static func webcamPlacement(from capture: CapturePreferences) -> PictureInPicturePlacement {
        PictureInPicturePlacement(
            corner: .bottomTrailing,
            widthRatio: capture.webcamRelativeSize,
            marginRatio: 0.04,
            aspectRatio: PictureInPictureAspectRatio(rawValue: capture.webcamAspectRatio.rawValue) ?? .widescreen16x9,
            frameShape: PictureInPictureFrameShape(rawValue: capture.webcamFrameShape.rawValue) ?? .roundedRectangle,
            cornerRadius: capture.webcamCornerRadius,
            isMirrored: capture.webcamMirror,
            borderEnabled: capture.webcamBorderEnabled,
            shadowEnabled: capture.webcamShadowEnabled
        )
    }

    static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "lesson" : collapsed
    }
}

