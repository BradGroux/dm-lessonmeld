import Foundation

public struct LessonMeldPreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 9

    public var schemaVersion: Int
    public var firstRunCompletedAt: Date?
    public var general: GeneralPreferences
    public var capture: CapturePreferences
    public var transcription: TranscriptionPreferences
    public var annotation: AnnotationPreferences
    public var export: ExportPreferences
    public var integrations: IntegrationPreferences
    public var privacy: PrivacyPreferences
    public var shortcuts: [LessonMeldShortcutAction: String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case firstRunCompletedAt
        case general
        case capture
        case transcription
        case annotation
        case export
        case integrations
        case privacy
        case shortcuts
    }

    public init(
        schemaVersion: Int = LessonMeldPreferences.currentSchemaVersion,
        firstRunCompletedAt: Date? = nil,
        general: GeneralPreferences = GeneralPreferences(),
        capture: CapturePreferences = CapturePreferences(),
        transcription: TranscriptionPreferences = TranscriptionPreferences(),
        annotation: AnnotationPreferences = AnnotationPreferences(),
        export: ExportPreferences = ExportPreferences(),
        integrations: IntegrationPreferences = IntegrationPreferences(),
        privacy: PrivacyPreferences = PrivacyPreferences(),
        shortcuts: [LessonMeldShortcutAction: String] = LessonMeldShortcutAction.defaultShortcuts
    ) {
        self.schemaVersion = schemaVersion
        self.firstRunCompletedAt = firstRunCompletedAt
        self.general = general.normalized()
        self.capture = capture.normalized()
        self.transcription = transcription.normalized()
        self.annotation = annotation.normalized()
        self.export = export.normalized()
        self.integrations = integrations
        self.privacy = privacy
        self.shortcuts = Self.normalizedShortcuts(shortcuts)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let shortcutStrings = try container.decodeIfPresent([String: String].self, forKey: .shortcuts) ?? [:]
        let decodedShortcuts = Dictionary(
            uniqueKeysWithValues: shortcutStrings.compactMap { key, value in
                LessonMeldShortcutAction(rawValue: key).map { ($0, value) }
            }
        )
        var capture = try container.decodeIfPresent(CapturePreferences.self, forKey: .capture) ?? CapturePreferences()
        if decodedSchemaVersion < 2, capture.captureWebcam == false {
            capture.captureWebcam = true
        }
        if decodedSchemaVersion < 3, capture.quickRecordDurationSeconds == 5 {
            capture.quickRecordDurationSeconds = CapturePreferences.defaultQuickRecordDurationSeconds
        }
        if decodedSchemaVersion < 6, capture.hideRecorderControlsFromCapture {
            capture.hideRecorderControlsFromCapture = false
        }

        self.init(
            schemaVersion: max(decodedSchemaVersion, Self.currentSchemaVersion),
            firstRunCompletedAt: try container.decodeIfPresent(Date.self, forKey: .firstRunCompletedAt),
            general: try container.decodeIfPresent(GeneralPreferences.self, forKey: .general) ?? GeneralPreferences(),
            capture: capture,
            transcription: try container.decodeIfPresent(TranscriptionPreferences.self, forKey: .transcription) ?? TranscriptionPreferences(),
            annotation: try container.decodeIfPresent(AnnotationPreferences.self, forKey: .annotation) ?? AnnotationPreferences(),
            export: try container.decodeIfPresent(ExportPreferences.self, forKey: .export) ?? ExportPreferences(),
            integrations: try container.decodeIfPresent(IntegrationPreferences.self, forKey: .integrations) ?? IntegrationPreferences(),
            privacy: try container.decodeIfPresent(PrivacyPreferences.self, forKey: .privacy) ?? PrivacyPreferences(),
            shortcuts: decodedShortcuts
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(firstRunCompletedAt, forKey: .firstRunCompletedAt)
        try container.encode(general, forKey: .general)
        try container.encode(capture, forKey: .capture)
        try container.encode(transcription, forKey: .transcription)
        try container.encode(annotation, forKey: .annotation)
        try container.encode(export, forKey: .export)
        try container.encode(integrations, forKey: .integrations)
        try container.encode(privacy, forKey: .privacy)
        try container.encode(
            Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) }),
            forKey: .shortcuts
        )
    }

    public var onboardingCompleted: Bool {
        firstRunCompletedAt != nil
    }

    public func normalized() -> LessonMeldPreferences {
        LessonMeldPreferences(
            schemaVersion: max(schemaVersion, Self.currentSchemaVersion),
            firstRunCompletedAt: firstRunCompletedAt,
            general: general,
            capture: capture,
            transcription: transcription,
            annotation: annotation,
            export: export,
            integrations: integrations,
            privacy: privacy,
            shortcuts: shortcuts
        )
    }

    public static func normalizedShortcuts(_ shortcuts: [LessonMeldShortcutAction: String]) -> [LessonMeldShortcutAction: String] {
        var normalized = LessonMeldShortcutAction.defaultShortcuts
        for (action, shortcut) in shortcuts {
            let trimmed = shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            normalized[action] = trimmed
        }
        return normalized
    }
}

public enum LessonMeldPreferencesFileError: Error, Equatable, LocalizedError {
    case oversizedPreferences(URL, byteCount: Int64, limit: Int64)
    case unreadablePreferences(URL, String)

    public var errorDescription: String? {
        switch self {
        case .oversizedPreferences(let url, let byteCount, let limit):
            "LessonMeld preferences file is too large: \(url.path) is \(byteCount) bytes, limit is \(limit) bytes."
        case .unreadablePreferences(let url, let reason):
            "LessonMeld preferences file could not be decoded at \(url.path): \(reason)"
        }
    }
}

public enum LessonMeldPreferencesFile {
    public static let maxPreferencesBytes: Int64 = 1 * 1024 * 1024

    public static func load(from url: URL) throws -> LessonMeldPreferences {
        let data = try boundedPreferencesData(from: url)
        do {
            return try DMLessonJSON.decoder().decode(LessonMeldPreferences.self, from: data)
        } catch {
            throw LessonMeldPreferencesFileError.unreadablePreferences(url, error.localizedDescription)
        }
    }

    private static func boundedPreferencesData(from url: URL) throws -> Data {
        if let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init),
           byteCount > maxPreferencesBytes {
            throw LessonMeldPreferencesFileError.oversizedPreferences(url, byteCount: byteCount, limit: maxPreferencesBytes)
        }
        let data = try Data(contentsOf: url)
        if Int64(data.count) > maxPreferencesBytes {
            throw LessonMeldPreferencesFileError.oversizedPreferences(url, byteCount: Int64(data.count), limit: maxPreferencesBytes)
        }
        return data
    }
}

public struct GeneralPreferences: Codable, Equatable, Sendable {
    public var appearance: AppAppearance
    public var defaultProjectDirectory: String
    public var defaultTemplateID: String
    public var showMainWindowAtLaunch: Bool
    public var showAnnotationOverlayAtLaunch: Bool

    private enum CodingKeys: String, CodingKey {
        case appearance
        case defaultProjectDirectory
        case defaultTemplateID
        case showMainWindowAtLaunch
        case showAnnotationOverlayAtLaunch
    }

    public init(
        appearance: AppAppearance = .system,
        defaultProjectDirectory: String = "~/Movies/DMLessonMeld",
        defaultTemplateID: String = "workshop-lesson",
        showMainWindowAtLaunch: Bool = true,
        showAnnotationOverlayAtLaunch: Bool = false
    ) {
        self.appearance = appearance
        self.defaultProjectDirectory = defaultProjectDirectory
        self.defaultTemplateID = defaultTemplateID
        self.showMainWindowAtLaunch = showMainWindowAtLaunch
        self.showAnnotationOverlayAtLaunch = showAnnotationOverlayAtLaunch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            appearance: try container.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system,
            defaultProjectDirectory: try container.decodeIfPresent(String.self, forKey: .defaultProjectDirectory) ?? "~/Movies/DMLessonMeld",
            defaultTemplateID: try container.decodeIfPresent(String.self, forKey: .defaultTemplateID) ?? "workshop-lesson",
            showMainWindowAtLaunch: try container.decodeIfPresent(Bool.self, forKey: .showMainWindowAtLaunch) ?? true,
            showAnnotationOverlayAtLaunch: try container.decodeIfPresent(Bool.self, forKey: .showAnnotationOverlayAtLaunch) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(defaultProjectDirectory, forKey: .defaultProjectDirectory)
        try container.encode(defaultTemplateID, forKey: .defaultTemplateID)
        try container.encode(showMainWindowAtLaunch, forKey: .showMainWindowAtLaunch)
        try container.encode(showAnnotationOverlayAtLaunch, forKey: .showAnnotationOverlayAtLaunch)
    }

    public func normalized() -> GeneralPreferences {
        GeneralPreferences(
            appearance: appearance,
            defaultProjectDirectory: defaultProjectDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "~/Movies/DMLessonMeld"
                : defaultProjectDirectory,
            defaultTemplateID: defaultTemplateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "workshop-lesson"
                : defaultTemplateID,
            showMainWindowAtLaunch: showMainWindowAtLaunch,
            showAnnotationOverlayAtLaunch: showAnnotationOverlayAtLaunch
        )
    }
}

public enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    public var id: String { rawValue }
}

public struct CapturePreferences: Codable, Equatable, Sendable {
    public static let defaultQuickRecordDurationSeconds = 300

    public var quickRecordDurationSeconds: Int
    public var fps: Int
    public var includeCursor: Bool
    public var captureInteractionMetadata: Bool
    public var captureSystemAudio: Bool
    public var captureMicrophone: Bool
    public var microphoneDeviceID: String?
    public var captureWebcam: Bool
    public var cameraResolution: CameraResolution
    public var webcamFPS: Int
    public var webcamAspectRatio: WebcamAspectRatio
    public var webcamFrameShape: WebcamFrameShape
    public var webcamCornerRadius: Double
    public var webcamRelativeSize: Double
    public var webcamMirror: Bool
    public var webcamBorderEnabled: Bool
    public var webcamShadowEnabled: Bool
    public var showFloatingWebcamPreview: Bool
    public var countdownSeconds: Int
    public var rememberLastRegion: Bool
    public var hideRecorderControlsFromCapture: Bool
    public var showRecorderControlTooltips: Bool

    private enum CodingKeys: String, CodingKey {
        case quickRecordDurationSeconds
        case fps
        case includeCursor
        case captureInteractionMetadata
        case captureSystemAudio
        case captureMicrophone
        case microphoneDeviceID
        case captureWebcam
        case cameraResolution
        case webcamFPS
        case webcamAspectRatio
        case webcamFrameShape
        case webcamCornerRadius
        case webcamRelativeSize
        case webcamMirror
        case webcamBorderEnabled
        case webcamShadowEnabled
        case showFloatingWebcamPreview
        case countdownSeconds
        case rememberLastRegion
        case hideRecorderControlsFromCapture
        case showRecorderControlTooltips
    }

    public init(
        quickRecordDurationSeconds: Int = Self.defaultQuickRecordDurationSeconds,
        fps: Int = 60,
        includeCursor: Bool = true,
        captureInteractionMetadata: Bool = false,
        captureSystemAudio: Bool = false,
        captureMicrophone: Bool = true,
        microphoneDeviceID: String? = nil,
        captureWebcam: Bool = true,
        cameraResolution: CameraResolution = .p1080,
        webcamFPS: Int = 30,
        webcamAspectRatio: WebcamAspectRatio = .widescreen16x9,
        webcamFrameShape: WebcamFrameShape = .roundedRectangle,
        webcamCornerRadius: Double = 18,
        webcamRelativeSize: Double = 0.24,
        webcamMirror: Bool = false,
        webcamBorderEnabled: Bool = false,
        webcamShadowEnabled: Bool = true,
        showFloatingWebcamPreview: Bool = true,
        countdownSeconds: Int = 3,
        rememberLastRegion: Bool = true,
        hideRecorderControlsFromCapture: Bool = false,
        showRecorderControlTooltips: Bool = true
    ) {
        self.quickRecordDurationSeconds = quickRecordDurationSeconds
        self.fps = fps
        self.includeCursor = includeCursor
        self.captureInteractionMetadata = captureInteractionMetadata
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
        self.microphoneDeviceID = microphoneDeviceID
        self.captureWebcam = captureWebcam
        self.cameraResolution = cameraResolution
        self.webcamFPS = webcamFPS
        self.webcamAspectRatio = webcamAspectRatio
        self.webcamFrameShape = webcamFrameShape
        self.webcamCornerRadius = webcamCornerRadius
        self.webcamRelativeSize = webcamRelativeSize
        self.webcamMirror = webcamMirror
        self.webcamBorderEnabled = webcamBorderEnabled
        self.webcamShadowEnabled = webcamShadowEnabled
        self.showFloatingWebcamPreview = showFloatingWebcamPreview
        self.countdownSeconds = countdownSeconds
        self.rememberLastRegion = rememberLastRegion
        self.hideRecorderControlsFromCapture = hideRecorderControlsFromCapture
        self.showRecorderControlTooltips = showRecorderControlTooltips
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            quickRecordDurationSeconds: try container.decodeIfPresent(Int.self, forKey: .quickRecordDurationSeconds) ?? Self.defaultQuickRecordDurationSeconds,
            fps: try container.decodeIfPresent(Int.self, forKey: .fps) ?? 60,
            includeCursor: try container.decodeIfPresent(Bool.self, forKey: .includeCursor) ?? true,
            captureInteractionMetadata: try container.decodeIfPresent(Bool.self, forKey: .captureInteractionMetadata) ?? false,
            captureSystemAudio: try container.decodeIfPresent(Bool.self, forKey: .captureSystemAudio) ?? false,
            captureMicrophone: try container.decodeIfPresent(Bool.self, forKey: .captureMicrophone) ?? true,
            microphoneDeviceID: try container.decodeIfPresent(String.self, forKey: .microphoneDeviceID),
            captureWebcam: try container.decodeIfPresent(Bool.self, forKey: .captureWebcam) ?? true,
            cameraResolution: try container.decodeIfPresent(CameraResolution.self, forKey: .cameraResolution) ?? .p1080,
            webcamFPS: try container.decodeIfPresent(Int.self, forKey: .webcamFPS) ?? 30,
            webcamAspectRatio: try container.decodeIfPresent(WebcamAspectRatio.self, forKey: .webcamAspectRatio) ?? .widescreen16x9,
            webcamFrameShape: try container.decodeIfPresent(WebcamFrameShape.self, forKey: .webcamFrameShape) ?? .roundedRectangle,
            webcamCornerRadius: try container.decodeIfPresent(Double.self, forKey: .webcamCornerRadius) ?? 18,
            webcamRelativeSize: try container.decodeIfPresent(Double.self, forKey: .webcamRelativeSize) ?? 0.24,
            webcamMirror: try container.decodeIfPresent(Bool.self, forKey: .webcamMirror) ?? false,
            webcamBorderEnabled: try container.decodeIfPresent(Bool.self, forKey: .webcamBorderEnabled) ?? false,
            webcamShadowEnabled: try container.decodeIfPresent(Bool.self, forKey: .webcamShadowEnabled) ?? true,
            showFloatingWebcamPreview: try container.decodeIfPresent(Bool.self, forKey: .showFloatingWebcamPreview) ?? true,
            countdownSeconds: try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? 3,
            rememberLastRegion: try container.decodeIfPresent(Bool.self, forKey: .rememberLastRegion) ?? true,
            hideRecorderControlsFromCapture: try container.decodeIfPresent(Bool.self, forKey: .hideRecorderControlsFromCapture) ?? false,
            showRecorderControlTooltips: try container.decodeIfPresent(Bool.self, forKey: .showRecorderControlTooltips) ?? true
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quickRecordDurationSeconds, forKey: .quickRecordDurationSeconds)
        try container.encode(fps, forKey: .fps)
        try container.encode(includeCursor, forKey: .includeCursor)
        try container.encode(captureInteractionMetadata, forKey: .captureInteractionMetadata)
        try container.encode(captureSystemAudio, forKey: .captureSystemAudio)
        try container.encode(captureMicrophone, forKey: .captureMicrophone)
        try container.encodeIfPresent(microphoneDeviceID, forKey: .microphoneDeviceID)
        try container.encode(captureWebcam, forKey: .captureWebcam)
        try container.encode(cameraResolution, forKey: .cameraResolution)
        try container.encode(webcamFPS, forKey: .webcamFPS)
        try container.encode(webcamAspectRatio, forKey: .webcamAspectRatio)
        try container.encode(webcamFrameShape, forKey: .webcamFrameShape)
        try container.encode(webcamCornerRadius, forKey: .webcamCornerRadius)
        try container.encode(webcamRelativeSize, forKey: .webcamRelativeSize)
        try container.encode(webcamMirror, forKey: .webcamMirror)
        try container.encode(webcamBorderEnabled, forKey: .webcamBorderEnabled)
        try container.encode(webcamShadowEnabled, forKey: .webcamShadowEnabled)
        try container.encode(showFloatingWebcamPreview, forKey: .showFloatingWebcamPreview)
        try container.encode(countdownSeconds, forKey: .countdownSeconds)
        try container.encode(rememberLastRegion, forKey: .rememberLastRegion)
        try container.encode(hideRecorderControlsFromCapture, forKey: .hideRecorderControlsFromCapture)
        try container.encode(showRecorderControlTooltips, forKey: .showRecorderControlTooltips)
    }

    public func normalized() -> CapturePreferences {
        CapturePreferences(
            quickRecordDurationSeconds: min(max(quickRecordDurationSeconds, 1), 3_600),
            fps: [30, 60].contains(fps) ? fps : 60,
            includeCursor: includeCursor,
            captureInteractionMetadata: captureInteractionMetadata,
            captureSystemAudio: captureSystemAudio,
            captureMicrophone: captureMicrophone,
            microphoneDeviceID: Self.normalizedOptionalString(microphoneDeviceID),
            captureWebcam: captureWebcam,
            cameraResolution: cameraResolution,
            webcamFPS: Self.normalizedWebcamFPS(webcamFPS),
            webcamAspectRatio: webcamAspectRatio,
            webcamFrameShape: webcamFrameShape,
            webcamCornerRadius: min(max(webcamCornerRadius, 0), 64),
            webcamRelativeSize: min(max(webcamRelativeSize, 0.10), 0.40),
            webcamMirror: webcamMirror,
            webcamBorderEnabled: webcamBorderEnabled,
            webcamShadowEnabled: webcamShadowEnabled,
            showFloatingWebcamPreview: showFloatingWebcamPreview,
            countdownSeconds: min(max(countdownSeconds, 0), 10),
            rememberLastRegion: rememberLastRegion,
            hideRecorderControlsFromCapture: hideRecorderControlsFromCapture,
            showRecorderControlTooltips: showRecorderControlTooltips
        )
    }

    public static let supportedWebcamFPS = [24, 30, 40, 50, 60]

    public static func normalizedWebcamFPS(_ fps: Int) -> Int {
        supportedWebcamFPS.contains(fps) ? fps : 30
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum CameraResolution: String, Codable, CaseIterable, Identifiable, Sendable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p4K = "4K"

    public var id: String { rawValue }
}

public enum WebcamAspectRatio: String, Codable, CaseIterable, Identifiable, Sendable {
    case original
    case square1x1 = "1:1"
    case portrait2x3 = "2:3"
    case landscape3x2 = "3:2"
    case widescreen16x9 = "16:9"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .original:
            "Original"
        case .square1x1:
            "1:1"
        case .portrait2x3:
            "2:3"
        case .landscape3x2:
            "3:2"
        case .widescreen16x9:
            "16:9"
        }
    }
}

public enum WebcamFrameShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case roundedRectangle
    case square
    case circle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .roundedRectangle:
            "Rounded"
        case .square:
            "Square"
        case .circle:
            "Circle"
        }
    }
}

public struct AnnotationPreferences: Codable, Equatable, Sendable {
    public var defaultTool: AnnotationToolID
    public var defaultColorHex: String
    public var paletteHexColors: [String]
    public var lineWidth: Double
    public var toolbarVisibleOnOverlayOpen: Bool

    public init(
        defaultTool: AnnotationToolID = .pen,
        defaultColorHex: String = "#FFD733",
        paletteHexColors: [String] = ["#FFD733", "#22D3EE", "#22C55E", "#EF4444", "#A855F7", "#FFFFFF", "#050509", "#2F7CF6"],
        lineWidth: Double = 4,
        toolbarVisibleOnOverlayOpen: Bool = true
    ) {
        self.defaultTool = defaultTool
        self.defaultColorHex = defaultColorHex
        self.paletteHexColors = paletteHexColors
        self.lineWidth = lineWidth
        self.toolbarVisibleOnOverlayOpen = toolbarVisibleOnOverlayOpen
    }

    public func normalized() -> AnnotationPreferences {
        let colors = paletteHexColors
            .map(Self.normalizedHexColor)
            .filter { !$0.isEmpty }
        return AnnotationPreferences(
            defaultTool: defaultTool,
            defaultColorHex: Self.normalizedHexColor(defaultColorHex).isEmpty ? "#FFD733" : Self.normalizedHexColor(defaultColorHex),
            paletteHexColors: colors.isEmpty ? AnnotationPreferences().paletteHexColors : Array(colors.prefix(12)),
            lineWidth: min(max(lineWidth, 1), 24),
            toolbarVisibleOnOverlayOpen: toolbarVisibleOnOverlayOpen
        )
    }

    public static func normalizedHexColor(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let stripped = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard stripped.count == 6, stripped.allSatisfy({ $0.isHexDigit }) else {
            return ""
        }
        return "#\(stripped)"
    }
}

public enum AnnotationToolID: String, Codable, CaseIterable, Identifiable, Sendable {
    case pen
    case highlighter
    case line
    case rectangle
    case ellipse
    case arrow
    case text
    case laser
    case eraser
    case whiteboard
    case blackboard

    public var id: String { rawValue }
}

public struct ExportPreferences: Codable, Equatable, Sendable {
    public var defaultRenderQuality: RenderQualityID
    public var defaultFileType: RenderFileTypeID
    public var defaultLearnHousePackage: Bool
    public var createArchiveByDefault: Bool
    public var revealExportAfterCompletion: Bool

    public init(
        defaultRenderQuality: RenderQualityID = .highest,
        defaultFileType: RenderFileTypeID = .mp4,
        defaultLearnHousePackage: Bool = true,
        createArchiveByDefault: Bool = true,
        revealExportAfterCompletion: Bool = false
    ) {
        self.defaultRenderQuality = defaultRenderQuality
        self.defaultFileType = defaultFileType
        self.defaultLearnHousePackage = defaultLearnHousePackage
        self.createArchiveByDefault = createArchiveByDefault
        self.revealExportAfterCompletion = revealExportAfterCompletion
    }

    public func normalized() -> ExportPreferences { self }
}

public enum RenderQualityID: String, Codable, CaseIterable, Identifiable, Sendable {
    case medium
    case highest

    public var id: String { rawValue }
}

public enum RenderFileTypeID: String, Codable, CaseIterable, Identifiable, Sendable {
    case mp4
    case mov

    public var id: String { rawValue }
}

public struct IntegrationPreferences: Codable, Equatable, Sendable {
    public var learnHouseEnabled: Bool
    public var roadmapLMSConnectors: [String]
    public var agentManifestsEnabled: Bool
    public var preferredAgentTargets: [AgentTarget]

    public init(
        learnHouseEnabled: Bool = true,
        roadmapLMSConnectors: [String] = ["Canvas", "Moodle", "Google Classroom", "YouTube", "Vimeo"],
        agentManifestsEnabled: Bool = true,
        preferredAgentTargets: [AgentTarget] = AgentTarget.allCases
    ) {
        self.learnHouseEnabled = learnHouseEnabled
        self.roadmapLMSConnectors = roadmapLMSConnectors
        self.agentManifestsEnabled = agentManifestsEnabled
        self.preferredAgentTargets = preferredAgentTargets
    }
}

public enum AgentTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case openClaw = "OpenClaw"
    case codex = "Codex"
    case veritasKanban = "Veritas Kanban"

    public var id: String { rawValue }
}

public struct PrivacyPreferences: Codable, Equatable, Sendable {
    public var localOnlyMode: Bool
    public var includeMediaPathsInAgentManifests: Bool
    public var includeTranscriptReferencesInAgentManifests: Bool
    public var allowGitBackupsForSettings: Bool
    public var configBackupRootPath: String
    public var excludeMediaFromBackups: Bool

    public init(
        localOnlyMode: Bool = true,
        includeMediaPathsInAgentManifests: Bool = false,
        includeTranscriptReferencesInAgentManifests: Bool = false,
        allowGitBackupsForSettings: Bool = true,
        configBackupRootPath: String = "~/Library/Application Support/DMLessonMeld/Config",
        excludeMediaFromBackups: Bool = true
    ) {
        self.localOnlyMode = localOnlyMode
        self.includeMediaPathsInAgentManifests = includeMediaPathsInAgentManifests
        self.includeTranscriptReferencesInAgentManifests = includeTranscriptReferencesInAgentManifests
        self.allowGitBackupsForSettings = allowGitBackupsForSettings
        self.configBackupRootPath = configBackupRootPath
        self.excludeMediaFromBackups = excludeMediaFromBackups
    }
}

public enum LessonMeldShortcutAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case showSettings
    case showOnboarding
    case openAnnotationOverlay
    case quickRecord
    case stopRecording
    case quickColor1
    case quickColor2
    case quickColor3
    case quickColor4

    public var id: String { rawValue }

    public static let defaultShortcuts: [LessonMeldShortcutAction: String] = [
        .showSettings: "command+,",
        .showOnboarding: "option+command+p",
        .openAnnotationOverlay: "option+command+a",
        .quickRecord: "option+command+r",
        .stopRecording: "escape",
        .quickColor1: "command+1",
        .quickColor2: "command+2",
        .quickColor3: "command+3",
        .quickColor4: "command+4"
    ]
}
