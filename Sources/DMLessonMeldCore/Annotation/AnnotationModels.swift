import CoreGraphics
import Foundation

public enum AnnotationTool: String, CaseIterable, Codable, Equatable, Hashable, Identifiable, Sendable {
    case pen
    case highlighter
    case line
    case rectangle
    case ellipse
    case arrow
    case text
    case laser
    case whiteboard
    case blackboard

    public var id: String { rawValue }
}

public enum AnnotationKind: String, CaseIterable, Codable, Equatable, Hashable, Identifiable, Sendable {
    case pen
    case highlighter
    case line
    case rectangle
    case ellipse
    case arrow
    case text
    case laser
    case whiteboard
    case blackboard

    public var id: String { rawValue }
}

public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = RGBAColor(red: 0.95, green: 0.18, blue: 0.24)
    public static let amber = RGBAColor(red: 0.98, green: 0.65, blue: 0.14)
    public static let yellow = RGBAColor(red: 1.0, green: 0.86, blue: 0.2)
    public static let green = RGBAColor(red: 0.18, green: 0.78, blue: 0.39)
    public static let cyan = RGBAColor(red: 0.12, green: 0.72, blue: 0.88)
    public static let blue = RGBAColor(red: 0.16, green: 0.45, blue: 0.96)
    public static let purple = RGBAColor(red: 0.55, green: 0.36, blue: 0.95)
    public static let pink = RGBAColor(red: 0.95, green: 0.28, blue: 0.65)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0.02, green: 0.02, blue: 0.025)
    public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
}

public enum AnnotationTextWeight: String, CaseIterable, Codable, Equatable, Hashable, Identifiable, Sendable {
    case regular
    case medium
    case semibold
    case bold

    public var id: String { rawValue }
}

public struct AnnotationTextStyle: Codable, Equatable, Hashable, Sendable {
    public var fontName: String?
    public var fontSize: CGFloat
    public var weight: AnnotationTextWeight

    public init(fontName: String? = nil, fontSize: CGFloat = 24, weight: AnnotationTextWeight = .semibold) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.weight = weight
    }
}

public struct NormalizedAnnotationPoint: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var isValid: Bool {
        x.isFinite && y.isFinite && x >= 0 && x <= 1 && y >= 0 && y <= 1
    }

    public func canvasPoint(in size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(x) * size.width,
            y: (1 - CGFloat(y)) * size.height
        )
    }
}

public enum AnnotationCoordinateSpace: String, Codable, Equatable, Hashable, Sendable {
    case legacyCanvasPoints
    case normalizedCapture
}

public struct AnnotationTimeRange: Codable, Equatable, Hashable, Sendable {
    public var startSeconds: Double
    public var endSeconds: Double

    public init(startSeconds: Double, endSeconds: Double) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    public var isValid: Bool {
        startSeconds.isFinite && endSeconds.isFinite && startSeconds >= 0 && endSeconds > startSeconds
    }

    public func contains(_ seconds: Double) -> Bool {
        isValid && seconds >= startSeconds && seconds < endSeconds
    }
}

public struct AnnotationItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayID: UInt32
    public var kind: AnnotationKind
    public var points: [CGPoint]
    public var normalizedPoints: [NormalizedAnnotationPoint]?
    public var coordinateSpace: AnnotationCoordinateSpace
    public var timeRange: AnnotationTimeRange?
    public var color: RGBAColor
    public var fillColor: RGBAColor?
    public var lineWidth: CGFloat
    public var opacity: Double
    public var text: String?
    public var textStyle: AnnotationTextStyle?
    public var createdAt: Date
    public var updatedAt: Date
    public var isVisible: Bool
    public var isLocked: Bool

    public init(
        id: UUID = UUID(),
        displayID: UInt32,
        kind: AnnotationKind,
        points: [CGPoint],
        normalizedPoints: [NormalizedAnnotationPoint]? = nil,
        coordinateSpace: AnnotationCoordinateSpace = .legacyCanvasPoints,
        timeRange: AnnotationTimeRange? = nil,
        color: RGBAColor,
        fillColor: RGBAColor? = nil,
        lineWidth: CGFloat = 3,
        opacity: Double = 1,
        text: String? = nil,
        textStyle: AnnotationTextStyle? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isVisible: Bool = true,
        isLocked: Bool = false
    ) {
        self.id = id
        self.displayID = displayID
        self.kind = kind
        self.points = points
        self.normalizedPoints = normalizedPoints
        self.coordinateSpace = coordinateSpace
        self.timeRange = timeRange
        self.color = color
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.text = text
        self.textStyle = textStyle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isVisible = isVisible
        self.isLocked = isLocked
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayID
        case kind
        case points
        case normalizedPoints
        case coordinateSpace
        case timeRange
        case color
        case fillColor
        case lineWidth
        case opacity
        case text
        case textStyle
        case createdAt
        case updatedAt
        case isVisible
        case isLocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let normalizedPoints = try container.decodeIfPresent([NormalizedAnnotationPoint].self, forKey: .normalizedPoints)
        let coordinateSpace = try container.decodeIfPresent(AnnotationCoordinateSpace.self, forKey: .coordinateSpace)
            ?? (normalizedPoints?.isEmpty == false ? .normalizedCapture : .legacyCanvasPoints)

        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            displayID: try container.decodeIfPresent(UInt32.self, forKey: .displayID) ?? 0,
            kind: try container.decodeIfPresent(AnnotationKind.self, forKey: .kind) ?? .pen,
            points: try container.decodeIfPresent([CGPoint].self, forKey: .points) ?? [],
            normalizedPoints: normalizedPoints,
            coordinateSpace: coordinateSpace,
            timeRange: try container.decodeIfPresent(AnnotationTimeRange.self, forKey: .timeRange),
            color: try container.decodeIfPresent(RGBAColor.self, forKey: .color) ?? .yellow,
            fillColor: try container.decodeIfPresent(RGBAColor.self, forKey: .fillColor),
            lineWidth: try container.decodeIfPresent(CGFloat.self, forKey: .lineWidth) ?? 3,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
            text: try container.decodeIfPresent(String.self, forKey: .text),
            textStyle: try container.decodeIfPresent(AnnotationTextStyle.self, forKey: .textStyle),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(),
            isVisible: try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true,
            isLocked: try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayID, forKey: .displayID)
        try container.encode(kind, forKey: .kind)
        try container.encode(points, forKey: .points)
        try container.encodeIfPresent(normalizedPoints, forKey: .normalizedPoints)
        try container.encode(coordinateSpace, forKey: .coordinateSpace)
        try container.encodeIfPresent(timeRange, forKey: .timeRange)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(fillColor, forKey: .fillColor)
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encode(opacity, forKey: .opacity)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(textStyle, forKey: .textStyle)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(isLocked, forKey: .isLocked)
    }

    public func canvasPoints(for size: CGSize) -> [CGPoint] {
        guard coordinateSpace == .normalizedCapture,
              let normalizedPoints,
              !normalizedPoints.isEmpty,
              size.width > 0,
              size.height > 0 else {
            return points
        }
        return normalizedPoints.map { $0.canvasPoint(in: size) }
    }

    public func isVisible(at seconds: Double) -> Bool {
        guard isVisible else { return false }
        guard let timeRange else { return true }
        return timeRange.contains(seconds)
    }

    public static func normalizedCapturePoints(
        fromCanvasPoints points: [CGPoint],
        canvasSize: CGSize
    ) -> [NormalizedAnnotationPoint] {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return [] }
        return points.map { point in
            NormalizedAnnotationPoint(
                x: Double(min(max(point.x / canvasSize.width, 0), 1)),
                y: Double(min(max(1 - point.y / canvasSize.height, 0), 1))
            )
        }
    }

    public var boundingRect: CGRect {
        switch kind {
        case .pen, .highlighter, .line, .arrow, .laser:
            points.boundingRect.expanded(by: max(lineWidth, 8))
        case .rectangle, .ellipse, .whiteboard, .blackboard:
            points.boundingRect.expanded(by: max(lineWidth, 8))
        case .text:
            textBoundingRect
        }
    }

    public func touches(_ point: CGPoint, radius: CGFloat) -> Bool {
        guard isVisible, !points.isEmpty else { return false }

        switch kind {
        case .pen, .highlighter, .line, .arrow, .laser:
            return points.lineSegmentsContain(point, tolerance: max(radius, lineWidth))
        case .rectangle, .ellipse, .whiteboard, .blackboard:
            return boundingRect.expanded(by: radius).contains(point)
        case .text:
            return textBoundingRect.expanded(by: radius).contains(point)
        }
    }

    private var textBoundingRect: CGRect {
        guard let point = points.first else { return .zero }

        let text = text ?? ""
        let style = textStyle ?? AnnotationTextStyle()
        let lines = text.components(separatedBy: .newlines)
        let longestLineCount = lines.map(\.count).max() ?? text.count
        let width = max(CGFloat(longestLineCount) * style.fontSize * 0.62, style.fontSize * 2)
        let height = max(CGFloat(max(lines.count, 1)) * style.fontSize * 1.3, style.fontSize)
        return CGRect(x: point.x, y: point.y, width: width, height: height).expanded(by: 8)
    }
}

public extension Array where Element == CGPoint {
    var boundingRect: CGRect {
        guard let first else { return .zero }

        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y

        for point in self {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
    }

    func lineSegmentsContain(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        guard count > 1 else {
            return first.map { hypot($0.x - point.x, $0.y - point.y) <= tolerance } ?? false
        }

        for index in 0..<(count - 1) {
            let distance = distanceFrom(point, toSegmentStart: self[index], end: self[index + 1])
            if distance <= tolerance {
                return true
            }
        }

        return false
    }

    private func distanceFrom(_ point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y

        guard dx != 0 || dy != 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let numerator = (point.x - start.x) * dx + (point.y - start.y) * dy
        let denominator = dx * dx + dy * dy
        let t = Swift.max(0, Swift.min(1, numerator / denominator))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}

public extension CGRect {
    func expanded(by amount: CGFloat) -> CGRect {
        insetBy(dx: -amount, dy: -amount)
    }
}
