import Foundation

public struct LessonTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var segmentKinds: [LessonSegmentKind]
    public var defaultExportPresetID: String
    public var brandPreset: BrandPreset

    public init(
        id: String,
        name: String,
        summary: String,
        segmentKinds: [LessonSegmentKind],
        defaultExportPresetID: String,
        brandPreset: BrandPreset
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.segmentKinds = segmentKinds
        self.defaultExportPresetID = defaultExportPresetID
        self.brandPreset = brandPreset
    }

    public func seedManifest(lessonTitle: String, courseTitle: String? = nil) -> ProjectManifest {
        ProjectManifest(
            metadata: LessonMetadata(courseTitle: courseTitle, lessonTitle: lessonTitle),
            tracks: TimelineTrackKind.allCases.map {
                TimelineTrack(id: $0.rawValue, kind: $0, displayName: $0.rawValue)
            },
            markers: segmentKinds.enumerated().map { index, kind in
                ProjectTimelineMarker(
                    id: "segment-\(index + 1)",
                    kind: .segment,
                    timeSeconds: 0,
                    title: kind.displayName
                )
            },
            exportPresets: [defaultExportPresetID]
        )
    }
}

public enum LessonSegmentKind: String, Codable, CaseIterable, Sendable {
    case intro
    case setup
    case demo
    case explanation
    case exercise
    case recap
    case outro

    public var displayName: String {
        switch self {
        case .intro: "Intro"
        case .setup: "Setup"
        case .demo: "Demo"
        case .explanation: "Explanation"
        case .exercise: "Exercise"
        case .recap: "Recap"
        case .outro: "Outro"
        }
    }
}

public struct BrandPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var canvasBackground: String
    public var cursorStyle: String
    public var captionStyle: String
    public var cameraLayout: String

    public init(
        id: String,
        name: String,
        canvasBackground: String,
        cursorStyle: String,
        captionStyle: String,
        cameraLayout: String
    ) {
        self.id = id
        self.name = name
        self.canvasBackground = canvasBackground
        self.cursorStyle = cursorStyle
        self.captionStyle = captionStyle
        self.cameraLayout = cameraLayout
    }
}

public struct LessonTemplateExportPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var format: String
    public var codec: String
    public var resolution: String
    public var fps: String
    public var includesSidecars: Bool

    public init(
        id: String,
        name: String,
        format: String,
        codec: String,
        resolution: String,
        fps: String,
        includesSidecars: Bool
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.codec = codec
        self.resolution = resolution
        self.fps = fps
        self.includesSidecars = includesSidecars
    }
}
