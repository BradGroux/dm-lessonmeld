import CoreGraphics
import Foundation

public struct OverlayStore: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var isVisible: Bool
    public var overlays: [OverlayItem]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        isVisible: Bool = true,
        overlays: [OverlayItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.isVisible = isVisible
        self.overlays = overlays
    }
}

public struct OverlayItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: OverlayKind
    public var timeRange: EditTimeRange
    public var frame: NormalizedEditRect
    public var rotationDegrees: Double
    public var opacity: Double
    public var zIndex: Int
    public var style: OverlayStyle
    public var animation: OverlayAnimation
    public var isEnabled: Bool

    public init(
        id: String,
        kind: OverlayKind,
        timeRange: EditTimeRange,
        frame: NormalizedEditRect = NormalizedEditRect(x: 0.25, y: 0.25, width: 0.5, height: 0.18),
        rotationDegrees: Double = 0,
        opacity: Double = 1,
        zIndex: Int = 0,
        style: OverlayStyle = OverlayStyle(),
        animation: OverlayAnimation = OverlayAnimation(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.timeRange = timeRange
        self.frame = frame
        self.rotationDegrees = rotationDegrees.isFinite ? rotationDegrees : 0
        self.opacity = min(1, max(0, opacity.isFinite ? opacity : 1))
        self.zIndex = zIndex
        self.style = style
        self.animation = animation
        self.isEnabled = isEnabled
    }
}

public enum OverlayKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case rectangle
    case ellipse
    case line
    case arrow
    case callout
    case image
    case highlight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .text:
            "Text"
        case .rectangle:
            "Rectangle"
        case .ellipse:
            "Ellipse"
        case .line:
            "Line"
        case .arrow:
            "Arrow"
        case .callout:
            "Callout"
        case .image:
            "Image"
        case .highlight:
            "Highlight"
        }
    }
}

public enum OverlayHighlightMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case dim
    case blur
    case spotlight
    case outline

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dim:
            "Dim"
        case .blur:
            "Blur"
        case .spotlight:
            "Spotlight"
        case .outline:
            "Outline"
        }
    }
}

public enum OverlayHighlightShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case rectangle
    case roundedRectangle
    case ellipse

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rectangle:
            "Rectangle"
        case .roundedRectangle:
            "Rounded"
        case .ellipse:
            "Ellipse"
        }
    }
}

public struct OverlayStyle: Codable, Equatable, Sendable {
    public var text: String
    public var fontSize: Double
    public var textColor: RGBAColor
    public var fillColor: RGBAColor?
    public var strokeColor: RGBAColor
    public var lineWidth: Double
    public var backgroundColor: RGBAColor?
    public var cornerRadius: Double
    public var shadowEnabled: Bool
    public var imagePath: String?
    public var highlightMode: OverlayHighlightMode?
    public var highlightShape: OverlayHighlightShape?
    public var blurRadius: Double?
    public var featherRadius: Double?

    public init(
        text: String = "Overlay",
        fontSize: Double = 34,
        textColor: RGBAColor = .white,
        fillColor: RGBAColor? = nil,
        strokeColor: RGBAColor = .yellow,
        lineWidth: Double = 4,
        backgroundColor: RGBAColor? = RGBAColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 0.68),
        cornerRadius: Double = 12,
        shadowEnabled: Bool = true,
        imagePath: String? = nil,
        highlightMode: OverlayHighlightMode? = nil,
        highlightShape: OverlayHighlightShape? = nil,
        blurRadius: Double? = nil,
        featherRadius: Double? = nil
    ) {
        self.text = text
        self.fontSize = min(160, max(8, fontSize.isFinite ? fontSize : 34))
        self.textColor = textColor
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.lineWidth = min(24, max(0, lineWidth.isFinite ? lineWidth : 4))
        self.backgroundColor = backgroundColor
        self.cornerRadius = min(96, max(0, cornerRadius.isFinite ? cornerRadius : 12))
        self.shadowEnabled = shadowEnabled
        self.imagePath = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.highlightMode = highlightMode
        self.highlightShape = highlightShape
        self.blurRadius = blurRadius.map { min(80, max(0, $0.isFinite ? $0 : 0)) }
        self.featherRadius = featherRadius.map { min(80, max(0, $0.isFinite ? $0 : 0)) }
    }
}

public enum OverlayAnimationPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case slideUp
    case scaleIn

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none:
            "None"
        case .slideUp:
            "Slide Up"
        case .scaleIn:
            "Scale In"
        }
    }
}

public struct OverlayAnimation: Codable, Equatable, Sendable {
    public var fadeInSeconds: Double
    public var fadeOutSeconds: Double
    public var preset: OverlayAnimationPreset

    public init(
        fadeInSeconds: Double = 0.18,
        fadeOutSeconds: Double = 0.18,
        preset: OverlayAnimationPreset = .none
    ) {
        self.fadeInSeconds = min(5, max(0, fadeInSeconds.isFinite ? fadeInSeconds : 0.18))
        self.fadeOutSeconds = min(5, max(0, fadeOutSeconds.isFinite ? fadeOutSeconds : 0.18))
        self.preset = preset
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
