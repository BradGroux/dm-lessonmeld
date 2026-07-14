import AppKit
import AVFoundation
import AVKit
import DMLessonMeldCore
import DMLessonMeldSupport
import SwiftUI
import UniformTypeIdentifiers

enum EditorInspectorTab: String, CaseIterable, Identifiable {
    case edits
    case assets
    case canvas
    case cuts
    case zooms
    case overlays
    case camera
    case audio
    case captions
    case presets
    case cursor
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edits: "Edit"
        case .assets: "Assets"
        case .canvas: "Canvas"
        case .cuts: "Cuts"
        case .zooms: "Zooms"
        case .overlays: "Overlays"
        case .camera: "Camera"
        case .audio: "Audio"
        case .captions: "Captions"
        case .presets: "Presets"
        case .cursor: "Cursor"
        case .export: "Export"
        }
    }

    var systemImage: String {
        switch self {
        case .edits: "slider.horizontal.3"
        case .assets: "folder.badge.gearshape"
        case .canvas: "rectangle.inset.filled"
        case .cuts: "scissors"
        case .zooms: "plus.magnifyingglass"
        case .overlays: "text.bubble"
        case .camera: "video"
        case .audio: "waveform"
        case .captions: "captions.bubble"
        case .presets: "wand.and.stars"
        case .cursor: "cursorarrow.click"
        case .export: "square.and.arrow.up"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .edits: "1"
        case .assets: "2"
        case .canvas: "3"
        case .cuts: "4"
        case .zooms: "5"
        case .overlays: "6"
        case .camera: "7"
        case .audio: "8"
        case .captions: "9"
        case .presets: "0"
        case .cursor: "-"
        case .export: "="
        }
    }
}

enum LessonWorkflowStage: String, CaseIterable, Identifiable {
    case record
    case editVideo
    case exportPackage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .record: "Record"
        case .editVideo: "Edit Video"
        case .exportPackage: "Export/Package"
        }
    }

    var detail: String {
        switch self {
        case .record:
            "Capture a screen, window, area, camera, microphone, and optional system audio."
        case .editVideo:
            "Open a recorded or imported source video for preview, trim, cuts, zooms, overlays, captions, and annotations."
        case .exportPackage:
            "Render the final video or package the lesson for LearnHouse."
        }
    }

    var systemImage: String {
        switch self {
        case .record: "record.circle"
        case .editVideo: "film"
        case .exportPackage: "square.and.arrow.up"
        }
    }
}

struct EditorInspectorAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let handler: () -> Void

    init(_ title: String, systemImage: String, handler: @escaping () -> Void) {
        self.id = title
        self.title = title
        self.systemImage = systemImage
        self.handler = handler
    }
}

struct ProjectAssetGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let items: [ProjectAssetItem]
}

struct ProjectAssetItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let status: String
    let statusTint: Color
    let byteCount: Int64?
    let url: URL?
    let canOpen: Bool
    let issues: [ProjectValidationIssue]
}

enum TimelineSelection: Equatable {
    case cut(String)
    case speed(String)
    case audioVolume(String)
    case zoom(String)
    case overlay(String)
    case caption(String)
    case cameraRegion(String)
    case cursorHide(String)
    case marker(String)
}

enum TimelineDragAction: Equatable {
    case trimStart
    case trimEnd
    case moveCut
    case resizeCutStart
    case resizeCutEnd
    case moveSpeed
    case resizeSpeedStart
    case resizeSpeedEnd
    case moveAudioVolume
    case resizeAudioVolumeStart
    case resizeAudioVolumeEnd
    case moveZoom
    case resizeZoomStart
    case resizeZoomEnd
    case moveOverlay
    case resizeOverlayStart
    case resizeOverlayEnd
    case moveCaption
    case resizeCaptionStart
    case resizeCaptionEnd
    case moveCameraRegion
    case resizeCameraRegionStart
    case resizeCameraRegionEnd
    case moveCursorHide
    case resizeCursorHideStart
    case resizeCursorHideEnd
    case moveMarker
}

struct TimelineDragState {
    var action: TimelineDragAction
    var id: String
    var startSeconds: Double
    var endSeconds: Double
}

struct OverlayPreviewDragState {
    var id: String
    var startX: Double
    var startY: Double
}

struct OverlayPreviewResizeDragState {
    var id: String
    var startWidth: Double
    var startHeight: Double
}

struct ProjectVideoPlayer: NSViewRepresentable {
    var player: AVPlayer
    var controlsStyle: AVPlayerViewControlsStyle = .floating

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = controlsStyle
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
        if view.controlsStyle != controlsStyle {
            view.controlsStyle = controlsStyle
        }
    }
}

struct DashboardCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LessonMeldCard(padding: 18) {
            content
        }
    }
}

struct EditorPanel<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        LessonMeldPanel(title: title, subtitle: subtitle) {
            content
        }
    }
}

extension View {
    func contentPadding(top: CGFloat) -> some View {
        padding(.top, top)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Color {
    init(rgba: RGBAColor) {
        self.init(
            red: min(1, max(0, rgba.red)),
            green: min(1, max(0, rgba.green)),
            blue: min(1, max(0, rgba.blue)),
            opacity: min(1, max(0, rgba.alpha))
        )
    }
}

extension EditorCanvasAspectRatio {
    var previewAspectRatio: CGFloat? {
        switch self {
        case .source:
            nil
        case .custom:
            nil
        case .square1x1:
            1
        case .portrait4x5:
            4 / 5
        case .portrait9x16:
            9 / 16
        case .standard4x3:
            4 / 3
        case .widescreen16x9:
            16 / 9
        }
    }
}

struct EditableCutRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var reason: String
    var isEnabled: Bool
}

struct EditableSpeedRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var playbackRate: String
}

struct EditableAudioVolumeRegionRow: Identifiable, Equatable {
    var id: String
    var track: EditorAudioTrackRole
    var startSeconds: String
    var endSeconds: String
    var gain: String
    var fadeInSeconds: String
    var fadeOutSeconds: String
    var isEnabled: Bool
}

struct EditableCaptionRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var text: String
}

struct EditableZoomRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var scale: String
    var centerX: String
    var centerY: String
    var size: String
    var focusMode: ZoomFocusMode
    var easing: ZoomEasing
    var isEnabled: Bool
}

struct EditableOverlayRow: Identifiable, Equatable {
    var id: String
    var kind: OverlayKind
    var startSeconds: String
    var endSeconds: String
    var text: String
    var x: String
    var y: String
    var width: String
    var height: String
    var opacity: String
    var fontSize: String
    var fadeInSeconds: String
    var fadeOutSeconds: String
    var animationPreset: OverlayAnimationPreset
    var cornerRadius: String
    var highlightMode: OverlayHighlightMode
    var highlightShape: OverlayHighlightShape
    var blurRadius: String
    var featherRadius: String
    var textColor: RGBAColor
    var fillColor: RGBAColor
    var strokeColor: RGBAColor
    var imagePath: String
    var zIndex: Int
    var isEnabled: Bool
}

struct EditableCameraRegionRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var preset: CameraLayoutPreset
    var layoutAnimation: CameraLayoutAnimation
    var transitionSeconds: String
    var isEnabled: Bool
}

struct EditableCameraReactionRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var text: String
    var isEnabled: Bool
}

protocol EditableTimelineRangeRow {
    var id: String { get }
    var startSeconds: String { get set }
    var endSeconds: String { get set }
}

extension EditableCutRow: EditableTimelineRangeRow {}
extension EditableSpeedRow: EditableTimelineRangeRow {}
extension EditableAudioVolumeRegionRow: EditableTimelineRangeRow {}
extension EditableCaptionRow: EditableTimelineRangeRow {}
extension EditableZoomRow: EditableTimelineRangeRow {}
extension EditableOverlayRow: EditableTimelineRangeRow {}
extension EditableCameraRegionRow: EditableTimelineRangeRow {}
extension EditableTimeRangeRow: EditableTimelineRangeRow {}

struct EditableMarkerRow: Identifiable, Equatable {
    var id: String
    var kind: ProjectTimelineMarkerKind
    var timeSeconds: String
    var title: String
    var notes: String
}

struct EditableTimeRangeRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
}

struct ProjectEditorMetadataDirtySnapshot: Equatable {
    var lessonTitle: String
    var courseTitle: String
    var moduleTitle: String
    var instructor: String
    var summary: String
    var tags: String
}

struct ProjectEditorEditDecisionDirtySnapshot: Equatable {
    var trimStartSeconds: String
    var trimEndSeconds: String
    var sourceDurationSeconds: String
    var cuts: [EditableCutRow]
    var speedRegions: [EditableSpeedRow]
    var zoomRegions: [EditableZoomRow]
    var cameraRegions: [EditableCameraRegionRow]
    var cameraReactions: [EditableCameraReactionRow]
    var audioVolumeRegions: [EditableAudioVolumeRegionRow]
    var cursorHiddenRanges: [EditableTimeRangeRow]
}

struct ProjectEditorCanvasDirtySnapshot: Equatable {
    var aspectRatio: EditorCanvasAspectRatio
    var customWidth: String
    var customHeight: String
    var backgroundStyle: EditorCanvasBackgroundStyle
    var primaryColor: RGBAColor
    var secondaryColor: RGBAColor
    var backgroundImagePath: String
    var paddingRatio: Double
    var insetRatio: Double
    var cornerRadiusRatio: Double
    var shadowEnabled: Bool
    var shadowOpacity: Double
    var cropEnabled: Bool
    var cropX: String
    var cropY: String
    var cropWidth: String
    var cropHeight: String
}

struct ProjectEditorCursorDirtySnapshot: Equatable {
    var pointerStyle: EditorCursorPointerStyle
    var pointerVisible: Bool
    var smoothMovement: Bool
    var pointerScale: Double
    var pointerFillColor: RGBAColor
    var pointerStrokeColor: RGBAColor
    var clickEffectsVisible: Bool
    var clickColor: RGBAColor
    var clickScale: Double
    var clickOpacity: Double
    var clickDuration: Double
    var clickSoundEnabled: Bool
    var clickSoundVolume: Double
    var keyboardVisible: Bool
    var keyboardOpacity: Double
}

struct ProjectEditorCameraDirtySnapshot: Equatable {
    var corner: PictureInPictureCorner
    var widthRatio: String
    var marginRatio: String
    var aspectRatio: PictureInPictureAspectRatio
    var frameShape: PictureInPictureFrameShape
    var cornerRadius: String
    var mirrored: Bool
    var borderEnabled: Bool
    var shadowEnabled: Bool
}

struct ProjectEditorAudioDirtySnapshot: Equatable {
    var screenGain: String
    var screenMuted: Bool
    var screenSoloed: Bool
    var microphoneGain: String
    var microphoneMuted: Bool
    var microphoneSoloed: Bool
    var systemGain: String
    var systemMuted: Bool
    var systemSoloed: Bool
    var backgroundMusicPath: String
    var backgroundMusicStart: String
    var backgroundMusicSourceStart: String
    var backgroundMusicDuration: String
    var backgroundMusicGain: String
    var backgroundMusicLoop: Bool
    var backgroundMusicDuckUnderVoice: Bool
    var backgroundMusicDuckedGain: String
    var backgroundMusicFadeIn: String
    var backgroundMusicFadeOut: String
}

struct ProjectEditorExportDirtySnapshot: Equatable {
    var quality: RenderQuality
    var fileType: RenderFileType
    var resolution: RenderResolution
    var frameRate: RenderFrameRate
    var codec: RenderCodec
    var hardwareAccelerationEnabled: Bool
    var maxConcurrentExports: Int
    var alphaChannelEnabled: Bool
    var animatedGIFEnabled: Bool
    var proResEnabled: Bool
}

struct ProjectEditorCaptionDirtySnapshot: Equatable {
    var rows: [EditableCaptionRow]
    var burnInEnabled: Bool
    var placement: EditorCaptionPlacement
    var fontName: String
    var fontSize: String
    var textColor: RGBAColor
    var backgroundColor: RGBAColor
    var maxLineCount: Int
    var safeMargin: String
}

enum ProjectEditorDirtySnapshot: Equatable {
    case metadata(ProjectEditorMetadataDirtySnapshot)
    case markers([EditableMarkerRow])
    case editDecisions(ProjectEditorEditDecisionDirtySnapshot)
    case editorSettings(ProjectEditorSettingsDirtySnapshot<
        ProjectEditorCanvasDirtySnapshot,
        ProjectEditorCursorDirtySnapshot,
        ProjectEditorCameraDirtySnapshot,
        ProjectEditorAudioDirtySnapshot,
        ProjectEditorExportDirtySnapshot
    >)
    case overlays([EditableOverlayRow])
    case captions(ProjectEditorCaptionDirtySnapshot)
}
