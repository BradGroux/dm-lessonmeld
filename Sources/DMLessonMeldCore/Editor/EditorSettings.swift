import CoreGraphics
import Foundation

public struct EditorSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var canvas: EditorCanvasSettings

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        canvas: EditorCanvasSettings = EditorCanvasSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.canvas = canvas
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
