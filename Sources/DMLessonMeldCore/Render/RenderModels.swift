import CoreGraphics
import Foundation

public struct RenderPreset: Codable, Equatable, Sendable {
    public var fileType: RenderFileType
    public var quality: RenderQuality

    public init(fileType: RenderFileType = .mp4, quality: RenderQuality = .highest) {
        self.fileType = fileType
        self.quality = quality
    }
}

public enum RenderFileType: String, Codable, CaseIterable, Sendable {
    case mp4
    case mov

    public var fileExtension: String {
        rawValue
    }
}

public enum RenderQuality: String, Codable, CaseIterable, Sendable {
    case medium
    case highest
}

public struct RenderMediaSource: Codable, Equatable, Sendable {
    public var role: RenderMediaRole
    public var relativePath: String
    public var url: URL
    public var mimeType: String?

    public init(role: RenderMediaRole, relativePath: String, url: URL, mimeType: String? = nil) {
        self.role = role
        self.relativePath = relativePath
        self.url = url
        self.mimeType = mimeType
    }
}

public enum RenderMediaRole: String, Codable, Sendable {
    case screenVideo
    case webcamVideo
    case microphoneAudio
    case systemAudio
    case cursorMetadata
    case annotations
    case overlays
    case captions
    case transcript
}

public struct PictureInPictureOverlay: Codable, Equatable, Sendable {
    public var source: RenderMediaSource
    public var placement: PictureInPicturePlacement

    public init(source: RenderMediaSource, placement: PictureInPicturePlacement = .defaultBottomTrailing) {
        self.source = source
        self.placement = placement
    }
}

public struct PictureInPicturePlacement: Codable, Equatable, Sendable {
    public var corner: PictureInPictureCorner
    public var widthRatio: Double
    public var marginRatio: Double
    public var aspectRatio: PictureInPictureAspectRatio
    public var frameShape: PictureInPictureFrameShape
    public var cornerRadius: Double
    public var isMirrored: Bool
    public var borderEnabled: Bool
    public var shadowEnabled: Bool

    public init(
        corner: PictureInPictureCorner,
        widthRatio: Double,
        marginRatio: Double,
        aspectRatio: PictureInPictureAspectRatio = .original,
        frameShape: PictureInPictureFrameShape = .roundedRectangle,
        cornerRadius: Double = 12,
        isMirrored: Bool = false,
        borderEnabled: Bool = false,
        shadowEnabled: Bool = true
    ) {
        self.corner = corner
        self.widthRatio = widthRatio
        self.marginRatio = marginRatio
        self.aspectRatio = aspectRatio
        self.frameShape = frameShape
        self.cornerRadius = cornerRadius
        self.isMirrored = isMirrored
        self.borderEnabled = borderEnabled
        self.shadowEnabled = shadowEnabled
    }

    public static let defaultBottomTrailing = PictureInPicturePlacement(
        corner: .bottomTrailing,
        widthRatio: 0.22,
        marginRatio: 0.04
    )

    public var effectiveAspectRatio: PictureInPictureAspectRatio {
        frameShape == .circle ? .square1x1 : aspectRatio
    }

    public func resolvedSize(sourceSize: CGSize, targetWidth: Double) -> CGSize {
        if frameShape == .circle {
            let side = CGFloat(targetWidth)
            return CGSize(width: side, height: side)
        }

        return aspectRatio.resolvedSize(sourceSize: sourceSize, targetWidth: targetWidth)
    }

    public func resolvedRenderGeometry(sourceSize: CGSize, renderSize: CGSize) -> PictureInPictureRenderGeometry {
        let safeSourceSize = sourceSize.width > 0 && sourceSize.height > 0
            ? sourceSize
            : CGSize(width: 16, height: 9)
        let requestedWidth = max(1, renderSize.width * widthRatio)
        let frameSize = resolvedSize(sourceSize: safeSourceSize, targetWidth: Double(requestedWidth))
        let margin = min(renderSize.width, renderSize.height) * marginRatio
        let frameOrigin: CGPoint

        switch corner {
        case .topLeading:
            frameOrigin = CGPoint(x: margin, y: renderSize.height - margin - frameSize.height)
        case .topTrailing:
            frameOrigin = CGPoint(x: renderSize.width - margin - frameSize.width, y: renderSize.height - margin - frameSize.height)
        case .bottomLeading:
            frameOrigin = CGPoint(x: margin, y: margin)
        case .bottomTrailing:
            frameOrigin = CGPoint(x: renderSize.width - margin - frameSize.width, y: margin)
        }

        let frame = CGRect(origin: frameOrigin, size: frameSize)
        let sourceScale = max(frame.width / safeSourceSize.width, frame.height / safeSourceSize.height)
        let videoSize = CGSize(
            width: safeSourceSize.width * sourceScale,
            height: safeSourceSize.height * sourceScale
        )
        let videoFrame = CGRect(
            x: frame.midX - videoSize.width / 2,
            y: frame.midY - videoSize.height / 2,
            width: videoSize.width,
            height: videoSize.height
        )

        return PictureInPictureRenderGeometry(
            frame: frame,
            cropRect: frame,
            videoFrame: videoFrame,
            sourceScale: sourceScale,
            cornerRadius: resolvedCornerRadius(for: frameSize)
        )
    }

    private func resolvedCornerRadius(for size: CGSize) -> CGFloat {
        switch frameShape {
        case .square:
            0
        case .circle:
            min(size.width, size.height) / 2
        case .roundedRectangle:
            min(max(CGFloat(cornerRadius), 0), min(size.width, size.height) / 2)
        }
    }
}

public struct PictureInPictureRenderGeometry: Equatable, Sendable {
    public var frame: CGRect
    public var cropRect: CGRect
    public var videoFrame: CGRect
    public var sourceScale: CGFloat
    public var cornerRadius: CGFloat

    public init(
        frame: CGRect,
        cropRect: CGRect,
        videoFrame: CGRect,
        sourceScale: CGFloat,
        cornerRadius: CGFloat
    ) {
        self.frame = frame
        self.cropRect = cropRect
        self.videoFrame = videoFrame
        self.sourceScale = sourceScale
        self.cornerRadius = cornerRadius
    }
}

public enum PictureInPictureCorner: String, Codable, CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

public enum PictureInPictureAspectRatio: String, Codable, CaseIterable, Sendable {
    case original
    case square1x1 = "1:1"
    case portrait2x3 = "2:3"
    case landscape3x2 = "3:2"
    case widescreen16x9 = "16:9"

    public func resolvedSize(sourceSize: CGSize, targetWidth: Double) -> CGSize {
        let width = CGFloat(targetWidth)
        switch self {
        case .original:
            return CGSize(width: width, height: width * sourceSize.height / sourceSize.width)
        case .square1x1:
            return CGSize(width: width, height: width)
        case .portrait2x3:
            return CGSize(width: width, height: width * 1.5)
        case .landscape3x2:
            return CGSize(width: width, height: width * 2 / 3)
        case .widescreen16x9:
            return CGSize(width: width, height: width * 9 / 16)
        }
    }
}

public enum PictureInPictureFrameShape: String, Codable, CaseIterable, Sendable {
    case roundedRectangle
    case square
    case circle
}

public struct RenderPlan: Codable, Equatable, Sendable {
    public var projectURL: URL
    public var destinationURL: URL
    public var preset: RenderPreset
    public var screenVideo: RenderMediaSource
    public var webcamOverlay: PictureInPictureOverlay?
    public var audioSources: [RenderMediaSource]
    public var cursorSource: RenderMediaSource?
    public var annotationSource: RenderMediaSource?
    public var overlaySource: RenderMediaSource?
    public var captionSource: RenderMediaSource?
    public var zoomRegions: [ZoomRegion]
    public var markers: [ProjectTimelineMarker]
    public var canvas: EditorCanvasSettings
    public var camera: EditorCameraSettings
    public var cursor: EditorCursorSettings

    public init(
        projectURL: URL,
        destinationURL: URL,
        preset: RenderPreset = RenderPreset(),
        screenVideo: RenderMediaSource,
        webcamOverlay: PictureInPictureOverlay? = nil,
        audioSources: [RenderMediaSource] = [],
        cursorSource: RenderMediaSource? = nil,
        annotationSource: RenderMediaSource? = nil,
        overlaySource: RenderMediaSource? = nil,
        captionSource: RenderMediaSource? = nil,
        zoomRegions: [ZoomRegion] = [],
        markers: [ProjectTimelineMarker] = [],
        canvas: EditorCanvasSettings = EditorCanvasSettings(),
        camera: EditorCameraSettings = EditorCameraSettings(),
        cursor: EditorCursorSettings = EditorCursorSettings()
    ) {
        self.projectURL = projectURL
        self.destinationURL = destinationURL
        self.preset = preset
        self.screenVideo = screenVideo
        self.webcamOverlay = webcamOverlay
        self.audioSources = audioSources
        self.cursorSource = cursorSource
        self.annotationSource = annotationSource
        self.overlaySource = overlaySource
        self.captionSource = captionSource
        self.zoomRegions = zoomRegions
        self.markers = markers
        self.canvas = canvas
        self.camera = camera
        self.cursor = cursor
    }

    public static func make(
        manifest: ProjectManifest,
        projectURL: URL,
        destinationURL: URL,
        preset: RenderPreset = RenderPreset(),
        editDecisionList: EditDecisionList? = nil,
        editorSettings: EditorSettings? = nil
    ) throws -> RenderPlan {
        guard let screen = manifest.media.screen else {
            throw RenderPlanError.missingScreenVideo
        }

        let screenSource = RenderMediaSource(
            role: .screenVideo,
            relativePath: screen.relativePath,
            url: try ProjectBundle.projectLocalFileURL(for: screen, in: projectURL),
            mimeType: screen.mimeType
        )

        let cameraSettings = editorSettings?.camera ?? EditorCameraSettings(
            defaultPlacement: manifest.capture?.pictureInPicturePlacement ?? .defaultBottomTrailing
        )

        let webcamOverlay: PictureInPictureOverlay?
        if let webcam = manifest.media.webcam {
            webcamOverlay = PictureInPictureOverlay(
                source: RenderMediaSource(
                    role: .webcamVideo,
                    relativePath: webcam.relativePath,
                    url: try ProjectBundle.projectLocalFileURL(for: webcam, in: projectURL),
                    mimeType: webcam.mimeType
                ),
                placement: cameraSettings.defaultPlacement
            )
        } else {
            webcamOverlay = nil
        }

        var audioSources: [RenderMediaSource] = []
        if let microphoneAudio = manifest.media.microphoneAudio {
            audioSources.append(
                RenderMediaSource(
                    role: .microphoneAudio,
                    relativePath: microphoneAudio.relativePath,
                    url: try ProjectBundle.projectLocalFileURL(for: microphoneAudio, in: projectURL),
                    mimeType: microphoneAudio.mimeType
                )
            )
        }
        if let systemAudio = manifest.media.systemAudio {
            audioSources.append(
                RenderMediaSource(
                    role: .systemAudio,
                    relativePath: systemAudio.relativePath,
                    url: try ProjectBundle.projectLocalFileURL(for: systemAudio, in: projectURL),
                    mimeType: systemAudio.mimeType
                )
            )
        }

        let cursorSource: RenderMediaSource?
        if let cursorMetadata = manifest.media.cursorMetadata {
            cursorSource = RenderMediaSource(
                role: .cursorMetadata,
                relativePath: cursorMetadata.relativePath,
                url: try ProjectBundle.projectLocalFileURL(for: cursorMetadata, in: projectURL),
                mimeType: cursorMetadata.mimeType
            )
        } else {
            cursorSource = nil
        }

        let annotationSource: RenderMediaSource?
        if let annotations = manifest.media.annotations {
            annotationSource = RenderMediaSource(
                role: .annotations,
                relativePath: annotations.relativePath,
                url: try ProjectBundle.projectLocalFileURL(for: annotations, in: projectURL),
                mimeType: annotations.mimeType
            )
        } else {
            annotationSource = nil
        }

        let overlaySource: RenderMediaSource?
        if let overlays = manifest.media.overlays {
            overlaySource = RenderMediaSource(
                role: .overlays,
                relativePath: overlays.relativePath,
                url: try ProjectBundle.projectLocalFileURL(for: overlays, in: projectURL),
                mimeType: overlays.mimeType
            )
        } else {
            overlaySource = nil
        }

        let captionSource = try transcriptRenderSource(manifest: manifest, projectURL: projectURL)

        return RenderPlan(
            projectURL: projectURL,
            destinationURL: destinationURL,
            preset: preset,
            screenVideo: screenSource,
            webcamOverlay: webcamOverlay,
            audioSources: audioSources,
            cursorSource: cursorSource,
            annotationSource: annotationSource,
            overlaySource: overlaySource,
            captionSource: captionSource,
            zoomRegions: editDecisionList?.enabledZoomRegions ?? [],
            markers: manifest.markers,
            canvas: editorSettings?.canvas ?? EditorCanvasSettings(),
            camera: cameraSettings,
            cursor: editorSettings?.cursor ?? EditorCursorSettings()
        )
    }

    private static func transcriptRenderSource(manifest: ProjectManifest, projectURL: URL) throws -> RenderMediaSource? {
        if let transcript = manifest.media.transcripts.first {
            return RenderMediaSource(
                role: .transcript,
                relativePath: transcript.relativePath,
                url: try ProjectBundle.projectLocalFileURL(for: transcript, in: projectURL),
                mimeType: transcript.mimeType
            )
        }

        guard let captions = manifest.media.captions.first(where: {
            $0.mimeType == "application/json" || $0.relativePath.lowercased().hasSuffix(".json")
        }) else {
            return nil
        }
        return RenderMediaSource(
            role: .captions,
            relativePath: captions.relativePath,
            url: try ProjectBundle.projectLocalFileURL(for: captions, in: projectURL),
            mimeType: captions.mimeType
        )
    }

    public func validate(options: RenderValidationOptions = RenderValidationOptions()) -> [RenderValidationIssue] {
        RenderPlanValidator.validate(self, options: options)
    }
}

public enum RenderPlanError: Error, Equatable, LocalizedError, Sendable {
    case missingScreenVideo

    public var errorDescription: String? {
        switch self {
        case .missingScreenVideo:
            "Project manifest does not reference a screen video."
        }
    }
}

public struct RenderInspection: Codable, Equatable, Sendable {
    public var projectURL: URL
    public var lessonTitle: String
    public var hasWebcamOverlay: Bool
    public var hasCursorEffects: Bool
    public var hasAnnotations: Bool
    public var hasOverlays: Bool
    public var hasCaptions: Bool
    public var hasZoomRegions: Bool
    public var audioSourceCount: Int
    public var plan: RenderPlan?
    public var issues: [RenderValidationIssue]

    public init(
        projectURL: URL,
        lessonTitle: String,
        hasWebcamOverlay: Bool,
        hasCursorEffects: Bool = false,
        hasAnnotations: Bool = false,
        hasOverlays: Bool = false,
        hasCaptions: Bool = false,
        hasZoomRegions: Bool = false,
        audioSourceCount: Int,
        plan: RenderPlan?,
        issues: [RenderValidationIssue]
    ) {
        self.projectURL = projectURL
        self.lessonTitle = lessonTitle
        self.hasWebcamOverlay = hasWebcamOverlay
        self.hasCursorEffects = hasCursorEffects
        self.hasAnnotations = hasAnnotations
        self.hasOverlays = hasOverlays
        self.hasCaptions = hasCaptions
        self.hasZoomRegions = hasZoomRegions
        self.audioSourceCount = audioSourceCount
        self.plan = plan
        self.issues = issues
    }
}
