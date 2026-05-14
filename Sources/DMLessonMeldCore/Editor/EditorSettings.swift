import CoreGraphics
import Foundation

public struct EditorSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var canvas: EditorCanvasSettings
    public var zoom: EditorZoomSettings?
    public var cursor: EditorCursorSettings?
    public var camera: EditorCameraSettings?
    public var audio: EditorAudioSettings?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        canvas: EditorCanvasSettings = EditorCanvasSettings(),
        zoom: EditorZoomSettings? = EditorZoomSettings(),
        cursor: EditorCursorSettings? = EditorCursorSettings(),
        camera: EditorCameraSettings? = EditorCameraSettings(),
        audio: EditorAudioSettings? = EditorAudioSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.canvas = canvas
        self.zoom = zoom
        self.cursor = cursor
        self.camera = camera
        self.audio = audio
    }
}

public enum EditorSettingsFile {
    public static let defaultFileName = "editor-settings.json"

    public static func url(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(defaultFileName)
    }

    public static func exists(in projectURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(in: projectURL).path)
    }

    public static func load(fromProject projectURL: URL) throws -> EditorSettings {
        let data = try Data(contentsOf: url(in: projectURL))
        return try DMLessonJSON.decoder().decode(EditorSettings.self, from: data)
    }

    public static func loadIfPresent(fromProject projectURL: URL) throws -> EditorSettings? {
        exists(in: projectURL) ? try load(fromProject: projectURL) : nil
    }

    public static func save(_ settings: EditorSettings, toProject projectURL: URL) throws {
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let data = try DMLessonJSON.encoder().encode(settings)
        try data.write(to: url(in: projectURL), options: [.atomic])
    }
}

public struct EditorCanvasSettings: Codable, Equatable, Sendable {
    public var aspectRatio: EditorCanvasAspectRatio
    public var background: EditorCanvasBackground
    public var paddingRatio: Double
    public var insetRatio: Double
    public var cornerRadiusRatio: Double
    public var shadow: EditorCanvasShadow
    public var cropRect: NormalizedEditRect?
    public var customSize: EditorCanvasCustomSize?

    public init(
        aspectRatio: EditorCanvasAspectRatio = .source,
        background: EditorCanvasBackground = EditorCanvasBackground(),
        paddingRatio: Double = 0,
        insetRatio: Double = 0,
        cornerRadiusRatio: Double = 0,
        shadow: EditorCanvasShadow = EditorCanvasShadow(),
        cropRect: NormalizedEditRect? = nil,
        customSize: EditorCanvasCustomSize? = nil
    ) {
        self.aspectRatio = aspectRatio
        self.background = background
        self.paddingRatio = Self.clamped(paddingRatio, min: 0, max: 0.45)
        self.insetRatio = Self.clamped(insetRatio, min: 0, max: 0.45)
        self.cornerRadiusRatio = Self.clamped(cornerRadiusRatio, min: 0, max: 0.25)
        self.shadow = shadow
        self.cropRect = cropRect
        self.customSize = customSize
    }

    public var isDefault: Bool {
        self == EditorCanvasSettings()
    }

    public func renderGeometry(sourceSize: CGSize) -> EditorCanvasRenderGeometry {
        let safeSource = sourceSize.width > 0 && sourceSize.height > 0
            ? sourceSize
            : CGSize(width: 1920, height: 1080)
        let crop = resolvedCropRect(sourceSize: safeSource)
        let renderSize = aspectRatio.resolvedRenderSize(sourceSize: safeSource, customSize: customSize)
        let outerInset = min(renderSize.width, renderSize.height) * CGFloat(insetRatio)
        let padding = min(renderSize.width, renderSize.height) * CGFloat(paddingRatio)
        let available = CGRect(origin: .zero, size: renderSize)
            .insetBy(dx: outerInset + padding, dy: outerInset + padding)
        let safeAvailable = available.width > 1 && available.height > 1
            ? available
            : CGRect(origin: .zero, size: renderSize).insetBy(dx: outerInset, dy: outerInset)
        let scale = min(safeAvailable.width / crop.width, safeAvailable.height / crop.height)
        let videoSize = CGSize(width: crop.width * scale, height: crop.height * scale)
        let frame = CGRect(
            x: safeAvailable.midX - videoSize.width / 2,
            y: safeAvailable.midY - videoSize.height / 2,
            width: videoSize.width,
            height: videoSize.height
        )
        let cornerRadius = min(renderSize.width, renderSize.height) * CGFloat(cornerRadiusRatio)
        return EditorCanvasRenderGeometry(
            renderSize: renderSize,
            sourceCropRect: crop,
            videoFrame: frame,
            cornerRadius: min(cornerRadius, min(frame.width, frame.height) / 2)
        )
    }

    private func resolvedCropRect(sourceSize: CGSize) -> CGRect {
        guard let cropRect else {
            return CGRect(origin: .zero, size: sourceSize)
        }
        let width = max(0.01, min(1, cropRect.width))
        let height = max(0.01, min(1, cropRect.height))
        let x = max(0, min(1 - width, cropRect.x))
        let y = max(0, min(1 - height, cropRect.y))
        return CGRect(
            x: CGFloat(x) * sourceSize.width,
            y: CGFloat(y) * sourceSize.height,
            width: CGFloat(width) * sourceSize.width,
            height: CGFloat(height) * sourceSize.height
        )
    }

    private static func clamped(_ value: Double, min lowerBound: Double, max upperBound: Double) -> Double {
        min(upperBound, max(lowerBound, value.isFinite ? value : lowerBound))
    }
}

public struct EditorCanvasRenderGeometry: Equatable, Sendable {
    public var renderSize: CGSize
    public var sourceCropRect: CGRect
    public var videoFrame: CGRect
    public var cornerRadius: CGFloat

    public init(renderSize: CGSize, sourceCropRect: CGRect, videoFrame: CGRect, cornerRadius: CGFloat) {
        self.renderSize = renderSize
        self.sourceCropRect = sourceCropRect
        self.videoFrame = videoFrame
        self.cornerRadius = cornerRadius
    }
}

public enum EditorCanvasAspectRatio: String, Codable, CaseIterable, Identifiable, Sendable {
    case source
    case custom
    case square1x1 = "1:1"
    case portrait4x5 = "4:5"
    case portrait9x16 = "9:16"
    case standard4x3 = "4:3"
    case widescreen16x9 = "16:9"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .source: "Source"
        case .custom: "Custom"
        case .square1x1: "1:1"
        case .portrait4x5: "4:5"
        case .portrait9x16: "9:16"
        case .standard4x3: "4:3"
        case .widescreen16x9: "16:9"
        }
    }

    public func resolvedRenderSize(
        sourceSize: CGSize,
        customSize: EditorCanvasCustomSize? = nil
    ) -> CGSize {
        let safeWidth = max(sourceSize.width, 16)
        let safeHeight = max(sourceSize.height, 16)
        let width = max(safeWidth, 640)
        let height: CGFloat
        switch self {
        case .source:
            return CGSize(width: evenDimension(safeWidth), height: evenDimension(safeHeight))
        case .custom:
            guard let customSize else {
                return CGSize(width: evenDimension(safeWidth), height: evenDimension(safeHeight))
            }
            return customSize.cgSize
        case .square1x1:
            height = width
        case .portrait4x5:
            height = width * 5 / 4
        case .portrait9x16:
            height = width * 16 / 9
        case .standard4x3:
            height = width * 3 / 4
        case .widescreen16x9:
            height = width * 9 / 16
        }
        return CGSize(width: evenDimension(width), height: evenDimension(height))
    }

    private func evenDimension(_ value: CGFloat) -> CGFloat {
        let rounded = Int(value.rounded())
        return CGFloat(rounded.isMultiple(of: 2) ? rounded : rounded + 1)
    }
}

public struct EditorCanvasCustomSize: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = Self.evenClamped(width)
        self.height = Self.evenClamped(height)
    }

    public var cgSize: CGSize {
        CGSize(width: width, height: height)
    }

    private static func evenClamped(_ value: Int) -> Int {
        let clamped = min(7680, max(16, value))
        return clamped.isMultiple(of: 2) ? clamped : clamped + 1
    }
}

public struct EditorCanvasBackground: Codable, Equatable, Sendable {
    public var style: EditorCanvasBackgroundStyle
    public var primaryColor: RGBAColor
    public var secondaryColor: RGBAColor
    public var imagePath: String?

    public init(
        style: EditorCanvasBackgroundStyle = .none,
        primaryColor: RGBAColor = .black,
        secondaryColor: RGBAColor = .purple,
        imagePath: String? = nil
    ) {
        self.style = style
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.imagePath = imagePath
    }
}

public enum EditorCanvasBackgroundStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case solid
    case gradient
    case image

    public var id: String { rawValue }
}

public struct EditorCanvasShadow: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var opacity: Double
    public var radiusRatio: Double
    public var offsetYRatio: Double

    public init(
        isEnabled: Bool = false,
        opacity: Double = 0.34,
        radiusRatio: Double = 0.02,
        offsetYRatio: Double = -0.008
    ) {
        self.isEnabled = isEnabled
        self.opacity = min(1, max(0, opacity.isFinite ? opacity : 0.34))
        self.radiusRatio = min(0.12, max(0, radiusRatio.isFinite ? radiusRatio : 0.02))
        self.offsetYRatio = min(0.12, max(-0.12, offsetYRatio.isFinite ? offsetYRatio : -0.008))
    }
}

public struct EditorZoomSettings: Codable, Equatable, Sendable {
    public var automaticClickZoomsEnabled: Bool

    public init(automaticClickZoomsEnabled: Bool = true) {
        self.automaticClickZoomsEnabled = automaticClickZoomsEnabled
    }
}

public struct EditorAudioSettings: Codable, Equatable, Sendable {
    public var screenAudio: EditorAudioTrackSettings
    public var microphoneAudio: EditorAudioTrackSettings
    public var systemAudio: EditorAudioTrackSettings
    public var backgroundMusic: EditorBackgroundMusicSettings?
    public var volumeRegions: [EditorAudioVolumeRegion]

    public init(
        screenAudio: EditorAudioTrackSettings = EditorAudioTrackSettings(),
        microphoneAudio: EditorAudioTrackSettings = EditorAudioTrackSettings(),
        systemAudio: EditorAudioTrackSettings = EditorAudioTrackSettings(),
        backgroundMusic: EditorBackgroundMusicSettings? = nil,
        volumeRegions: [EditorAudioVolumeRegion] = []
    ) {
        self.screenAudio = screenAudio
        self.microphoneAudio = microphoneAudio
        self.systemAudio = systemAudio
        self.backgroundMusic = backgroundMusic
        self.volumeRegions = volumeRegions
    }

    public var isDefault: Bool {
        self == EditorAudioSettings()
    }

    public var enabledVolumeRegions: [EditorAudioVolumeRegion] {
        volumeRegions.filter(\.isEnabled).sorted { $0.range.startSeconds < $1.range.startSeconds }
    }

    public func trackSettings(for role: EditorAudioTrackRole) -> EditorAudioTrackSettings {
        switch role {
        case .screen:
            screenAudio
        case .microphone:
            microphoneAudio
        case .system:
            systemAudio
        case .backgroundMusic:
            EditorAudioTrackSettings(gain: backgroundMusic?.gain ?? 1)
        case .all:
            EditorAudioTrackSettings()
        }
    }

    public func isSoloMuted(role: EditorAudioTrackRole) -> Bool {
        let soloed = [
            (EditorAudioTrackRole.screen, screenAudio),
            (.microphone, microphoneAudio),
            (.system, systemAudio)
        ].filter { $0.1.isSoloed }
        guard !soloed.isEmpty else { return false }
        return !soloed.contains { $0.0 == role }
    }
}

public struct EditorAudioTrackSettings: Codable, Equatable, Sendable {
    public var gain: Double
    public var isMuted: Bool
    public var isSoloed: Bool

    public init(gain: Double = 1, isMuted: Bool = false, isSoloed: Bool = false) {
        self.gain = min(2, max(0, gain.isFinite ? gain : 1))
        self.isMuted = isMuted
        self.isSoloed = isSoloed
    }
}

public enum EditorAudioTrackRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case screen
    case microphone
    case system
    case backgroundMusic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            "All Tracks"
        case .screen:
            "Screen"
        case .microphone:
            "Microphone"
        case .system:
            "System"
        case .backgroundMusic:
            "Music"
        }
    }
}

public struct EditorAudioVolumeRegion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var track: EditorAudioTrackRole
    public var range: EditTimeRange
    public var gain: Double
    public var fadeInSeconds: Double
    public var fadeOutSeconds: Double
    public var isEnabled: Bool

    public init(
        id: String,
        track: EditorAudioTrackRole = .all,
        range: EditTimeRange,
        gain: Double = 0.6,
        fadeInSeconds: Double = 0.12,
        fadeOutSeconds: Double = 0.12,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.track = track
        self.range = range
        self.gain = min(2, max(0, gain.isFinite ? gain : 0.6))
        self.fadeInSeconds = min(10, max(0, fadeInSeconds.isFinite ? fadeInSeconds : 0.12))
        self.fadeOutSeconds = min(10, max(0, fadeOutSeconds.isFinite ? fadeOutSeconds : 0.12))
        self.isEnabled = isEnabled
    }
}

public struct EditorBackgroundMusicSettings: Codable, Equatable, Sendable {
    public var relativePath: String
    public var startSeconds: Double
    public var sourceStartSeconds: Double
    public var durationSeconds: Double?
    public var gain: Double
    public var loop: Bool
    public var duckUnderVoice: Bool
    public var duckedGain: Double
    public var fadeInSeconds: Double
    public var fadeOutSeconds: Double

    public init(
        relativePath: String,
        startSeconds: Double = 0,
        sourceStartSeconds: Double = 0,
        durationSeconds: Double? = nil,
        gain: Double = 0.28,
        loop: Bool = true,
        duckUnderVoice: Bool = true,
        duckedGain: Double = 0.12,
        fadeInSeconds: Double = 0.5,
        fadeOutSeconds: Double = 0.5
    ) {
        self.relativePath = relativePath
        self.startSeconds = max(0, startSeconds.isFinite ? startSeconds : 0)
        self.sourceStartSeconds = max(0, sourceStartSeconds.isFinite ? sourceStartSeconds : 0)
        if let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 {
            self.durationSeconds = durationSeconds
        } else {
            self.durationSeconds = nil
        }
        self.gain = min(2, max(0, gain.isFinite ? gain : 0.28))
        self.loop = loop
        self.duckUnderVoice = duckUnderVoice
        self.duckedGain = min(2, max(0, duckedGain.isFinite ? duckedGain : 0.12))
        self.fadeInSeconds = min(10, max(0, fadeInSeconds.isFinite ? fadeInSeconds : 0.5))
        self.fadeOutSeconds = min(10, max(0, fadeOutSeconds.isFinite ? fadeOutSeconds : 0.5))
    }
}

public struct EditorCameraSettings: Codable, Equatable, Sendable {
    public var defaultPlacement: PictureInPicturePlacement
    public var layoutRegions: [CameraLayoutRegion]
    public var reactions: [CameraReaction]

    public init(
        defaultPlacement: PictureInPicturePlacement = .defaultBottomTrailing,
        layoutRegions: [CameraLayoutRegion] = [],
        reactions: [CameraReaction] = []
    ) {
        self.defaultPlacement = defaultPlacement
        self.layoutRegions = layoutRegions
        self.reactions = reactions
    }

    public var enabledLayoutRegions: [CameraLayoutRegion] {
        layoutRegions.filter(\.isEnabled).sorted { $0.range.startSeconds < $1.range.startSeconds }
    }

    public var enabledReactions: [CameraReaction] {
        reactions.filter(\.isEnabled).sorted { $0.range.startSeconds < $1.range.startSeconds }
    }
}

public struct CameraLayoutRegion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var range: EditTimeRange
    public var preset: CameraLayoutPreset
    public var placement: PictureInPicturePlacement?
    public var animation: CameraLayoutAnimation
    public var transitionSeconds: Double
    public var isEnabled: Bool

    public init(
        id: String,
        range: EditTimeRange,
        preset: CameraLayoutPreset,
        placement: PictureInPicturePlacement? = nil,
        animation: CameraLayoutAnimation = .fade,
        transitionSeconds: Double = 0.18,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.range = range
        self.preset = preset
        self.placement = placement
        self.animation = animation
        self.transitionSeconds = min(2, max(0, transitionSeconds.isFinite ? transitionSeconds : 0.18))
        self.isEnabled = isEnabled
    }

    public func resolvedPlacement(default defaultPlacement: PictureInPicturePlacement) -> PictureInPicturePlacement {
        placement ?? preset.defaultPlacement(fallback: defaultPlacement)
    }
}

public enum CameraLayoutPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case cornerPip
    case sideBySide
    case presenterFocus
    case hidden
    case fullCamera
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cornerPip:
            "Corner PiP"
        case .sideBySide:
            "Side by Side"
        case .presenterFocus:
            "Presenter Focus"
        case .hidden:
            "Hidden"
        case .fullCamera:
            "Full Camera"
        case .custom:
            "Custom"
        }
    }

    public func defaultPlacement(fallback: PictureInPicturePlacement) -> PictureInPicturePlacement {
        switch self {
        case .cornerPip:
            .defaultBottomTrailing
        case .sideBySide:
            PictureInPicturePlacement(
                corner: .bottomTrailing,
                widthRatio: 0.46,
                marginRatio: 0.025,
                aspectRatio: .widescreen16x9,
                frameShape: .roundedRectangle,
                cornerRadius: 18,
                borderEnabled: true,
                shadowEnabled: true
            )
        case .presenterFocus:
            PictureInPicturePlacement(
                corner: .bottomLeading,
                widthRatio: 0.34,
                marginRatio: 0.035,
                aspectRatio: .square1x1,
                frameShape: .circle,
                borderEnabled: true,
                shadowEnabled: true
            )
        case .hidden:
            fallback
        case .fullCamera:
            PictureInPicturePlacement(
                corner: .bottomLeading,
                widthRatio: 1,
                marginRatio: 0,
                aspectRatio: .widescreen16x9,
                frameShape: .square,
                cornerRadius: 0,
                isMirrored: fallback.isMirrored,
                borderEnabled: false,
                shadowEnabled: false
            )
        case .custom:
            fallback
        }
    }
}

public enum CameraLayoutAnimation: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case fade

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none:
            "None"
        case .fade:
            "Fade"
        }
    }
}

public struct CameraReaction: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var range: EditTimeRange
    public var text: String
    public var frame: NormalizedEditRect
    public var isEnabled: Bool

    public init(
        id: String,
        range: EditTimeRange,
        text: String,
        frame: NormalizedEditRect = NormalizedEditRect(x: 0.74, y: 0.18, width: 0.12, height: 0.12),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.range = range
        self.text = text
        self.frame = frame
        self.isEnabled = isEnabled
    }
}

public struct EditorCursorSettings: Codable, Equatable, Sendable {
    public var pointerStyle: EditorCursorPointerStyle
    public var pointerVisible: Bool
    public var smoothMovement: Bool
    public var pointerScale: Double
    public var pointerFillColor: RGBAColor
    public var pointerStrokeColor: RGBAColor
    public var hiddenRanges: [EditTimeRange]
    public var clickEffects: EditorClickEffectSettings
    public var keyboardOverlay: EditorKeyboardOverlaySettings

    public init(
        pointerStyle: EditorCursorPointerStyle = .macOS,
        pointerVisible: Bool = true,
        smoothMovement: Bool = true,
        pointerScale: Double = 1,
        pointerFillColor: RGBAColor = .white,
        pointerStrokeColor: RGBAColor = .black,
        hiddenRanges: [EditTimeRange] = [],
        clickEffects: EditorClickEffectSettings = EditorClickEffectSettings(),
        keyboardOverlay: EditorKeyboardOverlaySettings = EditorKeyboardOverlaySettings()
    ) {
        self.pointerStyle = pointerStyle
        self.pointerVisible = pointerVisible
        self.smoothMovement = smoothMovement
        self.pointerScale = min(3, max(0.25, pointerScale.isFinite ? pointerScale : 1))
        self.pointerFillColor = pointerFillColor
        self.pointerStrokeColor = pointerStrokeColor
        self.hiddenRanges = hiddenRanges
        self.clickEffects = clickEffects
        self.keyboardOverlay = keyboardOverlay
    }

    private enum CodingKeys: String, CodingKey {
        case pointerStyle
        case pointerVisible
        case smoothMovement
        case pointerScale
        case pointerFillColor
        case pointerStrokeColor
        case hiddenRanges
        case clickEffects
        case keyboardOverlay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            pointerStyle: try container.decodeIfPresent(EditorCursorPointerStyle.self, forKey: .pointerStyle) ?? .macOS,
            pointerVisible: try container.decodeIfPresent(Bool.self, forKey: .pointerVisible) ?? true,
            smoothMovement: try container.decodeIfPresent(Bool.self, forKey: .smoothMovement) ?? true,
            pointerScale: try container.decodeIfPresent(Double.self, forKey: .pointerScale) ?? 1,
            pointerFillColor: try container.decodeIfPresent(RGBAColor.self, forKey: .pointerFillColor) ?? .white,
            pointerStrokeColor: try container.decodeIfPresent(RGBAColor.self, forKey: .pointerStrokeColor) ?? .black,
            hiddenRanges: try container.decodeIfPresent([EditTimeRange].self, forKey: .hiddenRanges) ?? [],
            clickEffects: try container.decodeIfPresent(EditorClickEffectSettings.self, forKey: .clickEffects) ?? EditorClickEffectSettings(),
            keyboardOverlay: try container.decodeIfPresent(EditorKeyboardOverlaySettings.self, forKey: .keyboardOverlay) ?? EditorKeyboardOverlaySettings()
        )
    }
}

public enum EditorCursorPointerStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case macOS
    case touchDot

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .macOS:
            "macOS Pointer"
        case .touchDot:
            "Touch Dot"
        }
    }
}

public struct EditorClickEffectSettings: Codable, Equatable, Sendable {
    public var rippleVisible: Bool
    public var color: RGBAColor
    public var scale: Double
    public var opacity: Double
    public var durationSeconds: Double
    public var soundEnabled: Bool
    public var soundVolume: Double

    public init(
        rippleVisible: Bool = true,
        color: RGBAColor = .yellow,
        scale: Double = 1,
        opacity: Double = 0.85,
        durationSeconds: Double = 0.42,
        soundEnabled: Bool = false,
        soundVolume: Double = 0.45
    ) {
        self.rippleVisible = rippleVisible
        self.color = color
        self.scale = min(4, max(0.25, scale.isFinite ? scale : 1))
        self.opacity = min(1, max(0, opacity.isFinite ? opacity : 0.85))
        self.durationSeconds = min(2, max(0.05, durationSeconds.isFinite ? durationSeconds : 0.42))
        self.soundEnabled = soundEnabled
        self.soundVolume = min(1, max(0, soundVolume.isFinite ? soundVolume : 0.45))
    }

    private enum CodingKeys: String, CodingKey {
        case rippleVisible
        case color
        case scale
        case opacity
        case durationSeconds
        case soundEnabled
        case soundVolume
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rippleVisible: try container.decodeIfPresent(Bool.self, forKey: .rippleVisible) ?? true,
            color: try container.decodeIfPresent(RGBAColor.self, forKey: .color) ?? .yellow,
            scale: try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.85,
            durationSeconds: try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0.42,
            soundEnabled: try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false,
            soundVolume: try container.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.45
        )
    }
}

public struct EditorKeyboardOverlaySettings: Codable, Equatable, Sendable {
    public var isVisible: Bool
    public var opacity: Double

    public init(isVisible: Bool = true, opacity: Double = 0.9) {
        self.isVisible = isVisible
        self.opacity = min(1, max(0, opacity.isFinite ? opacity : 0.9))
    }
}
