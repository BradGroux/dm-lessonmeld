import CoreGraphics
import Foundation

public struct NormalizedCapturePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = Self.clamped(x)
        self.y = Self.clamped(y)
    }

    public init(point: CGPoint, in captureRect: CGRect) {
        let rect = captureRect.standardized
        guard rect.width > 0, rect.height > 0 else {
            self.init(x: 0, y: 0)
            return
        }

        self.init(
            x: (point.x - rect.minX) / rect.width,
            y: (point.y - rect.minY) / rect.height
        )
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public enum CursorClickButton: String, Codable, Equatable, Sendable {
    case left
    case right
    case middle
    case other
}

public enum CursorClickPhase: String, Codable, Equatable, Sendable {
    case down
    case up
}

public struct CursorSample: Codable, Equatable, Sendable {
    public var timestampSeconds: TimeInterval
    public var position: NormalizedCapturePoint
    public var isVisible: Bool

    public init(
        timestampSeconds: TimeInterval,
        position: NormalizedCapturePoint,
        isVisible: Bool = true
    ) {
        self.timestampSeconds = max(0, timestampSeconds)
        self.position = position
        self.isVisible = isVisible
    }
}

public struct CursorClick: Codable, Equatable, Sendable {
    public var timestampSeconds: TimeInterval
    public var position: NormalizedCapturePoint
    public var button: CursorClickButton
    public var phase: CursorClickPhase
    public var clickCount: Int

    public init(
        timestampSeconds: TimeInterval,
        position: NormalizedCapturePoint,
        button: CursorClickButton = .left,
        phase: CursorClickPhase = .down,
        clickCount: Int = 1
    ) {
        self.timestampSeconds = max(0, timestampSeconds)
        self.position = position
        self.button = button
        self.phase = phase
        self.clickCount = max(1, clickCount)
    }
}

public struct InteractionMetadataDocument: Codable, Equatable, Sendable {
    public var schema: String
    public var version: Int
    public var captureSize: CGSize
    public var rendersCursorPointer: Bool
    public var cursorSamples: [CursorSample]
    public var clicks: [CursorClick]
    public var keystrokes: [KeyboardMetadataEvent]

    private enum CodingKeys: String, CodingKey {
        case schema
        case version
        case captureSize
        case rendersCursorPointer
        case cursorSamples
        case clicks
        case keystrokes
    }

    public init(
        schema: String = "io.digitalmeld.dm-lessonmeld.capture-metadata",
        version: Int = 1,
        captureSize: CGSize,
        rendersCursorPointer: Bool = true,
        cursorSamples: [CursorSample] = [],
        clicks: [CursorClick] = [],
        keystrokes: [KeyboardMetadataEvent] = []
    ) {
        self.schema = schema
        self.version = version
        self.captureSize = captureSize
        self.rendersCursorPointer = rendersCursorPointer
        self.cursorSamples = cursorSamples
        self.clicks = clicks
        self.keystrokes = keystrokes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schema: try container.decodeIfPresent(String.self, forKey: .schema) ?? "io.digitalmeld.dm-lessonmeld.capture-metadata",
            version: try container.decodeIfPresent(Int.self, forKey: .version) ?? 1,
            captureSize: try container.decode(CGSize.self, forKey: .captureSize),
            rendersCursorPointer: try container.decodeIfPresent(Bool.self, forKey: .rendersCursorPointer) ?? true,
            cursorSamples: try container.decodeIfPresent([CursorSample].self, forKey: .cursorSamples) ?? [],
            clicks: try container.decodeIfPresent([CursorClick].self, forKey: .clicks) ?? [],
            keystrokes: try container.decodeIfPresent([KeyboardMetadataEvent].self, forKey: .keystrokes) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(version, forKey: .version)
        try container.encode(captureSize, forKey: .captureSize)
        try container.encode(rendersCursorPointer, forKey: .rendersCursorPointer)
        try container.encode(cursorSamples, forKey: .cursorSamples)
        try container.encode(clicks, forKey: .clicks)
        try container.encode(keystrokes, forKey: .keystrokes)
    }

    public func normalizingTimestamps(relativeTo startTimestamp: TimeInterval, pauseOffset: TimeInterval = 0) -> Self {
        Self(
            schema: schema,
            version: version,
            captureSize: captureSize,
            rendersCursorPointer: rendersCursorPointer,
            cursorSamples: cursorSamples.map {
                CursorSample(
                    timestampSeconds: $0.timestampSeconds - startTimestamp - pauseOffset,
                    position: $0.position,
                    isVisible: $0.isVisible
                )
            },
            clicks: clicks.map {
                CursorClick(
                    timestampSeconds: $0.timestampSeconds - startTimestamp - pauseOffset,
                    position: $0.position,
                    button: $0.button,
                    phase: $0.phase,
                    clickCount: $0.clickCount
                )
            },
            keystrokes: keystrokes.map {
                KeyboardMetadataEvent(
                    timestampSeconds: $0.timestampSeconds - startTimestamp - pauseOffset,
                    keyCode: $0.keyCode,
                    characters: $0.characters,
                    modifiers: $0.modifiers,
                    phase: $0.phase,
                    isRepeat: $0.isRepeat
                )
            }
        )
    }
}

public struct InteractionMetadataRecorder: Sendable {
    public var startTimestamp: TimeInterval
    public var pauseOffset: TimeInterval
    public var captureRect: CGRect
    public var rendersCursorPointer: Bool
    public private(set) var cursorSamples: [CursorSample]
    public private(set) var clicks: [CursorClick]
    public private(set) var keystrokes: [KeyboardMetadataEvent]

    public init(
        startTimestamp: TimeInterval = 0,
        pauseOffset: TimeInterval = 0,
        captureRect: CGRect,
        rendersCursorPointer: Bool = true,
        cursorSamples: [CursorSample] = [],
        clicks: [CursorClick] = [],
        keystrokes: [KeyboardMetadataEvent] = []
    ) {
        self.startTimestamp = startTimestamp
        self.pauseOffset = max(0, pauseOffset)
        self.captureRect = captureRect.standardized
        self.rendersCursorPointer = rendersCursorPointer
        self.cursorSamples = cursorSamples
        self.clicks = clicks
        self.keystrokes = keystrokes
    }

    public mutating func addPauseOffset(_ duration: TimeInterval) {
        pauseOffset = max(0, pauseOffset + duration)
    }

    public mutating func appendCursorSample(
        point: CGPoint,
        timestamp: TimeInterval,
        isVisible: Bool = true
    ) {
        cursorSamples.append(
            CursorSample(
                timestampSeconds: normalizedTimestamp(from: timestamp),
                position: NormalizedCapturePoint(point: point, in: captureRect),
                isVisible: isVisible
            )
        )
    }

    public mutating func appendClick(
        point: CGPoint,
        timestamp: TimeInterval,
        button: CursorClickButton = .left,
        phase: CursorClickPhase = .down,
        clickCount: Int = 1
    ) {
        clicks.append(
            CursorClick(
                timestampSeconds: normalizedTimestamp(from: timestamp),
                position: NormalizedCapturePoint(point: point, in: captureRect),
                button: button,
                phase: phase,
                clickCount: clickCount
            )
        )
    }

    public mutating func appendKeystroke(
        timestamp: TimeInterval,
        keyCode: UInt16,
        characters: String? = nil,
        modifiers: KeyboardMetadataModifiers = [],
        phase: KeyboardMetadataPhase = .down,
        isRepeat: Bool = false
    ) {
        keystrokes.append(
            KeyboardMetadataEvent(
                timestampSeconds: normalizedTimestamp(from: timestamp),
                keyCode: keyCode,
                characters: characters,
                modifiers: modifiers,
                phase: phase,
                isRepeat: isRepeat
            )
        )
    }

    public func document() -> InteractionMetadataDocument {
        InteractionMetadataDocument(
            captureSize: captureRect.size,
            rendersCursorPointer: rendersCursorPointer,
            cursorSamples: cursorSamples,
            clicks: clicks,
            keystrokes: keystrokes
        )
    }

    public func normalizedTimestamp(from timestamp: TimeInterval) -> TimeInterval {
        max(0, timestamp - startTimestamp - pauseOffset)
    }
}
