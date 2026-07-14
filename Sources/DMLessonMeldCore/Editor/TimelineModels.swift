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

public struct TimelineRetimingMapper: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        var sourceRange: EditTimeRange
        var outputRange: EditTimeRange
        var playbackRate: Double
    }

    private var segments: [Segment]
    private var retainedSourceRanges: [EditTimeRange]?
    private var sourceDurationSeconds: Double?

    public init(
        speedRegions: [SpeedRegion] = [],
        retainedSourceRanges: [EditTimeRange]? = nil,
        sourceDurationSeconds: Double? = nil
    ) {
        let normalizedDuration = sourceDurationSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.sourceDurationSeconds = normalizedDuration
        self.retainedSourceRanges = retainedSourceRanges.map {
            Self.normalizedRetainedRanges($0, sourceDurationSeconds: normalizedDuration)
        }

        let normalizedSpeedRegions: [SpeedRegion] = speedRegions
            .sorted { left, right in
                if left.range.startSeconds == right.range.startSeconds {
                    return left.id < right.id
                }
                return left.range.startSeconds < right.range.startSeconds
            }
            .compactMap { region -> SpeedRegion? in
                guard region.playbackRate.isFinite, region.playbackRate > 0 else { return nil }
                let startSeconds = max(0, region.range.startSeconds)
                var endSeconds = max(startSeconds, region.range.endSeconds)
                if let normalizedDuration {
                    endSeconds = min(endSeconds, normalizedDuration)
                }
                guard endSeconds > startSeconds else { return nil }
                return SpeedRegion(
                    id: region.id,
                    range: EditTimeRange(startSeconds: startSeconds, endSeconds: endSeconds),
                    playbackRate: region.playbackRate
                )
            }

        let sourceRanges: [EditTimeRange]
        if let retainedSourceRanges = self.retainedSourceRanges {
            sourceRanges = retainedSourceRanges
        } else if let normalizedDuration, normalizedDuration > 0 {
            sourceRanges = [EditTimeRange(startSeconds: 0, durationSeconds: normalizedDuration)]
        } else if let lastSpeedEnd = normalizedSpeedRegions.map(\.range.endSeconds).max(), lastSpeedEnd > 0 {
            sourceRanges = [EditTimeRange(startSeconds: 0, endSeconds: lastSpeedEnd)]
        } else {
            sourceRanges = []
        }

        var outputCursorSeconds = 0.0
        var builtSegments: [Segment] = []
        for sourceRange in sourceRanges {
            let boundaries: [Double] = Set(
                [sourceRange.startSeconds, sourceRange.endSeconds] +
                normalizedSpeedRegions.flatMap { region -> [Double] in
                    guard region.range.overlaps(sourceRange) else { return [] }
                    return [
                        max(sourceRange.startSeconds, region.range.startSeconds),
                        min(sourceRange.endSeconds, region.range.endSeconds)
                    ]
                }
            ).sorted()

            for (startSeconds, endSeconds) in zip(boundaries, boundaries.dropFirst()) where endSeconds > startSeconds {
                let midpoint = startSeconds + (endSeconds - startSeconds) / 2
                let matchingSpeedRegion: SpeedRegion? = normalizedSpeedRegions.first {
                    midpoint >= $0.range.startSeconds && midpoint < $0.range.endSeconds
                }
                let playbackRate = matchingSpeedRegion?.playbackRate ?? 1
                let outputDurationSeconds = (endSeconds - startSeconds) / playbackRate
                builtSegments.append(Segment(
                    sourceRange: EditTimeRange(startSeconds: startSeconds, endSeconds: endSeconds),
                    outputRange: EditTimeRange(startSeconds: outputCursorSeconds, durationSeconds: outputDurationSeconds),
                    playbackRate: playbackRate
                ))
                outputCursorSeconds += outputDurationSeconds
            }
        }
        segments = builtSegments
    }

    public var isIdentity: Bool {
        retainedSourceRanges == nil && segments.allSatisfy { $0.playbackRate == 1 }
    }

    public func outputTime(forSourceTime sourceTimeSeconds: Double) -> Double {
        guard sourceTimeSeconds.isFinite else { return 0 }
        let sourceTimeSeconds = clampedSourceTime(sourceTimeSeconds)
        if segments.isEmpty {
            return retainedSourceRanges == nil ? sourceTimeSeconds : 0
        }
        var priorOutputEndSeconds = 0.0
        for segment in segments {
            if sourceTimeSeconds < segment.sourceRange.startSeconds {
                return priorOutputEndSeconds
            }
            if sourceTimeSeconds <= segment.sourceRange.endSeconds {
                return max(
                    0,
                    segment.outputRange.startSeconds +
                    (sourceTimeSeconds - segment.sourceRange.startSeconds) / segment.playbackRate
                )
            }
            priorOutputEndSeconds = segment.outputRange.endSeconds
        }

        guard retainedSourceRanges == nil, let lastSegment = segments.last else {
            return priorOutputEndSeconds
        }
        return max(0, lastSegment.outputRange.endSeconds + sourceTimeSeconds - lastSegment.sourceRange.endSeconds)
    }

    public func outputRange(forSourceRange sourceRange: EditTimeRange) -> EditTimeRange {
        let startSeconds = outputTime(forSourceTime: sourceRange.startSeconds)
        let endSeconds = outputTime(forSourceTime: sourceRange.endSeconds)
        return EditTimeRange(startSeconds: startSeconds, endSeconds: max(startSeconds, endSeconds))
    }

    public func outputDuration(forSourceDuration sourceDurationSeconds: Double) -> Double {
        outputTime(forSourceTime: sourceDurationSeconds)
    }

    public func isSourceTimeRetained(_ sourceTimeSeconds: Double) -> Bool {
        guard sourceTimeSeconds.isFinite else { return false }
        guard let retainedSourceRanges else {
            return sourceTimeSeconds >= 0 && sourceTimeSeconds <= (sourceDurationSeconds ?? sourceTimeSeconds)
        }
        return retainedSourceRanges.contains {
            sourceTimeSeconds >= $0.startSeconds && sourceTimeSeconds < $0.endSeconds
        }
    }

    var sourceSegments: [Segment] {
        segments
    }

    private func clampedSourceTime(_ seconds: Double) -> Double {
        let nonNegativeSeconds = max(0, seconds)
        guard let sourceDurationSeconds else {
            return nonNegativeSeconds
        }
        return min(nonNegativeSeconds, sourceDurationSeconds)
    }

    private static func normalizedRetainedRanges(
        _ ranges: [EditTimeRange],
        sourceDurationSeconds: Double?
    ) -> [EditTimeRange] {
        var normalized: [EditTimeRange] = []
        for range in ranges.sorted(by: { $0.startSeconds < $1.startSeconds }) {
            let startSeconds = max(0, range.startSeconds)
            let endSeconds = min(
                max(startSeconds, range.endSeconds),
                sourceDurationSeconds ?? .greatestFiniteMagnitude
            )
            guard endSeconds > startSeconds else { continue }
            if let last = normalized.last, startSeconds <= last.endSeconds {
                normalized[normalized.count - 1] = EditTimeRange(
                    startSeconds: last.startSeconds,
                    endSeconds: max(last.endSeconds, endSeconds)
                )
            } else {
                normalized.append(EditTimeRange(startSeconds: startSeconds, endSeconds: endSeconds))
            }
        }
        return normalized
    }
}

public struct NormalizedEditRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = Self.clamped(x)
        self.y = Self.clamped(y)
        self.width = Self.clamped(width)
        self.height = Self.clamped(height)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decodeIfPresent(Double.self, forKey: .x) ?? 0,
            y: try container.decodeIfPresent(Double.self, forKey: .y) ?? 0,
            width: try container.decodeIfPresent(Double.self, forKey: .width) ?? 0,
            height: try container.decodeIfPresent(Double.self, forKey: .height) ?? 0
        )
    }

    public static let center = NormalizedEditRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    public var centerX: Double {
        x + width / 2
    }

    public var centerY: Double {
        y + height / 2
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
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
