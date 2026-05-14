import Foundation

public struct EditTimeRange: Codable, Equatable, Sendable {
    public var startSeconds: Double
    public var durationSeconds: Double

    public init(startSeconds: Double, durationSeconds: Double) {
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
    }

    public init(startSeconds: Double, endSeconds: Double) {
        self.startSeconds = startSeconds
        self.durationSeconds = endSeconds - startSeconds
    }

    public var endSeconds: Double {
        startSeconds + durationSeconds
    }

    public func contains(_ timeSeconds: Double) -> Bool {
        timeSeconds >= startSeconds && timeSeconds <= endSeconds
    }

    public func overlaps(_ other: EditTimeRange) -> Bool {
        startSeconds < other.endSeconds && other.startSeconds < endSeconds
    }
}

public struct TimelineCut: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var range: EditTimeRange
    public var reason: String?
    public var isEnabled: Bool

    public init(
        id: String,
        range: EditTimeRange,
        reason: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.range = range
        self.reason = reason
        self.isEnabled = isEnabled
    }
}

public struct SpeedRegion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var range: EditTimeRange
    public var playbackRate: Double

    public init(id: String, range: EditTimeRange, playbackRate: Double) {
        self.id = id
        self.range = range
        self.playbackRate = playbackRate
    }
}

public struct NormalizedEditRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = Self.clamped(x)
        self.y = Self.clamped(y)
        self.width = Self.clamped(width)
        self.height = Self.clamped(height)
    }

    public static let center = NormalizedEditRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    public var centerX: Double {
        x + width / 2
    }

    public var centerY: Double {
        y + height / 2
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public enum ZoomFocusMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case clickMetadata
    case cursorMetadata

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: "Manual"
        case .clickMetadata: "Click"
        case .cursorMetadata: "Cursor"
        }
    }
}

public enum ZoomEasing: String, Codable, CaseIterable, Identifiable, Sendable {
    case smooth
    case linear
    case instant

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smooth: "Smooth"
        case .linear: "Linear"
        case .instant: "Instant"
        }
    }
}

public struct ZoomRegion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var range: EditTimeRange
    public var focusRect: NormalizedEditRect
    public var scale: Double
    public var isEnabled: Bool
    public var focusMode: ZoomFocusMode?
    public var easing: ZoomEasing?

    public init(
        id: String,
        range: EditTimeRange,
        focusRect: NormalizedEditRect = .center,
        scale: Double = 1.5,
        isEnabled: Bool = true,
        focusMode: ZoomFocusMode? = .manual,
        easing: ZoomEasing? = .smooth
    ) {
        self.id = id
        self.range = range
        self.focusRect = focusRect
        self.scale = scale
        self.isEnabled = isEnabled
        self.focusMode = focusMode
        self.easing = easing
    }
}

public struct TimelineMarker: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: TimelineMarkerKind
    public var timeSeconds: Double
    public var title: String
    public var notes: String?

    public init(
        id: String,
        kind: TimelineMarkerKind,
        timeSeconds: Double,
        title: String,
        notes: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.timeSeconds = timeSeconds
        self.title = title
        self.notes = notes
    }
}

public enum TimelineMarkerKind: String, Codable, CaseIterable, Sendable {
    case chapter
    case retake
    case note
}

public struct EditDecisionList: Codable, Equatable, Sendable {
    public var id: String
    public var sourceMediaURL: URL?
    public var sourceDurationSeconds: Double?
    public var trimRange: EditTimeRange?
    public var cuts: [TimelineCut]
    public var speedRegions: [SpeedRegion]
    public var zoomRegions: [ZoomRegion]
    public var markers: [TimelineMarker]

    public init(
        id: String,
        sourceMediaURL: URL? = nil,
        sourceDurationSeconds: Double? = nil,
        trimRange: EditTimeRange? = nil,
        cuts: [TimelineCut] = [],
        speedRegions: [SpeedRegion] = [],
        zoomRegions: [ZoomRegion] = [],
        markers: [TimelineMarker] = []
    ) {
        self.id = id
        self.sourceMediaURL = sourceMediaURL
        self.sourceDurationSeconds = sourceDurationSeconds
        self.trimRange = trimRange
        self.cuts = cuts
        self.speedRegions = speedRegions
        self.zoomRegions = zoomRegions
        self.markers = markers
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceMediaURL
        case sourceDurationSeconds
        case trimRange
        case cuts
        case speedRegions
        case zoomRegions
        case markers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceMediaURL = try container.decodeIfPresent(URL.self, forKey: .sourceMediaURL)
        sourceDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceDurationSeconds)
        trimRange = try container.decodeIfPresent(EditTimeRange.self, forKey: .trimRange)
        cuts = try container.decodeIfPresent([TimelineCut].self, forKey: .cuts) ?? []
        speedRegions = try container.decodeIfPresent([SpeedRegion].self, forKey: .speedRegions) ?? []
        zoomRegions = try container.decodeIfPresent([ZoomRegion].self, forKey: .zoomRegions) ?? []
        markers = try container.decodeIfPresent([TimelineMarker].self, forKey: .markers) ?? []
    }

    public var effectiveSourceRange: EditTimeRange? {
        if let trimRange {
            return trimRange
        }

        guard let sourceDurationSeconds else {
            return nil
        }

        return EditTimeRange(startSeconds: 0, durationSeconds: sourceDurationSeconds)
    }

    public var enabledCuts: [TimelineCut] {
        cuts.filter(\.isEnabled)
    }

    public var enabledZoomRegions: [ZoomRegion] {
        zoomRegions.filter(\.isEnabled)
    }

    public func validate() -> [EditValidationIssue] {
        EditDecisionListValidator.validate(self)
    }

    public func validated() throws -> EditDecisionList {
        let issues = validate()
        let errors = issues.filter { $0.severity == .error }
        if !errors.isEmpty {
            throw EditValidationError(issues: issues)
        }

        return self
    }
}
