import CoreGraphics
import Foundation

public struct ProjectManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var appVersion: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: LessonMetadata
    public var media: ProjectMedia
    public var capture: ProjectCaptureSettings?
    public var tracks: [TimelineTrack]
    public var markers: [ProjectTimelineMarker]
    public var exportPresets: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        appVersion: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: LessonMetadata,
        media: ProjectMedia = ProjectMedia(),
        capture: ProjectCaptureSettings? = nil,
        tracks: [TimelineTrack] = [],
        markers: [ProjectTimelineMarker] = [],
        exportPresets: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
        self.media = media
        self.capture = capture
        self.tracks = tracks
        self.markers = markers
        self.exportPresets = exportPresets
    }
}

public struct LessonMetadata: Codable, Equatable, Sendable {
    public var courseTitle: String?
    public var moduleTitle: String?
    public var lessonTitle: String
    public var instructor: String?
    public var summary: String?
    public var tags: [String]
    public var version: String?
    public var license: String?

    public init(
        courseTitle: String? = nil,
        moduleTitle: String? = nil,
        lessonTitle: String,
        instructor: String? = nil,
        summary: String? = nil,
        tags: [String] = [],
        version: String? = nil,
        license: String? = nil
    ) {
        self.courseTitle = courseTitle
        self.moduleTitle = moduleTitle
        self.lessonTitle = lessonTitle
        self.instructor = instructor
        self.summary = summary
        self.tags = tags
        self.version = version
        self.license = license
    }
}

public struct ProjectMedia: Codable, Equatable, Sendable {
    public var screen: ProjectFile?
    public var webcam: ProjectFile?
    public var microphoneAudio: ProjectFile?
    public var systemAudio: ProjectFile?
    public var embeddedAudio: ProjectEmbeddedAudio?
    public var cursorMetadata: ProjectFile?
    public var annotations: ProjectFile?
    public var overlays: ProjectFile?
    public var captions: [ProjectFile]
    public var transcripts: [ProjectFile]
    public var thumbnail: ProjectFile?
    public var attachments: [ProjectFile]

    public init(
        screen: ProjectFile? = nil,
        webcam: ProjectFile? = nil,
        microphoneAudio: ProjectFile? = nil,
        systemAudio: ProjectFile? = nil,
        embeddedAudio: ProjectEmbeddedAudio? = nil,
        cursorMetadata: ProjectFile? = nil,
        annotations: ProjectFile? = nil,
        overlays: ProjectFile? = nil,
        captions: [ProjectFile] = [],
        transcripts: [ProjectFile] = [],
        thumbnail: ProjectFile? = nil,
        attachments: [ProjectFile] = []
    ) {
        self.screen = screen
        self.webcam = webcam
        self.microphoneAudio = microphoneAudio
        self.systemAudio = systemAudio
        self.embeddedAudio = embeddedAudio
        self.cursorMetadata = cursorMetadata
        self.annotations = annotations
        self.overlays = overlays
        self.captions = captions
        self.transcripts = transcripts
        self.thumbnail = thumbnail
        self.attachments = attachments
    }

    public init(
        screen: ProjectFile? = nil,
        webcam: ProjectFile? = nil,
        microphoneAudio: ProjectFile? = nil,
        systemAudio: ProjectFile? = nil,
        embeddedAudio: ProjectEmbeddedAudio? = nil,
        captions: [ProjectFile] = [],
        transcripts: [ProjectFile] = [],
        thumbnail: ProjectFile? = nil,
        attachments: [ProjectFile] = []
    ) {
        self.init(
            screen: screen,
            webcam: webcam,
            microphoneAudio: microphoneAudio,
            systemAudio: systemAudio,
            embeddedAudio: embeddedAudio,
            cursorMetadata: nil,
            annotations: nil,
            overlays: nil,
            captions: captions,
            transcripts: transcripts,
            thumbnail: thumbnail,
            attachments: attachments
        )
    }

    public var allFiles: [ProjectFile] {
        [screen, webcam, microphoneAudio, systemAudio, cursorMetadata, annotations, overlays, thumbnail].compactMap { $0 }
            + captions
            + transcripts
            + attachments
    }

    public var hasEmbeddedSystemAudio: Bool {
        embeddedAudio?.screenVideo.contains(.systemAudio) == true
    }
}

public struct ProjectEmbeddedAudio: Codable, Equatable, Sendable {
    public var screenVideo: [ProjectEmbeddedAudioRole]

    public init(screenVideo: [ProjectEmbeddedAudioRole] = []) {
        self.screenVideo = Array(Set(screenVideo)).sorted { $0.rawValue < $1.rawValue }
    }

    public var isEmpty: Bool {
        screenVideo.isEmpty
    }
}

public enum ProjectEmbeddedAudioRole: String, Codable, CaseIterable, Hashable, Sendable {
    case systemAudio
}

public struct ProjectFile: Codable, Equatable, Sendable {
    public var relativePath: String
    public var role: ProjectFileRole
    public var mimeType: String?
    public var byteCount: Int64?

    public init(
        relativePath: String,
        role: ProjectFileRole,
        mimeType: String? = nil,
        byteCount: Int64? = nil
    ) {
        self.relativePath = relativePath
        self.role = role
        self.mimeType = mimeType
        self.byteCount = byteCount
    }
}

public enum ProjectFileRole: String, Codable, CaseIterable, Sendable {
    case screenVideo
    case webcamVideo
    case microphoneAudio
    case systemAudio
    case cursorMetadata
    case annotations
    case overlays
    case captions
    case transcript
    case thumbnail
    case manifest
    case attachment
}

public struct ProjectCaptureSettings: Codable, Equatable, Sendable {
    public var target: ProjectCaptureTarget
    public var displayID: UInt32?
    public var windowID: UInt32?
    public var region: ProjectCaptureRegion?
    public var screenFPS: Int
    public var includeCursor: Bool
    public var captureInteractionMetadata: Bool
    public var captureMicrophone: Bool
    public var microphoneDeviceID: String?
    public var captureWebcam: Bool
    public var captureSystemAudio: Bool
    public var webcam: ProjectWebcamCaptureSettings

    public init(
        target: ProjectCaptureTarget = .screen,
        displayID: UInt32? = nil,
        windowID: UInt32? = nil,
        region: ProjectCaptureRegion? = nil,
        screenFPS: Int = 60,
        includeCursor: Bool = true,
        captureInteractionMetadata: Bool = true,
        captureMicrophone: Bool = true,
        microphoneDeviceID: String? = nil,
        captureWebcam: Bool = true,
        captureSystemAudio: Bool = false,
        webcam: ProjectWebcamCaptureSettings = ProjectWebcamCaptureSettings()
    ) {
        self.target = target
        self.displayID = displayID
        self.windowID = windowID
        self.region = region
        self.screenFPS = screenFPS
        self.includeCursor = includeCursor
        self.captureInteractionMetadata = captureInteractionMetadata
        self.captureMicrophone = captureMicrophone
        let trimmedMicrophoneDeviceID = microphoneDeviceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.microphoneDeviceID = trimmedMicrophoneDeviceID.isEmpty ? nil : trimmedMicrophoneDeviceID
        self.captureWebcam = captureWebcam
        self.captureSystemAudio = captureSystemAudio
        self.webcam = webcam
    }

    public var pictureInPicturePlacement: PictureInPicturePlacement {
        PictureInPicturePlacement(
            corner: .bottomTrailing,
            widthRatio: webcam.relativeSize,
            marginRatio: 0.04,
            aspectRatio: webcam.pictureInPictureAspectRatio,
            frameShape: webcam.pictureInPictureFrameShape,
            cornerRadius: webcam.cornerRadius,
            isMirrored: webcam.isMirrored,
            borderEnabled: webcam.borderEnabled,
            shadowEnabled: webcam.shadowEnabled
        )
    }
}

public enum ProjectCaptureTarget: String, Codable, CaseIterable, Sendable {
    case screen
    case window
    case region
}

public struct ProjectCaptureRegion: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct ProjectWebcamCaptureSettings: Codable, Equatable, Sendable {
    public var cameraID: String?
    public var resolution: CameraResolution
    public var fps: Int
    public var aspectRatio: WebcamAspectRatio
    public var frameShape: WebcamFrameShape
    public var cornerRadius: Double
    public var relativeSize: Double
    public var isMirrored: Bool
    public var borderEnabled: Bool
    public var shadowEnabled: Bool

    public init(
        cameraID: String? = nil,
        resolution: CameraResolution = .p1080,
        fps: Int = 30,
        aspectRatio: WebcamAspectRatio = .widescreen16x9,
        frameShape: WebcamFrameShape = .roundedRectangle,
        cornerRadius: Double = 18,
        relativeSize: Double = 0.24,
        isMirrored: Bool = false,
        borderEnabled: Bool = false,
        shadowEnabled: Bool = true
    ) {
        self.cameraID = cameraID
        self.resolution = resolution
        self.fps = CapturePreferences.normalizedWebcamFPS(fps)
        self.aspectRatio = aspectRatio
        self.frameShape = frameShape
        self.cornerRadius = min(max(cornerRadius, 0), 64)
        self.relativeSize = min(max(relativeSize, 0.10), 0.40)
        self.isMirrored = isMirrored
        self.borderEnabled = borderEnabled
        self.shadowEnabled = shadowEnabled
    }

    public var pictureInPictureAspectRatio: PictureInPictureAspectRatio {
        PictureInPictureAspectRatio(rawValue: aspectRatio.rawValue) ?? .widescreen16x9
    }

    public var pictureInPictureFrameShape: PictureInPictureFrameShape {
        PictureInPictureFrameShape(rawValue: frameShape.rawValue) ?? .roundedRectangle
    }
}

public struct TimelineTrack: Codable, Equatable, Sendable {
    public var id: String
    public var kind: TimelineTrackKind
    public var displayName: String
    public var isEnabled: Bool

    public init(id: String, kind: TimelineTrackKind, displayName: String, isEnabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.isEnabled = isEnabled
    }
}

public enum TimelineTrackKind: String, Codable, CaseIterable, Sendable {
    case screen
    case webcam
    case microphone
    case systemAudio
    case cursor
    case annotations
    case overlays
    case captions
    case effects
}

public struct ProjectTimelineMarker: Codable, Equatable, Sendable {
    public var id: String
    public var kind: ProjectTimelineMarkerKind
    public var timeSeconds: Double
    public var title: String
    public var notes: String?

    public init(
        id: String,
        kind: ProjectTimelineMarkerKind,
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

public enum ProjectTimelineMarkerKind: String, Codable, CaseIterable, Sendable {
    case chapter
    case retake
    case presenterNote
    case segment
}
