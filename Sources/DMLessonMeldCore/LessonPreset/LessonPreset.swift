import Foundation

public struct LessonPreset: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var summary: String?
    public var createdAt: Date
    public var editorSettings: EditorSettings?
    public var capturePreferences: CapturePreferences?
    public var annotationPreferences: AnnotationPreferences?
    public var exportPreferences: ExportPreferences?
    public var exportPresetIDs: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String = UUID().uuidString,
        name: String,
        summary: String? = nil,
        createdAt: Date = Date(),
        editorSettings: EditorSettings? = nil,
        capturePreferences: CapturePreferences? = nil,
        annotationPreferences: AnnotationPreferences? = nil,
        exportPreferences: ExportPreferences? = nil,
        exportPresetIDs: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Preset" : name
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.summary = trimmedSummary.isEmpty ? nil : trimmedSummary
        self.createdAt = createdAt
        self.editorSettings = editorSettings
        self.capturePreferences = capturePreferences?.normalized()
        self.annotationPreferences = annotationPreferences?.normalized()
        self.exportPreferences = exportPreferences?.normalized()
        self.exportPresetIDs = Self.normalizedPresetIDs(exportPresetIDs)
    }

    public func normalized() -> LessonPreset {
        LessonPreset(
            schemaVersion: max(schemaVersion, Self.currentSchemaVersion),
            id: id,
            name: name,
            summary: summary,
            createdAt: createdAt,
            editorSettings: editorSettings,
            capturePreferences: capturePreferences,
            annotationPreferences: annotationPreferences,
            exportPreferences: exportPreferences,
            exportPresetIDs: exportPresetIDs
        )
    }

    public static func make(
        fromProject projectURL: URL,
        preferences: LessonMeldPreferences? = nil,
        name: String,
        summary: String? = nil,
        id: String = UUID().uuidString,
        createdAt: Date = Date()
    ) throws -> LessonPreset {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let settings = try EditorSettingsFile.loadIfPresent(fromProject: projectURL) ?? EditorSettings()
        return LessonPreset(
            id: id,
            name: name,
            summary: summary,
            createdAt: createdAt,
            editorSettings: settings,
            capturePreferences: preferences?.capture,
            annotationPreferences: preferences?.annotation,
            exportPreferences: preferences?.export,
            exportPresetIDs: manifest.exportPresets
        )
    }

    private static func normalizedPresetIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.compactMap { id in
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                return nil
            }
            return trimmed
        }
    }
}

public enum LessonPresetFile {
    public static let fileExtension = "dmlpreset"

    public static func load(from url: URL) throws -> LessonPreset {
        let data = try Data(contentsOf: url)
        return try DMLessonJSON.decoder().decode(LessonPreset.self, from: data).normalized()
    }

    public static func save(_ preset: LessonPreset, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try DMLessonJSON.encoder().encode(preset.normalized())
        try data.write(to: url, options: [.atomic])
    }
}

public struct LessonPresetApplyPreview: Codable, Equatable, Sendable {
    public var presetName: String
    public var writesEditorSettings: Bool
    public var updatesCaptureSettings: Bool
    public var updatesExportPresets: Bool
    public var updatesAppPreferences: Bool
    public var preservedProjectFields: [String]

    public init(
        presetName: String,
        writesEditorSettings: Bool,
        updatesCaptureSettings: Bool,
        updatesExportPresets: Bool,
        updatesAppPreferences: Bool,
        preservedProjectFields: [String] = ["metadata", "media", "tracks", "markers"]
    ) {
        self.presetName = presetName
        self.writesEditorSettings = writesEditorSettings
        self.updatesCaptureSettings = updatesCaptureSettings
        self.updatesExportPresets = updatesExportPresets
        self.updatesAppPreferences = updatesAppPreferences
        self.preservedProjectFields = preservedProjectFields
    }
}

public enum LessonPresetApplier {
    @discardableResult
    public static func preview(
        _ preset: LessonPreset,
        applyingAppPreferences: Bool = false
    ) -> LessonPresetApplyPreview {
        LessonPresetApplyPreview(
            presetName: preset.name,
            writesEditorSettings: preset.editorSettings != nil,
            updatesCaptureSettings: preset.capturePreferences != nil,
            updatesExportPresets: !preset.exportPresetIDs.isEmpty,
            updatesAppPreferences: applyingAppPreferences && (
                preset.capturePreferences != nil
                    || preset.annotationPreferences != nil
                    || preset.exportPreferences != nil
            )
        )
    }

    @discardableResult
    public static func apply(
        _ preset: LessonPreset,
        toProject projectURL: URL
    ) throws -> LessonPresetApplyPreview {
        let normalized = preset.normalized()
        if let editorSettings = normalized.editorSettings {
            try EditorSettingsFile.save(editorSettings, toProject: projectURL)
        }

        if normalized.capturePreferences != nil || !normalized.exportPresetIDs.isEmpty {
            _ = try ProjectBundle.updateManifest(at: projectURL) { manifest in
                if let capture = normalized.capturePreferences {
                    manifest.capture = ProjectCaptureSettings(from: capture)
                }
                if !normalized.exportPresetIDs.isEmpty {
                    manifest.exportPresets = normalized.exportPresetIDs
                }
            }
        }

        return preview(normalized)
    }

    public static func applyPreferences(
        _ preset: LessonPreset,
        to preferences: LessonMeldPreferences
    ) -> LessonMeldPreferences {
        var next = preferences
        if let capture = preset.capturePreferences {
            next.capture = capture.normalized()
        }
        if let annotation = preset.annotationPreferences {
            next.annotation = annotation.normalized()
        }
        if let export = preset.exportPreferences {
            next.export = export.normalized()
        }
        return next.normalized()
    }
}

public extension ProjectCaptureSettings {
    init(from preferences: CapturePreferences) {
        self.init(
            screenFPS: preferences.fps,
            includeCursor: preferences.includeCursor,
            captureInteractionMetadata: preferences.captureInteractionMetadata,
            captureMicrophone: preferences.captureMicrophone,
            microphoneDeviceID: preferences.microphoneDeviceID,
            captureWebcam: preferences.captureWebcam,
            captureSystemAudio: preferences.captureSystemAudio,
            webcam: ProjectWebcamCaptureSettings(
                resolution: preferences.cameraResolution,
                fps: preferences.webcamFPS,
                aspectRatio: preferences.webcamAspectRatio,
                frameShape: preferences.webcamFrameShape,
                cornerRadius: preferences.webcamCornerRadius,
                relativeSize: preferences.webcamRelativeSize,
                isMirrored: preferences.webcamMirror,
                borderEnabled: preferences.webcamBorderEnabled,
                shadowEnabled: preferences.webcamShadowEnabled
            )
        )
    }
}
