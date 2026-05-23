import AppKit
import AVFoundation
import AVKit
import Combine
import DMLessonMeldCore
import DMLessonMeldSupport
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ProjectEditorModel: ObservableObject {
    @Published var projectURL: URL?
    @Published var manifest: ProjectManifest?
    @Published var summary: ProjectBundleSummary?
    @Published var renderInspection: RenderInspection?
    @Published var player: AVPlayer?
    @Published var currentTimeSeconds: Double = 0
    @Published var previewDurationSeconds: Double = 0
    @Published var isPlaying = false
    @Published var cutRows: [EditableCutRow] = []
    @Published var speedRows: [EditableSpeedRow] = []
    @Published var zoomRows: [EditableZoomRow] = []
    @Published var overlayRows: [EditableOverlayRow] = []
    @Published var markerRows: [EditableMarkerRow] = []
    @Published var editValidationIssues: [EditValidationIssue] = []
    @Published var renderQuality: RenderQuality = .highest
    @Published var renderFileType: RenderFileType = .mp4
    @Published var renderResolution: RenderResolution = .source
    @Published var renderFrameRate: RenderFrameRate = .source
    @Published var renderCodec: RenderCodec = .h264
    @Published var renderHardwareAccelerationEnabled = true
    @Published var renderMaxConcurrentExports = 1
    @Published var renderAlphaChannelEnabled = false
    @Published var renderAnimatedGIFEnabled = false
    @Published var renderProResEnabled = false
    @Published var renderDestinationPath = ""
    @Published var trimDestinationPath = ""
    @Published var rawAssetDestinationPath = ""
    @Published var sharePackageDestinationPath = ""
    @Published var shareFinalVideoPath = ""
    @Published var trimStartSeconds = "0"
    @Published var trimEndSeconds = ""
    @Published var sourceDurationSeconds = ""
    @Published var isRendering = false
    @Published var renderProgress = 0.0
    @Published var isTrimming = false
    @Published var isPackagingLearnHouse = false
    @Published var isExtractingRawAssets = false
    @Published var isBuildingSharePackage = false
    @Published var isExportingFrame = false
    @Published var jobHistory: [EditorJobRecord] = []
    @Published var selectedJobID: String?
    @Published var metadataLessonTitle = ""
    @Published var metadataCourseTitle = ""
    @Published var metadataModuleTitle = ""
    @Published var metadataInstructor = ""
    @Published var metadataSummary = ""
    @Published var metadataTags = ""
    @Published var canvasAspectRatio: EditorCanvasAspectRatio = .source
    @Published var canvasCustomWidth = "1920"
    @Published var canvasCustomHeight = "1080"
    @Published var canvasBackgroundStyle: EditorCanvasBackgroundStyle = .none
    @Published var canvasPrimaryColor: RGBAColor = .black
    @Published var canvasSecondaryColor: RGBAColor = .purple
    @Published var canvasBackgroundImagePath = ""
    @Published var canvasBackgroundImage: NSImage?
    @Published var canvasPaddingRatio = 0.0
    @Published var canvasInsetRatio = 0.0
    @Published var canvasCornerRadiusRatio = 0.0
    @Published var canvasShadowEnabled = false
    @Published var canvasShadowOpacity = 0.34
    @Published var canvasCropEnabled = false
    @Published var canvasCropX = "0"
    @Published var canvasCropY = "0"
    @Published var canvasCropWidth = "1"
    @Published var canvasCropHeight = "1"
    @Published var zoomAutoGenerationEnabled = true
    @Published var cursorPreviewMetadata: InteractionMetadataDocument?
    @Published var cursorPointerStyle: EditorCursorPointerStyle = .macOS
    @Published var cursorPointerVisible = true
    @Published var cursorSmoothMovement = true
    @Published var cursorPointerScale = 1.0
    @Published var cursorPointerFillColor: RGBAColor = .white
    @Published var cursorPointerStrokeColor: RGBAColor = .black
    @Published var cursorClickEffectsVisible = true
    @Published var cursorClickColor: RGBAColor = .yellow
    @Published var cursorClickScale = 1.0
    @Published var cursorClickOpacity = 0.85
    @Published var cursorClickDuration = 0.42
    @Published var cursorClickSoundEnabled = false
    @Published var cursorClickSoundVolume = 0.45
    @Published var cursorKeyboardVisible = true
    @Published var cursorKeyboardOpacity = 0.9
    @Published var cursorHiddenRangeRows: [EditableTimeRangeRow] = []
    @Published var cameraCorner: PictureInPictureCorner = .bottomTrailing
    @Published var cameraWidthRatio = "0.22"
    @Published var cameraMarginRatio = "0.04"
    @Published var cameraAspectRatio: PictureInPictureAspectRatio = .widescreen16x9
    @Published var cameraFrameShape: PictureInPictureFrameShape = .roundedRectangle
    @Published var cameraCornerRadius = "12"
    @Published var cameraMirrored = false
    @Published var cameraBorderEnabled = false
    @Published var cameraShadowEnabled = true
    @Published var cameraRegionRows: [EditableCameraRegionRow] = []
    @Published var cameraReactionRows: [EditableCameraReactionRow] = []
    @Published var screenAudioGain = "1"
    @Published var screenAudioMuted = false
    @Published var screenAudioSoloed = false
    @Published var microphoneAudioGain = "1"
    @Published var microphoneAudioMuted = false
    @Published var microphoneAudioSoloed = false
    @Published var systemAudioGain = "1"
    @Published var systemAudioMuted = false
    @Published var systemAudioSoloed = false
    @Published var backgroundMusicPath = ""
    @Published var backgroundMusicStart = "0"
    @Published var backgroundMusicSourceStart = "0"
    @Published var backgroundMusicDuration = ""
    @Published var backgroundMusicGain = "0.28"
    @Published var backgroundMusicLoop = true
    @Published var backgroundMusicDuckUnderVoice = true
    @Published var backgroundMusicDuckedGain = "0.12"
    @Published var backgroundMusicFadeIn = "0.5"
    @Published var backgroundMusicFadeOut = "0.5"
    @Published var audioVolumeRows: [EditableAudioVolumeRegionRow] = []
    @Published var captionRows: [EditableCaptionRow] = []
    @Published var captionBurnInEnabled = true
    @Published var captionPlacement: EditorCaptionPlacement = .bottom
    @Published var captionFontName = "Helvetica-Bold"
    @Published var captionFontSize = "34"
    @Published var captionTextColor: RGBAColor = .white
    @Published var captionBackgroundColor = RGBAColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 0.72)
    @Published var captionMaxLineCount = 3
    @Published var captionSafeMargin = "0.07"
    @Published var presetName = "Lesson preset"
    @Published var presetSummary = ""
    @Published var presetPreviewSummary = ""
    @Published var annotationItemCount = 0
    @Published var annotationSidecarStatus = "Not initialized"
    @Published var annotationDraftText = "Annotation note"
    @Published var annotationDraftX = "120"
    @Published var annotationDraftY = "120"
    @Published var annotationDraftStart = ""
    @Published var annotationDraftEnd = ""
    @Published var message = ""
    @Published var messageIsError = false
    @Published private(set) var dirtyAreas: Set<ProjectDirtyArea> = []
    private var timeObserver: Any?
    private var lastEditDecisionList: EditDecisionList?
    private var renderTask: Task<Void, Never>?
    private var activeRenderJobID: String?
    private var isLoadingProject = false
    private var isDirtyRefreshScheduled = false
    private var savedDirtyFingerprints: [ProjectDirtyArea: String] = [:]
    private var dirtyStateCancellables: Set<AnyCancellable> = []
    private static let minimumTimelineRangeSeconds = 0.1

    init() {
        bindDirtyStateRefresh()
    }

    var hasUnsavedChanges: Bool {
        !dirtyAreas.isEmpty
    }

    var dirtySummary: String {
        let labels = dirtyAreas.sorted { $0.sortOrder < $1.sortOrder }.map(\.rawValue)
        return labels.isEmpty ? "None" : labels.joined(separator: ", ")
    }

    var activeEditorJob: EditorJobRecord? {
        jobHistory.first { $0.isActive }
    }

    var hasActiveEditorJob: Bool {
        activeEditorJob != nil
    }

    var recentEditorJobs: [EditorJobRecord] {
        Array(jobHistory.prefix(8))
    }

    func canStartEditorJob(_ kind: EditorJobKind) -> Bool {
        guard let projectPath = normalizedCurrentProjectPath else {
            return false
        }
        return EditorJobConflictPolicy.conflictingActiveJob(
            in: jobHistory,
            projectPath: projectPath,
            kind: kind
        ) == nil
    }

    var metadataDirtyFingerprint: String {
        [
            metadataLessonTitle,
            metadataCourseTitle,
            metadataModuleTitle,
            metadataInstructor,
            metadataSummary,
            metadataTags
        ].joined(separator: "||")
    }

    var editDecisionDirtyFingerprint: String {
        [
            trimStartSeconds,
            trimEndSeconds,
            sourceDurationSeconds,
            cutRows.map { "\($0.id)|\($0.startSeconds)|\($0.endSeconds)|\($0.reason)|\($0.isEnabled)" }.joined(separator: "~~"),
            speedRows.map { "\($0.id)|\($0.startSeconds)|\($0.endSeconds)|\($0.playbackRate)" }.joined(separator: "~~"),
            zoomRows.map { "\($0.id)|\($0.startSeconds)|\($0.endSeconds)|\($0.scale)|\($0.centerX)|\($0.centerY)|\($0.size)|\($0.focusMode.rawValue)|\($0.easing.rawValue)|\($0.isEnabled)" }.joined(separator: "~~"),
            cameraRegionRows.map { "\($0.id)|\($0.startSeconds)|\($0.endSeconds)|\($0.preset.rawValue)|\($0.layoutAnimation.rawValue)|\($0.transitionSeconds)|\($0.isEnabled)" }.joined(separator: "~~"),
            cameraReactionRows.map { "\($0.id)|\($0.startSeconds)|\($0.endSeconds)|\($0.text)|\($0.isEnabled)" }.joined(separator: "~~"),
            audioVolumeRows.map { "\($0.id)|\($0.track.rawValue)|\($0.startSeconds)|\($0.endSeconds)|\($0.gain)|\($0.fadeInSeconds)|\($0.fadeOutSeconds)|\($0.isEnabled)" }.joined(separator: "~~"),
            cursorHiddenRangeRows.map { "\($0.id)|\($0.startSeconds)|\($0.endSeconds)" }.joined(separator: "~~")
        ].joined(separator: "||")
    }

    var editorSettingsDirtyFingerprint: String {
        [
            canvasAspectRatio.rawValue,
            canvasCustomWidth,
            canvasCustomHeight,
            canvasBackgroundStyle.rawValue,
            "\(canvasPrimaryColor)",
            "\(canvasSecondaryColor)",
            canvasBackgroundImagePath,
            "\(canvasPaddingRatio)",
            "\(canvasInsetRatio)",
            "\(canvasCornerRadiusRatio)",
            "\(canvasShadowEnabled)",
            "\(canvasShadowOpacity)",
            "\(canvasCropEnabled)",
            canvasCropX,
            canvasCropY,
            canvasCropWidth,
            canvasCropHeight,
            cursorPointerStyle.rawValue,
            "\(cursorPointerVisible)",
            "\(cursorSmoothMovement)",
            "\(cursorPointerScale)",
            "\(cursorPointerFillColor)",
            "\(cursorPointerStrokeColor)",
            "\(cursorClickEffectsVisible)",
            "\(cursorClickColor)",
            "\(cursorClickScale)",
            "\(cursorClickOpacity)",
            "\(cursorClickDuration)",
            "\(cursorClickSoundEnabled)",
            "\(cursorClickSoundVolume)",
            "\(cursorKeyboardVisible)",
            "\(cursorKeyboardOpacity)",
            cameraCorner.rawValue,
            cameraWidthRatio,
            cameraMarginRatio,
            cameraAspectRatio.rawValue,
            cameraFrameShape.rawValue,
            cameraCornerRadius,
            "\(cameraMirrored)",
            "\(cameraBorderEnabled)",
            "\(cameraShadowEnabled)",
            screenAudioGain,
            "\(screenAudioMuted)",
            "\(screenAudioSoloed)",
            microphoneAudioGain,
            "\(microphoneAudioMuted)",
            "\(microphoneAudioSoloed)",
            systemAudioGain,
            "\(systemAudioMuted)",
            "\(systemAudioSoloed)",
            backgroundMusicPath,
            backgroundMusicStart,
            backgroundMusicSourceStart,
            backgroundMusicDuration,
            backgroundMusicGain,
            "\(backgroundMusicLoop)",
            "\(backgroundMusicDuckUnderVoice)",
            backgroundMusicDuckedGain,
            backgroundMusicFadeIn,
            backgroundMusicFadeOut,
            renderQuality.rawValue,
            renderFileType.rawValue,
            renderResolution.rawValue,
            renderFrameRate.rawValue,
            renderCodec.rawValue,
            "\(renderHardwareAccelerationEnabled)",
            "\(renderMaxConcurrentExports)",
            "\(renderAlphaChannelEnabled)",
            "\(renderAnimatedGIFEnabled)",
            "\(renderProResEnabled)"
        ].joined(separator: "||")
    }

    var captionDirtyFingerprint: String {
        [
            captionRows.map { "\($0.id)|\($0.startSeconds)|\($0.endSeconds)|\($0.text)" }.joined(separator: "~~"),
            "\(captionBurnInEnabled)",
            captionPlacement.rawValue,
            captionFontName,
            captionFontSize,
            "\(captionTextColor)",
            "\(captionBackgroundColor)",
            "\(captionMaxLineCount)",
            captionSafeMargin
        ].joined(separator: "||")
    }

    func refreshDirtyState(_ area: ProjectDirtyArea) {
        guard projectURL != nil, !isLoadingProject else { return }
        let current = dirtyFingerprint(for: area)
        var updated = dirtyAreas
        if savedDirtyFingerprints[area] == current {
            updated.remove(area)
        } else {
            updated.insert(area)
        }
        if updated != dirtyAreas {
            dirtyAreas = updated
        }
    }

    func refreshAllDirtyStates() {
        guard projectURL != nil, !isLoadingProject else { return }
        let updated = Set(ProjectDirtyArea.allCases.filter { area in
            savedDirtyFingerprints[area] != dirtyFingerprint(for: area)
        })
        if updated != dirtyAreas {
            dirtyAreas = updated
        }
    }

    func clearDirty(_ area: ProjectDirtyArea) {
        updateSavedFingerprint(for: area)
        dirtyAreas.remove(area)
    }

    func clearAllDirtyChanges() {
        ProjectDirtyArea.allCases.forEach { updateSavedFingerprint(for: $0) }
        dirtyAreas.removeAll()
    }

    func discardUnsavedChanges() {
        guard let projectURL else { return }
        loadProject(projectURL)
        setMessage("Reverted unsaved project changes.")
    }

    func saveAllDirtyChanges() {
        let areas = dirtyAreas
        if areas.contains(.metadata) {
            saveMetadata()
        }
        if areas.contains(.markers) {
            saveMarkers()
        }
        if areas.contains(.editDecisions) {
            saveEditDecisions()
        }
        if areas.contains(.editorSettings) {
            saveEditorSettings()
        }
        if areas.contains(.overlays) {
            saveOverlays()
        }
        if areas.contains(.captions) {
            saveCaptions()
        }
    }

    private func dirtyFingerprint(for area: ProjectDirtyArea) -> String {
        switch area {
        case .metadata:
            return metadataDirtyFingerprint
        case .markers:
            return markerRows
                .map { "\($0.id)|\($0.kind.rawValue)|\($0.timeSeconds)|\($0.title)|\($0.notes)" }
                .joined(separator: "~~")
        case .editDecisions:
            return editDecisionDirtyFingerprint
        case .editorSettings:
            return editorSettingsDirtyFingerprint
        case .overlays:
            return overlayRows
                .map { "\($0.id)|\($0.kind.rawValue)|\($0.startSeconds)|\($0.endSeconds)|\($0.text)|\($0.x)|\($0.y)|\($0.width)|\($0.height)|\($0.opacity)|\($0.fontSize)|\($0.fadeInSeconds)|\($0.fadeOutSeconds)|\($0.animationPreset.rawValue)|\($0.cornerRadius)|\($0.highlightMode.rawValue)|\($0.highlightShape.rawValue)|\($0.blurRadius)|\($0.featherRadius)|\($0.textColor)|\($0.fillColor)|\($0.strokeColor)|\($0.imagePath)|\($0.zIndex)|\($0.isEnabled)" }
                .joined(separator: "~~")
        case .captions:
            return captionDirtyFingerprint
        }
    }

    private func updateSavedFingerprint(for area: ProjectDirtyArea) {
        savedDirtyFingerprints[area] = dirtyFingerprint(for: area)
    }

    private func bindDirtyStateRefresh() {
        objectWillChange
            .sink { [weak self] _ in
                self?.scheduleDirtyStateRefresh()
            }
            .store(in: &dirtyStateCancellables)
    }

    private func scheduleDirtyStateRefresh() {
        guard !isDirtyRefreshScheduled else { return }
        isDirtyRefreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            isDirtyRefreshScheduled = false
            refreshAllDirtyStates()
        }
    }

    func apply(_ preferences: LessonMeldPreferences) {
        renderQuality = RenderQuality(rawValue: preferences.export.defaultRenderQuality.rawValue) ?? .highest
        renderFileType = RenderFileType(rawValue: preferences.export.defaultFileType.rawValue) ?? .mp4
        refreshDefaultDestinations()
    }

    func teardown() {
        removeTimeObserver()
        player?.pause()
        player = nil
        renderTask?.cancel()
        renderTask = nil
    }

    func closeProject() {
        markActiveJobsCancelledForCurrentProject("Project closed before the job completed.")
        teardown()
        projectURL = nil
        manifest = nil
        summary = nil
        renderInspection = nil
        editValidationIssues = []
        lastEditDecisionList = nil
        jobHistory = []
        selectedJobID = nil
        activeRenderJobID = nil
        currentTimeSeconds = 0
        previewDurationSeconds = 0
        isPlaying = false
        clearAllDirtyChanges()
        message = ""
        messageIsError = false
    }

    var formattedCurrentTime: String {
        Self.formatClock(currentTimeSeconds)
    }

    var formattedDuration: String {
        previewDurationSeconds > 0 ? Self.formatClock(previewDurationSeconds) : "--:--"
    }

    func cursorSample(at seconds: Double) -> CursorSample? {
        guard let cursorPreviewMetadata else { return nil }
        let hiddenRanges = cursorHiddenRangeRows.compactMap { row -> EditTimeRange? in
            guard let start = Double(row.startSeconds.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let end = Double(row.endSeconds.trimmingCharacters(in: .whitespacesAndNewlines)),
                  end > start else {
                return nil
            }
            return EditTimeRange(startSeconds: start, endSeconds: end)
        }
        guard !hiddenRanges.contains(where: { $0.contains(seconds) }) else { return nil }
        return cursorPreviewMetadata.cursorSamples
            .filter { $0.timestampSeconds <= seconds && $0.isVisible }
            .max { $0.timestampSeconds < $1.timestampSeconds }
    }

    func cursorClick(at seconds: Double) -> CursorClick? {
        guard let cursorPreviewMetadata else { return nil }
        return cursorPreviewMetadata.clicks
            .filter {
                $0.phase == .down
                    && seconds >= $0.timestampSeconds
                    && seconds <= $0.timestampSeconds + max(0.05, cursorClickDuration)
            }
            .max { $0.timestampSeconds < $1.timestampSeconds }
    }

    func cursorClickProgress(_ click: CursorClick, at seconds: Double) -> Double {
        let duration = max(0.05, cursorClickDuration)
        return min(1, max(0, (seconds - click.timestampSeconds) / duration))
    }

    func keyboardPreviewLabel(at seconds: Double) -> String? {
        guard let cursorPreviewMetadata else { return nil }
        let event = cursorPreviewMetadata.keystrokes
            .filter {
                $0.phase == .down
                    && !$0.isRepeat
                    && seconds >= $0.timestampSeconds
                    && seconds <= $0.timestampSeconds + 0.9
            }
            .max(by: { $0.timestampSeconds < $1.timestampSeconds })
        guard let event else {
            return nil
        }
        return Self.keyboardLabel(for: event)
    }

    var canvasPreviewAspectRatio: CGFloat? {
        if canvasAspectRatio == .custom,
           let width = Double(canvasCustomWidth.trimmingCharacters(in: .whitespacesAndNewlines)),
           let height = Double(canvasCustomHeight.trimmingCharacters(in: .whitespacesAndNewlines)),
           width > 0,
           height > 0 {
            return CGFloat(width / height)
        }
        return canvasAspectRatio.previewAspectRatio
    }

    var canvasPreviewPadding: CGFloat {
        CGFloat(canvasPaddingRatio) * 120
    }

    var canvasPreviewCornerRadius: CGFloat {
        CGFloat(canvasCornerRadiusRatio) * 360
    }

    func importVideoForEditing(_ preferences: LessonMeldPreferences) {
        let panel = NSOpenPanel()
        panel.title = "Create Digital Meld LessonMeld Project from Video"
        panel.message = "Choose an MP4 or MOV file to import into a local lesson bundle."
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.editableVideoContentTypes

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let sourceName = sourceURL.lastPathComponent
        let request = ProjectVideoImportRequest(
            sourceURL: sourceURL,
            defaultProjectDirectory: preferences.general.defaultProjectDirectory,
            defaultTemplateID: preferences.general.defaultTemplateID,
            existingProjectURL: projectURL,
            existingManifest: manifest
        )
        let didAccess = sourceURL.startAccessingSecurityScopedResource()

        setMessage("Importing \(sourceName)...")
        let importTask = Task.detached(priority: .userInitiated) { () throws -> ProjectVideoImportResult in
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            return try ProjectVideoImportService.importVideo(request)
        }

        Task { @MainActor [weak self] in
            do {
                let result = try await importTask.value
                self?.loadProject(result.projectURL)
                self?.setMessage("Imported \(sourceName) for editing.")
            } catch {
                self?.setError(error.localizedDescription)
            }
        }
    }

    func newProject(_ preferences: LessonMeldPreferences) {
        do {
            let panel = NSSavePanel()
            panel.title = "New Digital Meld LessonMeld Project"
            panel.nameFieldStringValue = "Untitled Lesson.dmlm"
            panel.prompt = "Create"
            panel.canCreateDirectories = true
            let defaultDirectory = Self.expandedURL(preferences.general.defaultProjectDirectory)
            try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
            panel.directoryURL = defaultDirectory

            guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
            let projectURL = Self.projectURLWithExtension(selectedURL)
            if FileManager.default.fileExists(atPath: ProjectBundle.manifestURL(in: projectURL).path) {
                throw ProjectEditorError.destinationExists(projectURL.path)
            }

            let lessonTitle = Self.lessonTitle(from: projectURL)
            guard let template = LessonTemplateLibrary.template(id: preferences.general.defaultTemplateID)
                ?? LessonTemplateLibrary.defaultTemplates.first else {
                throw ProjectEditorError.templateNotFound(preferences.general.defaultTemplateID)
            }
            let manifest = template.seedManifest(lessonTitle: lessonTitle)
            try ProjectBundle.writeManifest(manifest, to: projectURL)
            loadProject(projectURL)
            setMessage("Created \(lessonTitle).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Digital Meld LessonMeld Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if let projectType = Self.lessonProjectContentType {
            panel.allowedContentTypes = [projectType]
        }
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(url)
    }

    func loadProject(_ url: URL) {
        do {
            let loadedManifest = try ProjectBundle.loadManifest(at: url)
            try applyLoadedProject(url: url, manifest: loadedManifest, messagePrefix: "Loaded")
        } catch ProjectBundleError.manifestNotFound {
            do {
                let repair = try ProjectBundle.repair(at: url)
                try applyLoadedProject(
                    url: url,
                    manifest: repair.manifest,
                    messagePrefix: repair.wroteManifest ? "Recovered" : "Loaded"
                )
            } catch {
                setError(error.localizedDescription)
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), max(previewDurationSeconds, 0))
        currentTimeSeconds = clamped
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setTrimStartToPlayhead() {
        trimStartSeconds = Self.formatSecondsForEditing(currentTimeSeconds)
    }

    func setTrimEndToPlayhead() {
        trimEndSeconds = Self.formatSecondsForEditing(currentTimeSeconds)
    }

    func updateTrimStart(_ seconds: Double, duration: Double) {
        let end = optionalTimelineSeconds(trimEndSeconds) ?? duration
        let clamped = min(max(0, seconds), max(0, end - Self.minimumTimelineRangeSeconds))
        trimStartSeconds = Self.formatSecondsForEditing(clamped)
        clearTimelineValidation()
    }

    func updateTrimEnd(_ seconds: Double, duration: Double) {
        let start = optionalTimelineSeconds(trimStartSeconds) ?? 0
        let clamped = max(min(max(0, seconds), max(duration, start + Self.minimumTimelineRangeSeconds)), start + Self.minimumTimelineRangeSeconds)
        trimEndSeconds = Self.formatSecondsForEditing(clamped)
        clearTimelineValidation()
    }

    func clearTrim(duration: Double) {
        trimStartSeconds = "0"
        trimEndSeconds = Self.formatSecondsForEditing(duration)
        clearTimelineValidation()
    }

    func stepPlayhead(by delta: Double) {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + abs(delta))
        seek(to: min(max(currentTimeSeconds + delta, 0), max(duration, 0)))
    }

    func copyCurrentFrame() {
        guard !isExportingFrame else { return }
        guard let jobID = beginEditorJob(kind: .frameCopy, detail: "Copy the current preview frame to the clipboard.") else {
            return
        }
        isExportingFrame = true
        setMessage("Copying current frame...")
        Task {
            do {
                let image = try await currentFrameImage()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                isExportingFrame = false
                completeEditorJob(jobID, message: "Copied current frame to the clipboard.")
                setMessage("Copied current frame.")
            } catch {
                isExportingFrame = false
                failEditorJob(jobID, error: error)
                setError(error.localizedDescription)
            }
        }
    }

    func exportCurrentFrame() {
        guard !isExportingFrame else { return }
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let panel = NSSavePanel()
            panel.title = "Export Current Frame"
            panel.nameFieldStringValue = "\(Self.fileSlug(manifest.metadata.lessonTitle))-frame.png"
            panel.allowedContentTypes = [.png]
            panel.canCreateDirectories = true
            panel.directoryURL = projectURL.appendingPathComponent("Exports", isDirectory: true)
            guard panel.runModal() == .OK, let outputURL = panel.url else { return }
            guard let jobID = beginEditorJob(
                kind: .frameExport,
                detail: "Export the current preview frame as PNG.",
                outputURL: outputURL,
                projectURL: projectURL
            ) else {
                return
            }

            isExportingFrame = true
            setMessage("Exporting current frame...")
            Task {
                do {
                    let data = try await currentFramePNGData()
                    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: outputURL, options: [.atomic])
                    isExportingFrame = false
                    let displayPath = Self.displayPath(outputURL, projectURL: projectURL)
                    completeEditorJob(jobID, outputURL: outputURL, message: "Exported frame to \(displayPath).")
                    setMessage("Exported frame \(displayPath).")
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                } catch {
                    isExportingFrame = false
                    failEditorJob(jobID, error: error)
                    setError(error.localizedDescription)
                }
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func addCutAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 5)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 5, max(duration, start + 0.5))
        cutRows.append(
            EditableCutRow(
                id: "cut-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                reason: "Retake",
                isEnabled: true
            )
        )
    }

    func removeCut(id: String) {
        cutRows.removeAll { $0.id == id }
    }

    func moveCut(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &cutRows)
    }

    func resizeCut(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &cutRows)
    }

    func toggleCutEnabled(id: String) {
        guard let index = cutRows.firstIndex(where: { $0.id == id }) else { return }
        cutRows[index].isEnabled.toggle()
        clearTimelineValidation()
    }

    func duplicateCut(id: String, duration: Double) {
        guard let source = cutRows.first(where: { $0.id == id }),
              let start = optionalTimelineSeconds(source.startSeconds),
              let end = optionalTimelineSeconds(source.endSeconds) else {
            return
        }
        let length = max(Self.minimumTimelineRangeSeconds, end - start)
        let nextStart = min(max(0, start + length), max(0, duration - length))
        var duplicate = source
        duplicate.id = "cut-\(UUID().uuidString)"
        duplicate.startSeconds = Self.formatSecondsForEditing(nextStart)
        duplicate.endSeconds = Self.formatSecondsForEditing(nextStart + length)
        cutRows.append(duplicate)
        clearTimelineValidation()
    }

    func addSpeedRegionAtPlayhead(rate: Double) {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 4)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 4, max(duration, start + 0.5))
        speedRows.append(
            EditableSpeedRow(
                id: "speed-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                playbackRate: Self.formatSecondsForEditing(rate)
            )
        )
        clearTimelineValidation()
    }

    func removeSpeedRegion(id: String) {
        speedRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func moveSpeedRegion(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &speedRows)
    }

    func resizeSpeedRegion(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &speedRows)
    }

    func addZoomAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 3)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 3, max(duration, start + 0.5))
        zoomRows.append(
            EditableZoomRow(
                id: "zoom-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                scale: "1.6",
                centerX: "0.5",
                centerY: "0.5",
                size: "0.5",
                focusMode: .manual,
                easing: .smooth,
                isEnabled: true
            )
        )
    }

    func addInstantZoomAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 1)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.1, 0))
        let end = min(start + 1.5, max(duration, start + 0.1))
        zoomRows.append(
            EditableZoomRow(
                id: "zoom-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                scale: "1.8",
                centerX: "0.5",
                centerY: "0.5",
                size: "0.42",
                focusMode: .manual,
                easing: .instant,
                isEnabled: true
            )
        )
    }

    func removeZoom(id: String) {
        zoomRows.removeAll { $0.id == id }
    }

    func moveZoom(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &zoomRows)
    }

    func resizeZoom(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &zoomRows)
    }

    func toggleZoomEnabled(id: String) {
        guard let index = zoomRows.firstIndex(where: { $0.id == id }) else { return }
        zoomRows[index].isEnabled.toggle()
        clearTimelineValidation()
    }

    func duplicateZoom(id: String, duration: Double) {
        guard let source = zoomRows.first(where: { $0.id == id }),
              let start = optionalTimelineSeconds(source.startSeconds),
              let end = optionalTimelineSeconds(source.endSeconds) else {
            return
        }
        let length = max(Self.minimumTimelineRangeSeconds, end - start)
        let nextStart = min(max(0, start + length), max(0, duration - length))
        var duplicate = source
        duplicate.id = "zoom-\(UUID().uuidString)"
        duplicate.startSeconds = Self.formatSecondsForEditing(nextStart)
        duplicate.endSeconds = Self.formatSecondsForEditing(nextStart + length)
        zoomRows.append(duplicate)
        clearTimelineValidation()
    }

    func updateZoomFocus(id: String, centerX: Double? = nil, centerY: Double? = nil, size: Double? = nil) {
        guard let index = zoomRows.firstIndex(where: { $0.id == id }) else { return }
        if let centerX {
            zoomRows[index].centerX = Self.formatNormalized(min(max(centerX, 0), 1))
        }
        if let centerY {
            zoomRows[index].centerY = Self.formatNormalized(min(max(centerY, 0), 1))
        }
        if let size {
            zoomRows[index].size = Self.formatNormalized(min(max(size, 0.08), 1))
        }
        zoomRows[index].focusMode = .manual
        clearTimelineValidation()
    }

    func zoomRow(id: String) -> EditableZoomRow? {
        zoomRows.first { $0.id == id }
    }

    func addOverlayAtPlayhead(kind: OverlayKind) {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 4)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 4, max(duration, start + 0.5))
        overlayRows.append(Self.defaultOverlayRow(kind: kind, start: start, end: end, zIndex: overlayRows.count))
        clearTimelineValidation()
    }

    func chooseOverlayImageAtPlayhead() {
        let id = "overlay-\(UUID().uuidString)"
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 4)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 4, max(duration, start + 0.5))
        overlayRows.append(Self.defaultOverlayRow(id: id, kind: .image, start: start, end: end, zIndex: overlayRows.count))
        if !chooseImage(forOverlayID: id) {
            overlayRows.removeAll { $0.id == id && $0.imagePath.isEmpty }
        }
    }

    func removeOverlay(id: String) {
        overlayRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func moveOverlay(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &overlayRows)
    }

    func resizeOverlay(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &overlayRows)
    }

    func toggleOverlayEnabled(id: String) {
        guard let index = overlayRows.firstIndex(where: { $0.id == id }) else { return }
        overlayRows[index].isEnabled.toggle()
        clearTimelineValidation()
    }

    func updateOverlayFrame(id: String, x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) {
        guard let index = overlayRows.firstIndex(where: { $0.id == id }) else { return }
        let currentX = optionalTimelineSeconds(overlayRows[index].x) ?? 0
        let currentY = optionalTimelineSeconds(overlayRows[index].y) ?? 0
        let currentWidth = optionalTimelineSeconds(overlayRows[index].width) ?? 0.2
        let currentHeight = optionalTimelineSeconds(overlayRows[index].height) ?? 0.15
        if let x {
            overlayRows[index].x = Self.formatNormalized(min(max(x, 0), max(0, 1 - currentWidth)))
        }
        if let y {
            overlayRows[index].y = Self.formatNormalized(min(max(y, 0), max(0, 1 - currentHeight)))
        }
        if let width {
            overlayRows[index].width = Self.formatNormalized(min(max(width, 0.04), max(0.04, 1 - currentX)))
        }
        if let height {
            overlayRows[index].height = Self.formatNormalized(min(max(height, 0.04), max(0.04, 1 - currentY)))
        }
    }

    func overlayRows(at seconds: Double) -> [EditableOverlayRow] {
        overlayRows
            .filter { row in
                guard row.isEnabled,
                      let start = optionalTimelineSeconds(row.startSeconds),
                      let end = optionalTimelineSeconds(row.endSeconds) else {
                    return false
                }
                return seconds >= start && seconds <= end
            }
            .sorted { $0.zIndex < $1.zIndex }
    }

    @discardableResult
    func chooseImage(forOverlayID id: String) -> Bool {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let panel = NSOpenPanel()
            panel.title = "Choose Overlay Image"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.png, .jpeg]
            panel.prompt = "Choose"
            guard panel.runModal() == .OK, let sourceURL = panel.url else { return false }

            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destinationURL = try Self.uniqueOverlayAssetURL(for: sourceURL, projectURL: projectURL)
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            guard let index = overlayRows.firstIndex(where: { $0.id == id }) else { return false }
            overlayRows[index].kind = .image
            overlayRows[index].imagePath = Self.projectFile(
                for: destinationURL,
                role: .attachment,
                projectURL: projectURL,
                mimeType: Self.imageMimeType(for: destinationURL.pathExtension)
            ).relativePath
            saveOverlays()
            return true
        } catch {
            setError(error.localizedDescription)
            return false
        }
    }

    func overlayImage(for row: EditableOverlayRow) -> NSImage? {
        guard let projectURL, !row.imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let imageURL = ProjectBundle.fileURL(
            for: ProjectFile(relativePath: row.imagePath, role: .attachment),
            in: projectURL
        )
        return NSImage(contentsOf: imageURL)
    }

    func chooseBackgroundMusic() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let panel = NSOpenPanel()
            panel.title = "Choose Background Music"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.audio]
            panel.prompt = "Choose"
            guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destinationURL = try Self.uniqueAudioAssetURL(for: sourceURL, projectURL: projectURL)
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            backgroundMusicPath = Self.projectFile(
                for: destinationURL,
                role: .attachment,
                projectURL: projectURL,
                mimeType: Self.audioMimeType(for: destinationURL.pathExtension)
            ).relativePath
            if backgroundMusicDuration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let remaining = max(0.5, (previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? 0)) - (Double(backgroundMusicStart) ?? 0))
                backgroundMusicDuration = Self.formatSecondsForEditing(remaining)
            }
            saveEditorSettings()
        } catch {
            setError(error.localizedDescription)
        }
    }

    func clearBackgroundMusic() {
        backgroundMusicPath = ""
        backgroundMusicDuration = ""
        saveEditorSettings()
    }

    func addAudioVolumeRegionAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 4)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 4, max(duration, start + 0.5))
        audioVolumeRows.append(
            EditableAudioVolumeRegionRow(
                id: "audio-volume-\(UUID().uuidString)",
                track: .all,
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                gain: "0.6",
                fadeInSeconds: "0.12",
                fadeOutSeconds: "0.12",
                isEnabled: true
            )
        )
        clearTimelineValidation()
    }

    func removeAudioVolumeRegion(id: String) {
        audioVolumeRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func moveAudioVolumeRegion(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &audioVolumeRows)
    }

    func resizeAudioVolumeRegion(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &audioVolumeRows)
    }

    func toggleAudioVolumeRegionEnabled(id: String) {
        guard let index = audioVolumeRows.firstIndex(where: { $0.id == id }) else { return }
        audioVolumeRows[index].isEnabled.toggle()
        clearTimelineValidation()
    }

    func addCaptionAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 3)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 3, max(duration, start + 0.5))
        captionRows.append(
            EditableCaptionRow(
                id: "caption-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                text: "Caption text"
            )
        )
        clearTimelineValidation()
    }

    func removeCaption(id: String) {
        captionRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func moveCaption(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &captionRows)
    }

    func resizeCaption(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &captionRows)
    }

    func activeCaption(at seconds: Double) -> EditableCaptionRow? {
        captionRows
            .filter { row in
                guard let start = optionalTimelineSeconds(row.startSeconds),
                      let end = optionalTimelineSeconds(row.endSeconds) else {
                    return false
                }
                return seconds >= start && seconds <= end
            }
            .sorted { ($0.startSeconds, $0.id) < ($1.startSeconds, $1.id) }
            .last
    }

    func addCameraRegionAtPlayhead(preset: CameraLayoutPreset) {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 4)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 4, max(duration, start + 0.5))
        cameraRegionRows.append(EditableCameraRegionRow(
            id: "camera-region-\(UUID().uuidString)",
            startSeconds: Self.formatSecondsForEditing(start),
            endSeconds: Self.formatSecondsForEditing(end),
            preset: preset,
            layoutAnimation: .fade,
            transitionSeconds: "0.18",
            isEnabled: true
        ))
        clearTimelineValidation()
    }

    func removeCameraRegion(id: String) {
        cameraRegionRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func moveCameraRegion(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &cameraRegionRows)
    }

    func resizeCameraRegion(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &cameraRegionRows)
    }

    func toggleCameraRegionEnabled(id: String) {
        guard let index = cameraRegionRows.firstIndex(where: { $0.id == id }) else { return }
        cameraRegionRows[index].isEnabled.toggle()
        clearTimelineValidation()
    }

    func addCameraReactionAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 2)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 1.5, max(duration, start + 0.5))
        cameraReactionRows.append(EditableCameraReactionRow(
            id: "camera-reaction-\(UUID().uuidString)",
            startSeconds: Self.formatSecondsForEditing(start),
            endSeconds: Self.formatSecondsForEditing(end),
            text: "👍",
            isEnabled: true
        ))
        clearTimelineValidation()
    }

    func removeCameraReaction(id: String) {
        cameraReactionRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func generateAutoZoomsFromClicks() {
        do {
            guard zoomAutoGenerationEnabled else {
                throw ProjectEditorError.invalidMetadata("Automatic click zooms are disabled for this project.")
            }
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            guard let cursorMetadata = manifest.media.cursorMetadata else {
                throw ProjectEditorError.invalidMetadata("This project has no cursor/click metadata.")
            }

            let metadataURL = ProjectBundle.fileURL(for: cursorMetadata, in: projectURL)
            let data = try Data(contentsOf: metadataURL)
            let metadata = try DMLessonJSON.decoder().decode(InteractionMetadataDocument.self, from: data)
            let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? 0)
            let clicks = metadata.clicks
                .filter { $0.phase == .down }
                .sorted { $0.timestampSeconds < $1.timestampSeconds }
            guard !clicks.isEmpty else {
                setMessage("No click events were found in cursor metadata.")
                return
            }

            var added = 0
            for click in clicks.prefix(24) {
                let start = max(0, click.timestampSeconds - 0.25)
                let end = duration > 0 ? min(duration, click.timestampSeconds + 1.35) : click.timestampSeconds + 1.35
                guard end > start else { continue }
                zoomRows.append(
                    EditableZoomRow(
                        id: "zoom-click-\(UUID().uuidString)",
                        startSeconds: Self.formatSecondsForEditing(start),
                        endSeconds: Self.formatSecondsForEditing(end),
                        scale: click.clickCount > 1 ? "2.1" : "1.8",
                        centerX: Self.formatNormalized(click.position.x),
                        centerY: Self.formatNormalized(click.position.y),
                        size: "0.38",
                        focusMode: .clickMetadata,
                        easing: .smooth,
                        isEnabled: true
                    )
                )
                added += 1
            }
            clearTimelineValidation()
            if added > 0 {
                saveEditDecisions()
                setMessage("Added \(added) click zoom\(added == 1 ? "" : "s").")
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func addMarkerAtPlayhead() {
        let number = markerRows.count + 1
        let time = previewDurationSeconds > 0 ? currentTimeSeconds : 0
        markerRows.append(
            EditableMarkerRow(
                id: "marker-\(UUID().uuidString)",
                kind: .chapter,
                timeSeconds: Self.formatSecondsForEditing(time),
                title: "Marker \(number)",
                notes: ""
            )
        )
    }

    func removeMarker(id: String) {
        markerRows.removeAll { $0.id == id }
    }

    func moveMarker(id: String, to seconds: Double, duration: Double) {
        guard let index = markerRows.firstIndex(where: { $0.id == id }) else { return }
        markerRows[index].timeSeconds = Self.formatSecondsForEditing(min(max(0, seconds), max(duration, 0)))
        clearTimelineValidation()
    }

    func duplicateMarker(id: String, duration: Double) {
        guard let source = markerRows.first(where: { $0.id == id }),
              let seconds = optionalTimelineSeconds(source.timeSeconds) else {
            return
        }
        var duplicate = source
        duplicate.id = "marker-\(UUID().uuidString)"
        duplicate.title = "\(source.title) Copy"
        duplicate.timeSeconds = Self.formatSecondsForEditing(min(seconds + 1, max(duration, 0)))
        markerRows.append(duplicate)
        clearTimelineValidation()
    }

    func addCursorHiddenRangeAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 2)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.25, 0))
        let end = min(start + 2, max(duration, start + 0.25))
        cursorHiddenRangeRows.append(
            EditableTimeRangeRow(
                id: "cursor-hide-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end)
            )
        )
    }

    func removeCursorHiddenRange(id: String) {
        cursorHiddenRangeRows.removeAll { $0.id == id }
    }

    func moveCursorHiddenRange(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &cursorHiddenRangeRows)
    }

    func resizeCursorHiddenRange(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &cursorHiddenRangeRows)
    }

    func saveMarkers() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let nextMarkers = try markerRows.map { row in
                let timeSeconds = try parseSeconds(row.timeSeconds, label: "Marker time")
                let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else {
                    throw ProjectEditorError.invalidMetadata("Marker title is required.")
                }
                return ProjectTimelineMarker(
                    id: row.id,
                    kind: row.kind,
                    timeSeconds: timeSeconds,
                    title: title,
                    notes: Self.optionalText(row.notes)
                )
            }
            .sorted { first, second in
                if first.timeSeconds == second.timeSeconds {
                    return first.title.localizedStandardCompare(second.title) == .orderedAscending
                }
                return first.timeSeconds < second.timeSeconds
            }

            let updated = try ProjectBundle.updateManifest(at: projectURL) { manifest in
                manifest.markers = nextMarkers
            }
            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            loadMarkerRows(updated.markers)
            loadEditDecisions(projectURL: projectURL, manifest: updated)
            clearDirty(.markers)
            setMessage("Saved lesson markers.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func saveEditDecisions() {
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let editDecisionList = try makeEditDecisionList(projectURL: projectURL, manifest: manifest)
            editValidationIssues = editDecisionList.validate()
            if editValidationIssues.contains(where: { $0.severity == .error }) {
                throw ProjectEditorError.editValidationFailed
            }
            try EditDecisionListFile.save(editDecisionList, toProject: projectURL)
            lastEditDecisionList = editDecisionList
            clearDirty(.editDecisions)
            setMessage("Saved \(EditDecisionListFile.defaultFileName).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func saveOverlays() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let store = try makeOverlayStore()
            try OverlayStoreFile.save(store, toProject: projectURL)
            let updated = try attachOverlayStore(projectURL: projectURL)
            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            renderInspection = nil
            clearDirty(.overlays)
            setMessage("Saved \(OverlayStoreFile.defaultFileName).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func reloadOverlays() {
        guard let projectURL, let manifest else { return }
        loadOverlays(projectURL: projectURL, manifest: manifest)
        clearDirty(.overlays)
        setMessage("Reloaded overlays.")
    }

    func saveCaptions() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let transcript = try makeTranscriptDocument()
            try writeCaptionSidecars(transcript, projectURL: projectURL)
            let updated = try attachCaptionSidecars(projectURL: projectURL)
            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            renderInspection = nil
            clearDirty(.captions)
            setMessage("Saved captions.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func importCaptions() {
        do {
            guard projectURL != nil else {
                throw ProjectEditorError.projectRequired
            }
            let panel = NSOpenPanel()
            panel.title = "Import Captions"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = Self.captionImportContentTypes
            panel.prompt = "Import"
            guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: sourceURL)
            let transcript = try TranscriptImporter.transcript(from: data, fileName: sourceURL.lastPathComponent)
            captionRows = transcript.segments.map(Self.editableCaptionRow(from:))
            saveCaptions()
        } catch {
            setError(error.localizedDescription)
        }
    }

    func exportCaptionSidecars() {
        var jobID: String?
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            jobID = beginEditorJob(
                kind: .captionSidecars,
                detail: "Write VTT, SRT, and transcript text sidecars.",
                projectURL: projectURL
            )
            guard let jobID else {
                return
            }
            let transcript = try makeTranscriptDocument()
            try writeCaptionSidecars(transcript, projectURL: projectURL)
            let updated = try attachCaptionSidecars(projectURL: projectURL)
            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            completeEditorJob(jobID, outputURL: projectURL, message: "Exported caption sidecars into \(Self.displayPath(projectURL, projectURL: projectURL)).")
            setMessage("Exported caption sidecars.")
        } catch {
            if let jobID {
                failEditorJob(jobID, error: error)
            }
            setError(error.localizedDescription)
        }
    }

    func exportEditDecisions() {
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let editDecisionList = try makeEditDecisionList(projectURL: projectURL, manifest: manifest)
            editValidationIssues = editDecisionList.validate()
            if editValidationIssues.contains(where: { $0.severity == .error }) {
                throw ProjectEditorError.editValidationFailed
            }
            try EditDecisionListFile.save(editDecisionList, toProject: projectURL)
            lastEditDecisionList = editDecisionList

            let destinationURL = try destinationURL(path: trimDestinationPath)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw ProjectEditorError.destinationExists(destinationURL.path)
            }
            let plan = try ExportJob(
                id: "edit-decisions-\(UUID().uuidString)",
                editDecisionList: editDecisionList,
                destinationURL: destinationURL,
                preset: ExportPreset(
                    id: "app-edit-decisions",
                    fileType: ExportFileType(rawValue: renderFileType.rawValue) ?? .mp4,
                    quality: ExportQuality(rawValue: renderQuality.rawValue) ?? .highest
                )
            ).makePlan()
            guard let jobID = beginEditorJob(
                kind: .editDecisionExport,
                detail: "Apply saved trim, cut, speed, and zoom decisions.",
                outputURL: destinationURL,
                projectURL: projectURL
            ) else {
                return
            }

            isTrimming = true
            setMessage("Exporting cut list...")
            Task {
                do {
                    let output = try await AVAssetTrimExportService().export(plan: plan)
                    await MainActor.run {
                        self.isTrimming = false
                        let displayPath = Self.displayPath(output, projectURL: projectURL)
                        self.completeEditorJob(jobID, outputURL: output, message: "Exported cut list to \(displayPath).")
                        self.setMessage("Exported cut list \(displayPath).")
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                } catch {
                    await MainActor.run {
                        self.isTrimming = false
                        self.failEditorJob(jobID, error: error)
                        self.setError(error.localizedDescription)
                    }
                }
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func reloadEditDecisions() {
        guard let projectURL, let manifest else { return }
        loadEditDecisions(projectURL: projectURL, manifest: manifest)
        clearDirty(.editDecisions)
        setMessage("Reloaded edit decisions.")
    }

    func saveEditorSettings() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let settings = try currentEditorSettings()
            try EditorSettingsFile.save(settings, toProject: projectURL)
            renderInspection = nil
            clearDirty(.editorSettings)
            setMessage("Saved \(EditorSettingsFile.defaultFileName).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func exportProjectPreset(_ preferences: LessonMeldPreferences) {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw ProjectEditorError.invalidMetadata("Preset name is required.")
            }
            let settings = try currentEditorSettings()
            let manifest = try ProjectBundle.loadManifest(at: projectURL)
            let preset = LessonPreset(
                name: name,
                summary: presetSummary,
                editorSettings: settings,
                capturePreferences: preferences.capture,
                annotationPreferences: preferences.annotation,
                exportPreferences: preferences.export,
                exportPresetIDs: manifest.exportPresets
            )

            let panel = NSSavePanel()
            panel.title = "Save Lesson Preset"
            panel.nameFieldStringValue = Self.fileSlug(name).isEmpty
                ? "lesson-preset.\(LessonPresetFile.fileExtension)"
                : "\(Self.fileSlug(name)).\(LessonPresetFile.fileExtension)"
            if let contentType = Self.lessonPresetContentType {
                panel.allowedContentTypes = [contentType]
            }
            panel.canCreateDirectories = true
            panel.directoryURL = projectURL.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }

            let destinationURL = Self.presetURLWithExtension(url)
            try LessonPresetFile.save(preset, to: destinationURL)
            presetPreviewSummary = Self.presetPreviewSummary(LessonPresetApplier.preview(preset))
            setMessage("Saved preset \(Self.displayPath(destinationURL, projectURL: projectURL)).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func previewProjectPreset() {
        do {
            guard let preset = try chooseLessonPreset(title: "Preview Lesson Preset") else { return }
            presetPreviewSummary = Self.presetPreviewSummary(LessonPresetApplier.preview(preset))
            setMessage("Previewed preset \(preset.name).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func applyProjectPreset() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            guard let preset = try chooseLessonPreset(title: "Apply Lesson Preset") else { return }
            let preview = try LessonPresetApplier.apply(preset, toProject: projectURL)
            presetPreviewSummary = Self.presetPreviewSummary(preview)
            let updated = try ProjectBundle.loadManifest(at: projectURL)
            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            renderInspection = nil
            loadEditorSettings(projectURL: projectURL)
            setMessage("Applied preset \(preset.name).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func resetCanvasSettings() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let settings = EditorSettings()
            applyEditorSettings(settings)
            try EditorSettingsFile.save(settings, toProject: projectURL)
            renderInspection = nil
            setMessage("Reset canvas settings.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func chooseCanvasBackgroundImage() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let panel = NSOpenPanel()
            panel.title = "Choose Canvas Background Image"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.png, .jpeg]
            panel.prompt = "Choose"
            guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destinationURL = try Self.uniqueCanvasBackgroundURL(for: sourceURL, projectURL: projectURL)
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            canvasBackgroundStyle = .image
            canvasBackgroundImagePath = Self.projectFile(
                for: destinationURL,
                role: .attachment,
                projectURL: projectURL,
                mimeType: Self.imageMimeType(for: destinationURL.pathExtension)
            ).relativePath
            canvasBackgroundImage = NSImage(contentsOf: destinationURL)
            saveEditorSettings()
        } catch {
            setError(error.localizedDescription)
        }
    }

    func saveMetadata() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let title = metadataLessonTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw ProjectEditorError.invalidMetadata("Lesson title is required.")
            }

            let updated = try ProjectBundle.updateManifest(at: projectURL) { manifest in
                manifest.metadata.lessonTitle = title
                manifest.metadata.courseTitle = Self.optionalText(metadataCourseTitle)
                manifest.metadata.moduleTitle = Self.optionalText(metadataModuleTitle)
                manifest.metadata.instructor = Self.optionalText(metadataInstructor)
                manifest.metadata.summary = Self.optionalText(metadataSummary)
                manifest.metadata.tags = Self.tags(from: metadataTags)
            }

            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            clearDirty(.metadata)
            setMessage("Saved lesson metadata.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func initializeAnnotationSidecar() {
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let storeURL = try annotationStoreURL(projectURL: projectURL, manifest: manifest, createIfMissing: true)
            let updated = try attachAnnotationStore(projectURL: projectURL, storeURL: storeURL)
            self.manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            loadAnnotationStatus(projectURL: projectURL, manifest: updated)
            setMessage("Initialized annotations sidecar.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func prepareAnnotationSidecarForOverlay() -> URL? {
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let storeURL = try annotationStoreURL(projectURL: projectURL, manifest: manifest, createIfMissing: true)
            let updated = try attachAnnotationStore(projectURL: projectURL, storeURL: storeURL)
            self.manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            loadAnnotationStatus(projectURL: projectURL, manifest: updated)
            return storeURL
        } catch {
            setError(error.localizedDescription)
            return nil
        }
    }

    func reloadAnnotations() {
        guard let projectURL, let manifest else { return }
        loadAnnotationStatus(projectURL: projectURL, manifest: manifest)
        setMessage("Reloaded annotation sidecar.")
    }

    func addTextAnnotation(_ preferences: LessonMeldPreferences) {
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let text = annotationDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ProjectEditorError.invalidMetadata("Annotation text is required.")
            }

            let x = try parseRegionValue(annotationDraftX, label: "Annotation X")
            let y = try parseRegionValue(annotationDraftY, label: "Annotation Y")
            let start = try optionalSeconds(annotationDraftStart, label: "Annotation start") ?? max(currentTimeSeconds, 0)
            let end = try optionalSeconds(annotationDraftEnd, label: "Annotation end") ?? defaultAnnotationEnd(after: start)
            let timeRange = AnnotationTimeRange(startSeconds: start, endSeconds: end)
            guard timeRange.isValid else {
                throw ProjectEditorError.invalidNumber("Annotation end must be greater than annotation start.")
            }
            let storeURL = try annotationStoreURL(projectURL: projectURL, manifest: manifest, createIfMissing: true)
            var store = try loadAnnotationStore(at: storeURL)
            store.add(AnnotationItem(
                displayID: 0,
                kind: .text,
                points: [CGPoint(x: x, y: y)],
                timeRange: timeRange,
                color: Self.annotationColor(from: preferences.annotation.defaultColorHex),
                lineWidth: CGFloat(preferences.annotation.lineWidth),
                text: text,
                textStyle: AnnotationTextStyle(fontSize: 24)
            ))
            try writeAnnotationStore(store, to: storeURL)
            let updated = try attachAnnotationStore(projectURL: projectURL, storeURL: storeURL)
            self.manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            loadAnnotationStatus(projectURL: projectURL, manifest: updated)
            annotationDraftStart = Self.formatSecondsForEditing(start)
            annotationDraftEnd = Self.formatSecondsForEditing(end)
            setMessage("Added text annotation.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func chooseRenderDestination() {
        chooseDestination(defaultPath: renderDestinationPath, fileType: renderFileType) { [weak self] url in
            self?.renderDestinationPath = url.path
        }
    }

    func chooseTrimDestination() {
        chooseDestination(defaultPath: trimDestinationPath, fileType: renderFileType) { [weak self] url in
            self?.trimDestinationPath = url.path
        }
    }

    func chooseRawAssetDestination() {
        chooseDirectory(defaultPath: rawAssetDestinationPath, title: "Choose Raw Asset Folder") { [weak self] url in
            self?.rawAssetDestinationPath = url.path
        }
    }

    func chooseSharePackageDestination() {
        chooseDirectory(defaultPath: sharePackageDestinationPath, title: "Choose Share Package Folder") { [weak self] url in
            self?.sharePackageDestinationPath = url.path
        }
    }

    func chooseShareFinalVideo() {
        let panel = NSOpenPanel()
        panel.title = "Choose Final Rendered Video"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.editableVideoContentTypes
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        shareFinalVideoPath = url.path
    }

    func inspectRender(_ preferences: LessonMeldPreferences) {
        guard let projectURL else {
            setError("Open a project before inspecting render output.")
            return
        }

        do {
            let destinationURL = try destinationURL(path: renderDestinationPath)
            let loadedManifest = try ProjectBundle.loadManifest(at: projectURL)
            do {
                let plan = try renderPlan(
                    projectURL: projectURL,
                    manifest: loadedManifest,
                    destinationURL: destinationURL,
                    preferences: preferences
                )
                renderInspection = RenderInspection(
                    projectURL: projectURL,
                    lessonTitle: loadedManifest.metadata.lessonTitle,
                    hasWebcamOverlay: plan.webcamOverlay != nil,
                    hasCursorEffects: plan.cursorSource != nil,
                    hasAnnotations: plan.annotationSource != nil,
                    hasOverlays: plan.overlaySource != nil,
                    hasCaptions: plan.captionSource != nil,
                    hasZoomRegions: !plan.zoomRegions.isEmpty,
                    audioSourceCount: plan.audioSources.count,
                    plan: plan,
                    issues: plan.validate(options: .export)
                )
            } catch let error as RenderPlanError {
                renderInspection = RenderInspection(
                    projectURL: projectURL,
                    lessonTitle: loadedManifest.metadata.lessonTitle,
                    hasWebcamOverlay: loadedManifest.media.webcam != nil,
                    hasCursorEffects: loadedManifest.media.cursorMetadata != nil,
                    hasAnnotations: loadedManifest.media.annotations != nil,
                    hasOverlays: loadedManifest.media.overlays != nil,
                    hasCaptions: !loadedManifest.media.transcripts.isEmpty || !loadedManifest.media.captions.isEmpty,
                    hasZoomRegions: Self.projectHasZoomRegions(projectURL),
                    audioSourceCount: [loadedManifest.media.microphoneAudio, loadedManifest.media.systemAudio].compactMap { $0 }.count,
                    plan: nil,
                    issues: [
                        RenderValidationIssue(
                            severity: .error,
                            message: error.localizedDescription
                        )
                    ]
                )
            }
            setMessage("Render inspection completed.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func exportRender(_ preferences: LessonMeldPreferences) {
        guard let projectURL else {
            setError("Open a project before exporting.")
            return
        }
        guard !isRendering else { return }

        do {
            let destinationURL = try destinationURL(path: renderDestinationPath)
            guard let jobID = beginEditorJob(
                kind: .renderVideo,
                detail: "Render the edited lesson video.",
                outputURL: destinationURL,
                projectURL: projectURL
            ) else {
                return
            }

            isRendering = true
            renderProgress = 0
            activeRenderJobID = jobID
            setMessage("Rendering full project...")

            renderTask = Task {
                do {
                    let loadedManifest = try ProjectBundle.loadManifest(at: projectURL)
                    let plan = try renderPlan(
                        projectURL: projectURL,
                        manifest: loadedManifest,
                        destinationURL: destinationURL,
                        preferences: preferences
                    )
                    let output = try await AVFoundationRenderService().export(plan: plan) { [weak self] progress in
                        let clampedProgress = min(max(progress, 0), 1)
                        self?.renderProgress = clampedProgress
                        self?.updateEditorJobProgress(jobID, progress: clampedProgress)
                    }
                    await MainActor.run {
                        self.isRendering = false
                        self.renderProgress = 1
                        self.renderTask = nil
                        self.activeRenderJobID = nil
                        let displayPath = Self.displayPath(output, projectURL: projectURL)
                        self.completeEditorJob(jobID, outputURL: output, message: "Rendered video to \(displayPath).")
                        self.setMessage("Rendered \(displayPath).")
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                } catch RenderExportError.exportCancelled {
                    await MainActor.run {
                        self.isRendering = false
                        self.renderTask = nil
                        self.activeRenderJobID = nil
                        self.cancelEditorJob(jobID, message: "Render cancelled by user.")
                        self.setMessage("Render cancelled.")
                    }
                } catch {
                    await MainActor.run {
                        self.isRendering = false
                        self.renderTask = nil
                        self.activeRenderJobID = nil
                        self.failEditorJob(jobID, error: error)
                        self.setError(error.localizedDescription)
                    }
                }
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func packageLearnHouse(_ preferences: LessonMeldPreferences) {
        guard let projectURL else {
            setError("Open a project before packaging.")
            return
        }
        guard !isPackagingLearnHouse else { return }
        let outputDirectory = projectURL
            .deletingLastPathComponent()
            .appendingPathComponent("LearnHouse Exports", isDirectory: true)
        guard let jobID = beginEditorJob(
            kind: .learnHousePackage,
            detail: "Build a LearnHouse course import package.",
            outputURL: outputDirectory,
            projectURL: projectURL
        ) else {
            return
        }

        isPackagingLearnHouse = true
        setMessage("Packaging LearnHouse export...")
        let shouldArchive = preferences.export.createArchiveByDefault

        Task.detached(priority: .userInitiated) {
            do {
                let result = try LearnHousePackageBuilder().buildPackage(
                    projectURL: projectURL,
                    outputDirectory: outputDirectory,
                    archive: shouldArchive
                )
                await MainActor.run {
                    self.isPackagingLearnHouse = false
                    let revealPath = result.archivePath ?? result.packagePath
                    self.completeEditorJob(
                        jobID,
                        outputURL: URL(fileURLWithPath: revealPath),
                        message: "Packaged LearnHouse export at \(revealPath)."
                    )
                    self.setMessage("Packaged LearnHouse export.")
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: revealPath)])
                }
            } catch {
                await MainActor.run {
                    self.isPackagingLearnHouse = false
                    self.failEditorJob(jobID, error: error)
                    self.setError(error.localizedDescription)
                }
            }
        }
    }

    func extractRawAssets() {
        guard let projectURL else {
            setError("Open a project before extracting raw assets.")
            return
        }
        guard !isExtractingRawAssets else { return }

        let outputDirectory = directoryURL(path: rawAssetDestinationPath, fallback: projectURL.deletingLastPathComponent())
        guard let jobID = beginEditorJob(
            kind: .rawAssetExtract,
            detail: "Copy original media, sidecars, and editable project assets.",
            outputURL: outputDirectory,
            projectURL: projectURL
        ) else {
            return
        }

        isExtractingRawAssets = true
        setMessage("Extracting raw assets...")

        Task.detached(priority: .userInitiated) {
            do {
                let result = try RawAssetExtractor().extract(projectURL: projectURL, outputDirectory: outputDirectory)
                await MainActor.run {
                    self.isExtractingRawAssets = false
                    self.completeEditorJob(
                        jobID,
                        outputURL: URL(fileURLWithPath: result.outputDirectoryPath),
                        message: "Extracted \(result.files.count) raw assets to \(result.outputDirectoryPath)."
                    )
                    self.setMessage("Extracted \(result.files.count) raw asset\(result.files.count == 1 ? "" : "s").")
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.outputDirectoryPath)])
                }
            } catch {
                await MainActor.run {
                    self.isExtractingRawAssets = false
                    self.failEditorJob(jobID, error: error)
                    self.setError(error.localizedDescription)
                }
            }
        }
    }

    func buildLocalSharePackage() {
        guard let projectURL else {
            setError("Open a project before building a share package.")
            return
        }
        guard !isBuildingSharePackage else { return }

        let outputDirectory = directoryURL(path: sharePackageDestinationPath, fallback: projectURL.deletingLastPathComponent())
        let finalVideoURL = optionalFileURL(path: shareFinalVideoPath)
        guard let jobID = beginEditorJob(
            kind: .sharePackage,
            detail: "Bundle the project and optional final render for local sharing.",
            outputURL: outputDirectory,
            projectURL: projectURL
        ) else {
            return
        }

        isBuildingSharePackage = true
        setMessage("Building local share package...")

        Task.detached(priority: .userInitiated) {
            do {
                let result = try LocalSharePackageBuilder().buildPackage(
                    projectURL: projectURL,
                    outputDirectory: outputDirectory,
                    finalVideoURL: finalVideoURL
                )
                await MainActor.run {
                    self.isBuildingSharePackage = false
                    self.completeEditorJob(
                        jobID,
                        outputURL: URL(fileURLWithPath: result.packagePath),
                        message: "Built local share package at \(result.packagePath)."
                    )
                    self.setMessage("Built local share package.")
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.packagePath)])
                }
            } catch {
                await MainActor.run {
                    self.isBuildingSharePackage = false
                    self.failEditorJob(jobID, error: error)
                    self.setError(error.localizedDescription)
                }
            }
        }
    }

    func cancelRender() {
        renderTask?.cancel()
        if let activeRenderJobID {
            updateEditorJob(activeRenderJobID) { job in
                job.appendLog("Render cancellation requested.")
            }
        }
        setMessage("Cancelling render...")
    }

    private func renderPlan(
        projectURL: URL,
        manifest: ProjectManifest,
        destinationURL: URL,
        preferences: LessonMeldPreferences
    ) throws -> RenderPlan {
        try ProjectEditorRenderPlanner.makePlan(
            projectURL: projectURL,
            manifest: manifest,
            destinationURL: destinationURL,
            preset: renderPresetFromFields(),
            fallbackWebcamPlacement: QuickRecordingCompletionService.webcamPlacement(from: preferences.capture)
        )
    }

    private func renderPresetFromFields() -> RenderPreset {
        RenderPreset(
            fileType: renderFileType,
            quality: renderQuality,
            resolution: renderResolution,
            frameRate: renderFrameRate,
            codec: renderCodec,
            hardwareAccelerationEnabled: renderHardwareAccelerationEnabled,
            maxConcurrentExports: renderMaxConcurrentExports,
            alphaChannelEnabled: renderAlphaChannelEnabled,
            animatedGIFEnabled: renderAnimatedGIFEnabled,
            proResEnabled: renderProResEnabled || renderCodec == .proRes
        )
    }

    func exportTrim() {
        guard let projectURL, let manifest, let screen = manifest.media.screen else {
            setError("Open a project with a screen recording before trimming.")
            return
        }

        do {
            let start = try parseSeconds(trimStartSeconds, label: "Trim start")
            let end = try parseSeconds(trimEndSeconds, label: "Trim end")
            let duration = try parseSeconds(sourceDurationSeconds, label: "Source duration")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Trim end must be greater than trim start.")
            }
            guard duration >= end else {
                throw ProjectEditorError.invalidNumber("Source duration must be greater than or equal to trim end.")
            }

            let destinationURL = try destinationURL(path: trimDestinationPath)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw ProjectEditorError.destinationExists(destinationURL.path)
            }

            let editList = EditDecisionList(
                id: "app-trim-\(UUID().uuidString)",
                sourceMediaURL: ProjectBundle.fileURL(for: screen, in: projectURL),
                sourceDurationSeconds: duration,
                trimRange: EditTimeRange(startSeconds: start, endSeconds: end)
            )
            let job = ExportJob(
                id: "trim-\(UUID().uuidString)",
                editDecisionList: editList,
                destinationURL: destinationURL,
                preset: ExportPreset(
                    id: "app-trim",
                    fileType: ExportFileType(rawValue: renderFileType.rawValue) ?? .mp4,
                    quality: ExportQuality(rawValue: renderQuality.rawValue) ?? .highest
                )
            )
            let plan = try job.makePlan()
            guard let jobID = beginEditorJob(
                kind: .trimExport,
                detail: "Export the selected trim range.",
                outputURL: destinationURL,
                projectURL: projectURL
            ) else {
                return
            }

            isTrimming = true
            setMessage("Exporting trim...")
            Task {
                do {
                    let output = try await AVAssetTrimExportService().export(plan: plan)
                    await MainActor.run {
                        self.isTrimming = false
                        let displayPath = Self.displayPath(output, projectURL: projectURL)
                        self.completeEditorJob(jobID, outputURL: output, message: "Exported trim to \(displayPath).")
                        self.setMessage("Exported trim \(displayPath).")
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                } catch {
                    await MainActor.run {
                        self.isTrimming = false
                        self.failEditorJob(jobID, error: error)
                        self.setError(error.localizedDescription)
                    }
                }
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func revealProject() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    private func configurePreview(projectURL: URL, manifest: ProjectManifest) {
        removeTimeObserver()
        currentTimeSeconds = 0
        previewDurationSeconds = 0
        isPlaying = false

        guard let screen = manifest.media.screen else {
            player = nil
            return
        }

        let screenURL = ProjectBundle.fileURL(for: screen, in: projectURL)
        let nextPlayer = AVPlayer(url: screenURL)
        player = nextPlayer
        timeObserver = nextPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTimeSeconds = seconds
                }
            }
        }

        Task {
            do {
                let asset = AVURLAsset(url: screenURL)
                let duration = try await asset.load(.duration).seconds
                await MainActor.run {
                    guard duration.isFinite, duration > 0 else { return }
                    self.previewDurationSeconds = duration
                    if self.sourceDurationSeconds.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.sourceDurationSeconds = Self.formatSecondsForEditing(duration)
                    }
                    if self.trimEndSeconds.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.trimEndSeconds = Self.formatSecondsForEditing(duration)
                    }
                }
            } catch {
                await MainActor.run {
                    self.setError("Could not load preview duration: \(error.localizedDescription)")
                }
            }
        }
    }

    private func currentFrameImage() async throws -> NSImage {
        guard let projectURL, let manifest, let screen = manifest.media.screen else {
            throw ProjectEditorError.projectRequired
        }
        let screenURL = ProjectBundle.fileURL(for: screen, in: projectURL)
        let asset = AVURLAsset(url: screenURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.08, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
        let time = CMTime(seconds: max(0, currentTimeSeconds), preferredTimescale: 600)
        let cgImage = try await generator.image(at: time).image
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return image
    }

    private func currentFramePNGData() async throws -> Data {
        let image = try await currentFrameImage()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ProjectEditorError.frameExportFailed
        }
        return pngData
    }

    private func applyLoadedProject(url: URL, manifest loadedManifest: ProjectManifest, messagePrefix: String) throws {
        isLoadingProject = true
        defer {
            isLoadingProject = false
            clearAllDirtyChanges()
        }
        projectURL = url
        manifest = loadedManifest
        summary = try ProjectBundle.inspect(at: url)
        renderInspection = nil
        editValidationIssues = []
        loadEditorJobHistory(projectURL: url)
        loadMetadataFields(loadedManifest.metadata)
        loadMarkerRows(loadedManifest.markers)
        loadAnnotationStatus(projectURL: url, manifest: loadedManifest)
        loadEditorSettings(projectURL: url)
        loadCursorPreviewMetadata(projectURL: url, manifest: loadedManifest)
        loadOverlays(projectURL: url, manifest: loadedManifest)
        loadCaptions(projectURL: url, manifest: loadedManifest)
        refreshDefaultDestinations()
        configurePreview(projectURL: url, manifest: loadedManifest)
        loadEditDecisions(projectURL: url, manifest: loadedManifest)
        setMessage("\(messagePrefix) \(loadedManifest.metadata.lessonTitle).")
    }

    private var normalizedCurrentProjectPath: String? {
        Self.normalizedProjectPath(projectURL)
    }

    private static func normalizedProjectPath(_ url: URL?) -> String? {
        url?.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func displayPath(_ url: URL, projectURL: URL?) -> String {
        SafePathDisplay.projectRelativeOrBasename(url.path, projectPath: normalizedProjectPath(projectURL)) ?? url.lastPathComponent
    }

    private func loadEditorJobHistory(projectURL: URL) {
        do {
            var loadedJobs = try EditorJobHistoryFile.load(fromProject: projectURL)
            var didCancelStaleJobs = false
            for index in loadedJobs.indices where loadedJobs[index].isActive {
                loadedJobs[index].cancel("LessonMeld reopened before this job finished.")
                didCancelStaleJobs = true
            }
            jobHistory = loadedJobs
            selectedJobID = loadedJobs.first?.id
            if didCancelStaleJobs {
                persistEditorJobHistory(projectURL: projectURL)
            }
        } catch {
            jobHistory = []
            selectedJobID = nil
            setError("Could not load job history: \(error.localizedDescription)")
        }
    }

    private func persistEditorJobHistory(projectURL explicitProjectURL: URL? = nil) {
        guard let targetProjectURL = explicitProjectURL ?? projectURL else { return }
        try? EditorJobHistoryFile.save(jobHistory, toProject: targetProjectURL)
    }

    private func beginEditorJob(
        kind: EditorJobKind,
        detail: String? = nil,
        outputURL: URL? = nil,
        projectURL explicitProjectURL: URL? = nil
    ) -> String? {
        guard let targetProjectURL = explicitProjectURL ?? projectURL else {
            setError("Open a project before starting \(kind.title.lowercased()).")
            return nil
        }
        let projectPath = Self.normalizedProjectPath(targetProjectURL)
        if let conflict = EditorJobConflictPolicy.conflictingActiveJob(
            in: jobHistory,
            projectPath: projectPath,
            kind: kind
        ) {
            setError("Finish or cancel \(conflict.title) before starting \(kind.title).")
            return nil
        }

        var job = EditorJobRecord(
            kind: kind,
            detail: detail,
            projectPath: projectPath,
            outputPath: outputURL?.path
        )
        job.start()
        jobHistory.insert(job, at: 0)
        selectedJobID = job.id
        persistEditorJobHistory(projectURL: targetProjectURL)
        return job.id
    }

    private func updateEditorJob(_ id: String, persist: Bool = true, _ update: (inout EditorJobRecord) -> Void) {
        guard let index = jobHistory.firstIndex(where: { $0.id == id }) else { return }
        update(&jobHistory[index])
        if persist {
            persistEditorJobHistory()
        }
    }

    private func updateEditorJobProgress(_ id: String, progress: Double) {
        guard let index = jobHistory.firstIndex(where: { $0.id == id }) else { return }
        let clampedProgress = min(max(progress, 0), 1)
        guard abs(jobHistory[index].progress - clampedProgress) >= 0.01 || clampedProgress >= 1 else {
            return
        }
        jobHistory[index].updateProgress(clampedProgress)
        persistEditorJobHistory()
    }

    private func completeEditorJob(_ id: String, outputURL: URL? = nil, message: String? = nil) {
        updateEditorJob(id) { job in
            job.complete(outputPath: outputURL?.path, message: message)
        }
    }

    private func failEditorJob(_ id: String, error: Error) {
        failEditorJob(id, message: error.localizedDescription)
    }

    private func failEditorJob(_ id: String, message: String) {
        updateEditorJob(id) { job in
            job.fail(message)
        }
    }

    private func cancelEditorJob(_ id: String, message: String? = nil) {
        updateEditorJob(id) { job in
            job.cancel(message)
        }
    }

    private func markActiveJobsCancelledForCurrentProject(_ message: String) {
        guard let projectURL, let projectPath = normalizedCurrentProjectPath else { return }
        var didChange = false
        for index in jobHistory.indices where jobHistory[index].isActive && jobHistory[index].projectPath == projectPath {
            jobHistory[index].cancel(message)
            didChange = true
        }
        if didChange {
            persistEditorJobHistory(projectURL: projectURL)
        }
    }

    func cancelJob(_ job: EditorJobRecord) {
        guard job.isActive else { return }
        guard job.isCancellable else {
            setError("\(job.title) cannot be cancelled after it starts.")
            return
        }
        switch job.kind {
        case .renderVideo:
            cancelRender()
        case .trimExport,
             .editDecisionExport,
             .learnHousePackage,
             .rawAssetExtract,
             .sharePackage,
             .frameExport,
             .frameCopy,
             .captionSidecars:
            setError("\(job.title) cannot be cancelled after it starts.")
        }
    }

    func retryJob(_ job: EditorJobRecord, preferences: LessonMeldPreferences) {
        guard job.isRetryable else {
            setMessage("Only failed or cancelled jobs can be retried.")
            return
        }
        if let outputPath = job.outputPath {
            restoreDestinationPath(outputPath, for: job.kind)
        }
        switch job.kind {
        case .renderVideo:
            exportRender(preferences)
        case .trimExport:
            exportTrim()
        case .editDecisionExport:
            exportEditDecisions()
        case .learnHousePackage:
            packageLearnHouse(preferences)
        case .rawAssetExtract:
            extractRawAssets()
        case .sharePackage:
            buildLocalSharePackage()
        case .frameExport:
            exportCurrentFrame()
        case .frameCopy:
            copyCurrentFrame()
        case .captionSidecars:
            exportCaptionSidecars()
        }
    }

    private func restoreDestinationPath(_ outputPath: String, for kind: EditorJobKind) {
        let restoredOutputPath: String
        if outputPath.hasPrefix("/") {
            restoredOutputPath = outputPath
        } else if let projectURL {
            restoredOutputPath = projectURL.appendingPathComponent(outputPath).path
        } else {
            restoredOutputPath = outputPath
        }

        switch kind {
        case .renderVideo:
            renderDestinationPath = restoredOutputPath
        case .trimExport,
             .editDecisionExport:
            trimDestinationPath = restoredOutputPath
        case .rawAssetExtract:
            rawAssetDestinationPath = restoredOutputPath
        case .sharePackage:
            sharePackageDestinationPath = restoredOutputPath
        case .learnHousePackage,
             .frameExport,
             .frameCopy,
             .captionSidecars:
            break
        }
    }

    func revealJobOutput(_ job: EditorJobRecord) {
        guard let outputURL = jobOutputURL(job) else {
            setError("No output path is available for \(job.title).")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    func copyJobOutputPath(_ job: EditorJobRecord) {
        guard let outputURL = jobOutputURL(job) else {
            setError("No output path is available for \(job.title).")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputURL.path, forType: .string)
        setMessage("Copied \(job.title) output path.")
    }

    func copyJobLog(_ job: EditorJobRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jobLogText(job), forType: .string)
        setMessage("Copied \(job.title) log.")
    }

    func jobLogText(_ job: EditorJobRecord) -> String {
        if job.log.isEmpty {
            return "\(job.title) has no log entries."
        }
        return job.log.map { SafePathDisplay.redactingAbsolutePaths(in: $0) }.joined(separator: "\n")
    }

    private func jobOutputURL(_ job: EditorJobRecord) -> URL? {
        guard let outputPath = job.outputPath, !outputPath.isEmpty else {
            return nil
        }
        if outputPath.hasPrefix("/") {
            return URL(fileURLWithPath: outputPath)
        }
        return projectURL?.appendingPathComponent(outputPath)
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func loadCursorPreviewMetadata(projectURL: URL, manifest: ProjectManifest) {
        guard let cursorMetadata = manifest.media.cursorMetadata else {
            cursorPreviewMetadata = nil
            return
        }

        do {
            let metadataURL = ProjectBundle.fileURL(for: cursorMetadata, in: projectURL)
            let data = try Data(contentsOf: metadataURL)
            cursorPreviewMetadata = try DMLessonJSON.decoder().decode(InteractionMetadataDocument.self, from: data)
        } catch {
            cursorPreviewMetadata = nil
            setError("Could not load cursor metadata preview: \(error.localizedDescription)")
        }
    }

    private func loadOverlays(projectURL: URL, manifest: ProjectManifest) {
        do {
            let store: OverlayStore
            if let overlays = manifest.media.overlays {
                let url = ProjectBundle.fileURL(for: overlays, in: projectURL)
                let data = try Data(contentsOf: url)
                store = try DMLessonJSON.decoder().decode(OverlayStore.self, from: data)
            } else if let existing = try OverlayStoreFile.loadIfPresent(fromProject: projectURL) {
                store = existing
            } else {
                store = OverlayStore()
            }
            overlayRows = store.overlays.map(Self.editableOverlayRow(from:))
        } catch {
            overlayRows = []
            setError("Could not load overlays: \(error.localizedDescription)")
        }
    }

    private func loadCaptions(projectURL: URL, manifest: ProjectManifest) {
        do {
            guard let source = Self.captionSourceFile(in: manifest) else {
                captionRows = []
                return
            }
            let url = ProjectBundle.fileURL(for: source, in: projectURL)
            guard FileManager.default.fileExists(atPath: url.path) else {
                captionRows = []
                return
            }
            let data = try Data(contentsOf: url)
            let transcript: TranscriptDocument
            if source.mimeType == "application/json" || source.relativePath.lowercased().hasSuffix(".json") {
                transcript = try DMLessonJSON.decoder().decode(TranscriptDocument.self, from: data)
            } else {
                transcript = try TranscriptImporter.transcript(from: data, fileName: source.relativePath)
            }
            captionRows = transcript.segments.map(Self.editableCaptionRow(from:))
        } catch {
            captionRows = []
            setError("Could not load captions: \(error.localizedDescription)")
        }
    }

    private func loadEditDecisions(projectURL: URL, manifest: ProjectManifest) {
        do {
            let editDecisionList: EditDecisionList
            if EditDecisionListFile.exists(in: projectURL) {
                editDecisionList = try EditDecisionListFile.load(fromProject: projectURL)
            } else {
                editDecisionList = defaultEditDecisionList(projectURL: projectURL, manifest: manifest)
            }

            lastEditDecisionList = editDecisionList
            cutRows = editDecisionList.cuts.map { cut in
                EditableCutRow(
                    id: cut.id,
                    startSeconds: Self.formatSecondsForEditing(cut.range.startSeconds),
                    endSeconds: Self.formatSecondsForEditing(cut.range.endSeconds),
                    reason: cut.reason ?? "",
                    isEnabled: cut.isEnabled
                )
            }
            speedRows = editDecisionList.speedRegions.map(Self.editableSpeedRow(from:))
            zoomRows = editDecisionList.zoomRegions.map { zoom in
                let size = min(zoom.focusRect.width, zoom.focusRect.height)
                return EditableZoomRow(
                    id: zoom.id,
                    startSeconds: Self.formatSecondsForEditing(zoom.range.startSeconds),
                    endSeconds: Self.formatSecondsForEditing(zoom.range.endSeconds),
                    scale: Self.formatSecondsForEditing(zoom.scale),
                    centerX: Self.formatNormalized(zoom.focusRect.centerX),
                    centerY: Self.formatNormalized(zoom.focusRect.centerY),
                    size: Self.formatNormalized(size),
                    focusMode: zoom.focusMode ?? .manual,
                    easing: zoom.easing ?? .smooth,
                    isEnabled: zoom.isEnabled
                )
            }
            if let trimRange = editDecisionList.trimRange {
                trimStartSeconds = Self.formatSecondsForEditing(trimRange.startSeconds)
                trimEndSeconds = Self.formatSecondsForEditing(trimRange.endSeconds)
            } else {
                trimStartSeconds = "0"
                trimEndSeconds = editDecisionList.sourceDurationSeconds.map(Self.formatSecondsForEditing) ?? ""
            }
            sourceDurationSeconds = editDecisionList.sourceDurationSeconds.map(Self.formatSecondsForEditing) ?? sourceDurationSeconds
            editValidationIssues = editDecisionList.validate()
        } catch {
            cutRows = []
            speedRows = []
            zoomRows = []
            editValidationIssues = []
            setError("Could not load edit decisions: \(error.localizedDescription)")
        }
    }

    private func loadEditorSettings(projectURL: URL) {
        do {
            let settings = try EditorSettingsFile.loadIfPresent(fromProject: projectURL) ?? EditorSettings()
            applyEditorSettings(settings)
        } catch {
            applyEditorSettings(EditorSettings())
            setError("Could not load \(EditorSettingsFile.defaultFileName): \(error.localizedDescription)")
        }
    }

    private func updateRangeRow<Row: EditableTimelineRangeRow>(
        id: String,
        start: Double,
        end: Double,
        duration: Double,
        rows: inout [Row]
    ) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let length = max(Self.minimumTimelineRangeSeconds, end - start)
        let maxStart = max(0, duration - length)
        let nextStart = min(max(0, start), maxStart)
        rows[index].startSeconds = Self.formatSecondsForEditing(nextStart)
        rows[index].endSeconds = Self.formatSecondsForEditing(nextStart + length)
        clearTimelineValidation()
    }

    private func resizeRangeRow<Row: EditableTimelineRangeRow>(
        id: String,
        start: Double,
        end: Double,
        duration: Double,
        rows: inout [Row]
    ) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let nextStart = min(max(0, start), max(0, duration - Self.minimumTimelineRangeSeconds))
        let nextEnd = min(max(end, nextStart + Self.minimumTimelineRangeSeconds), max(duration, nextStart + Self.minimumTimelineRangeSeconds))
        rows[index].startSeconds = Self.formatSecondsForEditing(nextStart)
        rows[index].endSeconds = Self.formatSecondsForEditing(nextEnd)
        clearTimelineValidation()
    }

    private func optionalTimelineSeconds(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Double(trimmed), seconds.isFinite else { return nil }
        return seconds
    }

    private func clearTimelineValidation() {
        editValidationIssues = []
    }

    private func applyEditorSettings(_ settings: EditorSettings) {
        let canvas = settings.canvas
        canvasAspectRatio = canvas.aspectRatio
        canvasCustomWidth = String(canvas.customSize?.width ?? 1920)
        canvasCustomHeight = String(canvas.customSize?.height ?? 1080)
        canvasBackgroundStyle = canvas.background.style
        canvasPrimaryColor = canvas.background.primaryColor
        canvasSecondaryColor = canvas.background.secondaryColor
        canvasBackgroundImagePath = canvas.background.imagePath ?? ""
        loadCanvasBackgroundImage()
        canvasPaddingRatio = canvas.paddingRatio
        canvasInsetRatio = canvas.insetRatio
        canvasCornerRadiusRatio = canvas.cornerRadiusRatio
        canvasShadowEnabled = canvas.shadow.isEnabled
        canvasShadowOpacity = canvas.shadow.opacity
        if let cropRect = canvas.cropRect {
            canvasCropEnabled = true
            canvasCropX = Self.formatNormalized(cropRect.x)
            canvasCropY = Self.formatNormalized(cropRect.y)
            canvasCropWidth = Self.formatNormalized(cropRect.width)
            canvasCropHeight = Self.formatNormalized(cropRect.height)
        } else {
            canvasCropEnabled = false
            canvasCropX = "0"
            canvasCropY = "0"
            canvasCropWidth = "1"
            canvasCropHeight = "1"
        }
        zoomAutoGenerationEnabled = settings.zoom?.automaticClickZoomsEnabled ?? true
        let cursor = settings.cursor ?? EditorCursorSettings()
        cursorPointerStyle = cursor.pointerStyle
        cursorPointerVisible = cursor.pointerVisible
        cursorSmoothMovement = cursor.smoothMovement
        cursorPointerScale = cursor.pointerScale
        cursorPointerFillColor = cursor.pointerFillColor
        cursorPointerStrokeColor = cursor.pointerStrokeColor
        cursorClickEffectsVisible = cursor.clickEffects.rippleVisible
        cursorClickColor = cursor.clickEffects.color
        cursorClickScale = cursor.clickEffects.scale
        cursorClickOpacity = cursor.clickEffects.opacity
        cursorClickDuration = cursor.clickEffects.durationSeconds
        cursorClickSoundEnabled = cursor.clickEffects.soundEnabled
        cursorClickSoundVolume = cursor.clickEffects.soundVolume
        cursorKeyboardVisible = cursor.keyboardOverlay.isVisible
        cursorKeyboardOpacity = cursor.keyboardOverlay.opacity
        cursorHiddenRangeRows = cursor.hiddenRanges.enumerated().map { index, range in
            EditableTimeRangeRow(
                id: "cursor-hide-\(index)-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(range.startSeconds),
                endSeconds: Self.formatSecondsForEditing(range.endSeconds)
            )
        }
        let camera = settings.camera ?? EditorCameraSettings()
        cameraCorner = camera.defaultPlacement.corner
        cameraWidthRatio = Self.formatNormalized(camera.defaultPlacement.widthRatio)
        cameraMarginRatio = Self.formatNormalized(camera.defaultPlacement.marginRatio)
        cameraAspectRatio = camera.defaultPlacement.aspectRatio
        cameraFrameShape = camera.defaultPlacement.frameShape
        cameraCornerRadius = Self.formatSecondsForEditing(camera.defaultPlacement.cornerRadius)
        cameraMirrored = camera.defaultPlacement.isMirrored
        cameraBorderEnabled = camera.defaultPlacement.borderEnabled
        cameraShadowEnabled = camera.defaultPlacement.shadowEnabled
        cameraRegionRows = camera.layoutRegions.map(Self.editableCameraRegionRow(from:))
        cameraReactionRows = camera.reactions.map(Self.editableCameraReactionRow(from:))
        let audio = settings.audio ?? EditorAudioSettings()
        screenAudioGain = Self.formatSecondsForEditing(audio.screenAudio.gain)
        screenAudioMuted = audio.screenAudio.isMuted
        screenAudioSoloed = audio.screenAudio.isSoloed
        microphoneAudioGain = Self.formatSecondsForEditing(audio.microphoneAudio.gain)
        microphoneAudioMuted = audio.microphoneAudio.isMuted
        microphoneAudioSoloed = audio.microphoneAudio.isSoloed
        systemAudioGain = Self.formatSecondsForEditing(audio.systemAudio.gain)
        systemAudioMuted = audio.systemAudio.isMuted
        systemAudioSoloed = audio.systemAudio.isSoloed
        if let music = audio.backgroundMusic {
            backgroundMusicPath = music.relativePath
            backgroundMusicStart = Self.formatSecondsForEditing(music.startSeconds)
            backgroundMusicSourceStart = Self.formatSecondsForEditing(music.sourceStartSeconds)
            backgroundMusicDuration = music.durationSeconds.map(Self.formatSecondsForEditing) ?? ""
            backgroundMusicGain = Self.formatSecondsForEditing(music.gain)
            backgroundMusicLoop = music.loop
            backgroundMusicDuckUnderVoice = music.duckUnderVoice
            backgroundMusicDuckedGain = Self.formatSecondsForEditing(music.duckedGain)
            backgroundMusicFadeIn = Self.formatSecondsForEditing(music.fadeInSeconds)
            backgroundMusicFadeOut = Self.formatSecondsForEditing(music.fadeOutSeconds)
        } else {
            backgroundMusicPath = ""
            backgroundMusicStart = "0"
            backgroundMusicSourceStart = "0"
            backgroundMusicDuration = ""
            backgroundMusicGain = "0.28"
            backgroundMusicLoop = true
            backgroundMusicDuckUnderVoice = true
            backgroundMusicDuckedGain = "0.12"
            backgroundMusicFadeIn = "0.5"
            backgroundMusicFadeOut = "0.5"
        }
        audioVolumeRows = audio.volumeRegions.map(Self.editableAudioVolumeRegionRow(from:))
        let captions = settings.captions ?? EditorCaptionSettings()
        captionBurnInEnabled = captions.burnInEnabled
        captionPlacement = captions.placement
        captionFontName = captions.fontName
        captionFontSize = Self.formatSecondsForEditing(captions.fontSize)
        captionTextColor = captions.textColor
        captionBackgroundColor = captions.backgroundColor
        captionMaxLineCount = captions.maxLineCount
        captionSafeMargin = Self.formatNormalized(captions.safeMarginRatio)
    }

    private func currentEditorSettings() throws -> EditorSettings {
        let customSize: EditorCanvasCustomSize?
        if canvasAspectRatio == .custom {
            customSize = EditorCanvasCustomSize(
                width: try parseDimension(canvasCustomWidth, label: "Canvas width"),
                height: try parseDimension(canvasCustomHeight, label: "Canvas height")
            )
        } else {
            customSize = nil
        }

        let backgroundImagePath: String?
        if canvasBackgroundStyle == .image {
            let imagePath = canvasBackgroundImagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !imagePath.isEmpty else {
                throw ProjectEditorError.invalidMetadata("Choose a canvas background image or select a different background mode.")
            }
            backgroundImagePath = imagePath
        } else {
            backgroundImagePath = nil
        }

        let cropRect: NormalizedEditRect?
        if canvasCropEnabled {
            let x = try parseUnitInterval(canvasCropX, label: "Crop X")
            let y = try parseUnitInterval(canvasCropY, label: "Crop Y")
            let width = try parseUnitInterval(canvasCropWidth, label: "Crop width")
            let height = try parseUnitInterval(canvasCropHeight, label: "Crop height")
            guard width > 0, height > 0 else {
                throw ProjectEditorError.invalidNumber("Crop width and height must be greater than zero.")
            }
            guard x + width <= 1, y + height <= 1 else {
                throw ProjectEditorError.invalidNumber("Crop rectangle must fit inside the source video.")
            }
            cropRect = NormalizedEditRect(x: x, y: y, width: width, height: height)
        } else {
            cropRect = nil
        }

        let cursorHiddenRanges = try cursorHiddenRangeRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Cursor hide start")
            let end = try parseSeconds(row.endSeconds, label: "Cursor hide end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Cursor hide end must be greater than cursor hide start.")
            }
            return EditTimeRange(startSeconds: start, endSeconds: end)
        }

        let cameraRegions = try cameraRegionRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Camera region start")
            let end = try parseSeconds(row.endSeconds, label: "Camera region end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Camera region end must be greater than camera region start.")
            }
            return CameraLayoutRegion(
                id: row.id,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                preset: row.preset,
                placement: row.preset == .custom ? try cameraPlacementFromFields() : nil,
                animation: row.layoutAnimation,
                transitionSeconds: try parseNonNegative(row.transitionSeconds, label: "Camera transition"),
                isEnabled: row.isEnabled
            )
        }
        let cameraReactions = try cameraReactionRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Camera reaction start")
            let end = try parseSeconds(row.endSeconds, label: "Camera reaction end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Camera reaction end must be greater than camera reaction start.")
            }
            return CameraReaction(
                id: row.id,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                text: row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "👍" : row.text,
                isEnabled: row.isEnabled
            )
        }

        let backgroundMusic: EditorBackgroundMusicSettings?
        let musicPath = backgroundMusicPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if musicPath.isEmpty {
            backgroundMusic = nil
        } else {
            backgroundMusic = EditorBackgroundMusicSettings(
                relativePath: musicPath,
                startSeconds: try parseSeconds(backgroundMusicStart, label: "Music start"),
                sourceStartSeconds: try parseSeconds(backgroundMusicSourceStart, label: "Music source start"),
                durationSeconds: try optionalSeconds(backgroundMusicDuration, label: "Music duration"),
                gain: try parseNonNegative(backgroundMusicGain, label: "Music gain"),
                loop: backgroundMusicLoop,
                duckUnderVoice: backgroundMusicDuckUnderVoice,
                duckedGain: try parseNonNegative(backgroundMusicDuckedGain, label: "Ducked music gain"),
                fadeInSeconds: try parseNonNegative(backgroundMusicFadeIn, label: "Music fade in"),
                fadeOutSeconds: try parseNonNegative(backgroundMusicFadeOut, label: "Music fade out")
            )
        }

        let audioVolumeRegions = try audioVolumeRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Volume region start")
            let end = try parseSeconds(row.endSeconds, label: "Volume region end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Volume region end must be greater than volume region start.")
            }
            return EditorAudioVolumeRegion(
                id: row.id,
                track: row.track,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                gain: try parseNonNegative(row.gain, label: "Volume region gain"),
                fadeInSeconds: try parseNonNegative(row.fadeInSeconds, label: "Volume region fade in"),
                fadeOutSeconds: try parseNonNegative(row.fadeOutSeconds, label: "Volume region fade out"),
                isEnabled: row.isEnabled
            )
        }

        return EditorSettings(
            canvas: EditorCanvasSettings(
                aspectRatio: canvasAspectRatio,
                background: EditorCanvasBackground(
                    style: canvasBackgroundStyle,
                    primaryColor: canvasPrimaryColor,
                    secondaryColor: canvasSecondaryColor,
                    imagePath: backgroundImagePath
                ),
                paddingRatio: canvasPaddingRatio,
                insetRatio: canvasInsetRatio,
                cornerRadiusRatio: canvasCornerRadiusRatio,
                shadow: EditorCanvasShadow(
                    isEnabled: canvasShadowEnabled,
                    opacity: canvasShadowOpacity
                ),
                cropRect: cropRect,
                customSize: customSize
            ),
            zoom: EditorZoomSettings(automaticClickZoomsEnabled: zoomAutoGenerationEnabled),
            cursor: EditorCursorSettings(
                pointerStyle: cursorPointerStyle,
                pointerVisible: cursorPointerVisible,
                smoothMovement: cursorSmoothMovement,
                pointerScale: cursorPointerScale,
                pointerFillColor: cursorPointerFillColor,
                pointerStrokeColor: cursorPointerStrokeColor,
                hiddenRanges: cursorHiddenRanges,
                clickEffects: EditorClickEffectSettings(
                    rippleVisible: cursorClickEffectsVisible,
                    color: cursorClickColor,
                    scale: cursorClickScale,
                    opacity: cursorClickOpacity,
                    durationSeconds: cursorClickDuration,
                    soundEnabled: cursorClickSoundEnabled,
                    soundVolume: cursorClickSoundVolume
                ),
                keyboardOverlay: EditorKeyboardOverlaySettings(
                    isVisible: cursorKeyboardVisible,
                    opacity: cursorKeyboardOpacity
                )
            ),
            camera: EditorCameraSettings(
                defaultPlacement: try cameraPlacementFromFields(),
                layoutRegions: cameraRegions,
                reactions: cameraReactions
            ),
            audio: EditorAudioSettings(
                screenAudio: EditorAudioTrackSettings(
                    gain: try parseNonNegative(screenAudioGain, label: "Screen audio gain"),
                    isMuted: screenAudioMuted,
                    isSoloed: screenAudioSoloed
                ),
                microphoneAudio: EditorAudioTrackSettings(
                    gain: try parseNonNegative(microphoneAudioGain, label: "Microphone audio gain"),
                    isMuted: microphoneAudioMuted,
                    isSoloed: microphoneAudioSoloed
                ),
                systemAudio: EditorAudioTrackSettings(
                    gain: try parseNonNegative(systemAudioGain, label: "System audio gain"),
                    isMuted: systemAudioMuted,
                    isSoloed: systemAudioSoloed
                ),
                backgroundMusic: backgroundMusic,
                volumeRegions: audioVolumeRegions
            ),
            captions: EditorCaptionSettings(
                burnInEnabled: captionBurnInEnabled,
                placement: captionPlacement,
                fontName: captionFontName,
                fontSize: try parsePositive(captionFontSize, label: "Caption font size"),
                textColor: captionTextColor,
                backgroundColor: captionBackgroundColor,
                maxLineCount: captionMaxLineCount,
                safeMarginRatio: try parseUnitInterval(captionSafeMargin, label: "Caption safe margin")
            )
        )
    }

    private func cameraPlacementFromFields() throws -> PictureInPicturePlacement {
        PictureInPicturePlacement(
            corner: cameraCorner,
            widthRatio: try parseUnitInterval(cameraWidthRatio, label: "Camera size"),
            marginRatio: try parseUnitInterval(cameraMarginRatio, label: "Camera margin"),
            aspectRatio: cameraAspectRatio,
            frameShape: cameraFrameShape,
            cornerRadius: try parseNonNegative(cameraCornerRadius, label: "Camera corners"),
            isMirrored: cameraMirrored,
            borderEnabled: cameraBorderEnabled,
            shadowEnabled: cameraShadowEnabled
        )
    }

    private func loadCanvasBackgroundImage() {
        guard let projectURL, !canvasBackgroundImagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            canvasBackgroundImage = nil
            return
        }
        let imageURL = ProjectBundle.fileURL(
            for: ProjectFile(relativePath: canvasBackgroundImagePath, role: .attachment),
            in: projectURL
        )
        canvasBackgroundImage = NSImage(contentsOf: imageURL)
    }

    private func loadMetadataFields(_ metadata: LessonMetadata) {
        metadataLessonTitle = metadata.lessonTitle
        metadataCourseTitle = metadata.courseTitle ?? ""
        metadataModuleTitle = metadata.moduleTitle ?? ""
        metadataInstructor = metadata.instructor ?? ""
        metadataSummary = metadata.summary ?? ""
        metadataTags = metadata.tags.joined(separator: ", ")
    }

    private func loadMarkerRows(_ markers: [ProjectTimelineMarker]) {
        markerRows = markers
            .sorted { first, second in
                if first.timeSeconds == second.timeSeconds {
                    return first.title.localizedStandardCompare(second.title) == .orderedAscending
                }
                return first.timeSeconds < second.timeSeconds
            }
            .map { marker in
                EditableMarkerRow(
                    id: marker.id,
                    kind: marker.kind,
                    timeSeconds: Self.formatSecondsForEditing(marker.timeSeconds),
                    title: marker.title,
                    notes: marker.notes ?? ""
                )
            }
    }

    private func loadAnnotationStatus(projectURL: URL, manifest: ProjectManifest) {
        do {
            guard let annotations = manifest.media.annotations else {
                annotationItemCount = 0
                annotationSidecarStatus = "Not initialized"
                return
            }

            let url = ProjectBundle.fileURL(for: annotations, in: projectURL)
            guard FileManager.default.fileExists(atPath: url.path) else {
                annotationItemCount = 0
                annotationSidecarStatus = "Missing file"
                return
            }

            let store = try loadAnnotationStore(at: url)
            annotationItemCount = store.annotations.count
            annotationSidecarStatus = store.isLocked ? "Locked" : "Ready"
        } catch {
            annotationItemCount = 0
            annotationSidecarStatus = "Unreadable: \(error.localizedDescription)"
        }
    }

    private func annotationStoreURL(
        projectURL: URL,
        manifest: ProjectManifest,
        createIfMissing: Bool
    ) throws -> URL {
        let url = manifest.media.annotations
            .map { ProjectBundle.fileURL(for: $0, in: projectURL) }
            ?? projectURL.appendingPathComponent("annotations.json")

        if createIfMissing, !FileManager.default.fileExists(atPath: url.path) {
            try writeAnnotationStore(AnnotationStore(), to: url)
        }
        return url
    }

    private func loadAnnotationStore(at url: URL) throws -> AnnotationStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AnnotationStore()
        }
        let data = try Data(contentsOf: url)
        return try DMLessonJSON.decoder().decode(AnnotationStore.self, from: data)
    }

    private func writeAnnotationStore(_ store: AnnotationStore, to url: URL) throws {
        try AnnotationSidecarWriter.write(store, to: url)
    }

    private func makeOverlayStore() throws -> OverlayStore {
        let overlays = try overlayRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Overlay start")
            let end = try parseSeconds(row.endSeconds, label: "Overlay end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Overlay end must be greater than overlay start.")
            }
            let x = try parseUnitInterval(row.x, label: "Overlay X")
            let y = try parseUnitInterval(row.y, label: "Overlay Y")
            let width = try parseUnitInterval(row.width, label: "Overlay width")
            let height = try parseUnitInterval(row.height, label: "Overlay height")
            guard width > 0, height > 0 else {
                throw ProjectEditorError.invalidNumber("Overlay width and height must be greater than zero.")
            }
            guard x + width <= 1, y + height <= 1 else {
                throw ProjectEditorError.invalidNumber("Overlay frame must fit inside the preview.")
            }
            let imagePath = row.imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if row.kind == .image, imagePath.isEmpty {
                throw ProjectEditorError.invalidMetadata("Image overlays need a selected image.")
            }
            let opacity = try parseUnitInterval(row.opacity, label: "Overlay opacity")
            let fontSize = try parsePositive(row.fontSize, label: "Overlay text size")
            let fadeIn = try parseNonNegative(row.fadeInSeconds, label: "Overlay fade in")
            let fadeOut = try parseNonNegative(row.fadeOutSeconds, label: "Overlay fade out")
            let cornerRadius = try parseNonNegative(row.cornerRadius, label: "Overlay corners")
            let blurRadius = try parseNonNegative(row.blurRadius, label: "Overlay blur")
            let featherRadius = try parseNonNegative(row.featherRadius, label: "Overlay feather")
            return OverlayItem(
                id: row.id,
                kind: row.kind,
                timeRange: EditTimeRange(startSeconds: start, endSeconds: end),
                frame: NormalizedEditRect(x: x, y: y, width: width, height: height),
                opacity: opacity,
                zIndex: row.zIndex,
                style: OverlayStyle(
                    text: row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? row.kind.title : row.text,
                    fontSize: fontSize,
                    textColor: row.textColor,
                    fillColor: (row.kind == .rectangle || row.kind == .ellipse) ? row.fillColor : nil,
                    strokeColor: row.strokeColor,
                    backgroundColor: (row.kind == .text || row.kind == .callout) ? row.fillColor : nil,
                    cornerRadius: cornerRadius,
                    shadowEnabled: row.kind != .highlight,
                    imagePath: imagePath.isEmpty ? nil : imagePath,
                    highlightMode: row.kind == .highlight ? row.highlightMode : nil,
                    highlightShape: row.kind == .highlight ? row.highlightShape : nil,
                    blurRadius: row.kind == .highlight ? blurRadius : nil,
                    featherRadius: row.kind == .highlight ? featherRadius : nil
                ),
                animation: OverlayAnimation(
                    fadeInSeconds: fadeIn,
                    fadeOutSeconds: fadeOut,
                    preset: row.animationPreset
                ),
                isEnabled: row.isEnabled
            )
        }
        return OverlayStore(overlays: overlays)
    }

    private func makeTranscriptDocument() throws -> TranscriptDocument {
        let segments = try captionRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Caption start")
            let end = try parseSeconds(row.endSeconds, label: "Caption end")
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Caption end must be greater than caption start.")
            }
            guard !text.isEmpty else {
                throw ProjectEditorError.invalidMetadata("Caption text is required.")
            }
            return TranscriptSegment(
                id: row.id,
                startSeconds: start,
                endSeconds: end,
                text: text
            )
        }
        .sorted { $0.startSeconds < $1.startSeconds }
        return TranscriptDocument(title: metadataLessonTitle.trimmingCharacters(in: .whitespacesAndNewlines), segments: segments)
    }

    private func writeCaptionSidecars(_ transcript: TranscriptDocument, projectURL: URL) throws {
        _ = try QuickRecordingCompletionExporter.writeProjectCaptionSidecars(
            transcript: transcript,
            projectURL: projectURL
        )
    }

    private func attachOverlayStore(projectURL: URL) throws -> ProjectManifest {
        try ProjectBundle.updateManifest(at: projectURL) { manifest in
            let storeURL = OverlayStoreFile.url(inProject: projectURL)
            manifest.media.overlays = Self.projectFile(
                for: storeURL,
                role: .overlays,
                projectURL: projectURL,
                mimeType: "application/json"
            )
            if !manifest.tracks.contains(where: { $0.id == "overlays" }) {
                manifest.tracks.append(TimelineTrack(id: "overlays", kind: .overlays, displayName: "Overlays"))
            }
        }
    }

    private func attachCaptionSidecars(projectURL: URL) throws -> ProjectManifest {
        try ProjectBundle.updateManifest(at: projectURL) { manifest in
            manifest.media.transcripts.removeAll { ["transcript.json", "transcript.txt"].contains($0.relativePath) }
            manifest.media.transcripts.append(Self.projectFile(
                for: projectURL.appendingPathComponent("transcript.json"),
                role: .transcript,
                projectURL: projectURL,
                mimeType: "application/json"
            ))
            manifest.media.transcripts.append(Self.projectFile(
                for: projectURL.appendingPathComponent("transcript.txt"),
                role: .transcript,
                projectURL: projectURL,
                mimeType: "text/plain"
            ))
            manifest.media.captions.removeAll { ["captions.vtt", "captions.srt"].contains($0.relativePath) }
            manifest.media.captions.append(Self.projectFile(
                for: projectURL.appendingPathComponent("captions.vtt"),
                role: .captions,
                projectURL: projectURL,
                mimeType: "text/vtt"
            ))
            manifest.media.captions.append(Self.projectFile(
                for: projectURL.appendingPathComponent("captions.srt"),
                role: .captions,
                projectURL: projectURL,
                mimeType: "application/x-subrip"
            ))
            if !manifest.tracks.contains(where: { $0.id == "captions" }) {
                manifest.tracks.append(TimelineTrack(id: "captions", kind: .captions, displayName: "Captions"))
            }
        }
    }

    private func attachAnnotationStore(projectURL: URL, storeURL: URL) throws -> ProjectManifest {
        try ProjectBundle.updateManifest(at: projectURL) { manifest in
            manifest.media.annotations = Self.projectFile(for: storeURL, role: .annotations, projectURL: projectURL, mimeType: "application/json")
            if !manifest.tracks.contains(where: { $0.id == "annotations" }) {
                manifest.tracks.append(TimelineTrack(id: "annotations", kind: .annotations, displayName: "Annotations"))
            }
        }
    }

    private static func projectFile(
        for url: URL,
        role: ProjectFileRole,
        projectURL: URL,
        mimeType: String? = nil
    ) -> ProjectFile {
        let projectPath = projectURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let relativePath: String
        if filePath.hasPrefix(projectPath + "/") {
            relativePath = String(filePath.dropFirst(projectPath.count + 1))
        } else {
            relativePath = filePath
        }
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? NSNumber)?.int64Value
        return ProjectFile(relativePath: relativePath, role: role, mimeType: mimeType, byteCount: byteCount)
    }

    private func defaultEditDecisionList(projectURL: URL, manifest: ProjectManifest) -> EditDecisionList {
        EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: manifest.media.screen.map { ProjectBundle.fileURL(for: $0, in: projectURL) },
            sourceDurationSeconds: previewDurationSeconds > 0 ? previewDurationSeconds : nil,
            markers: manifest.markers.map { marker in
                TimelineMarker(
                    id: marker.id,
                    kind: editMarkerKind(for: marker.kind),
                    timeSeconds: marker.timeSeconds,
                    title: marker.title,
                    notes: marker.notes
                )
            }
        )
    }

    private func makeEditDecisionList(projectURL: URL, manifest: ProjectManifest) throws -> EditDecisionList {
        let duration = try optionalSeconds(sourceDurationSeconds, label: "Source duration")
            ?? (previewDurationSeconds > 0 ? previewDurationSeconds : nil)
        let trimStart = try optionalSeconds(trimStartSeconds, label: "Trim start")
        let trimEnd = try optionalSeconds(trimEndSeconds, label: "Trim end")
        let trimRange: EditTimeRange?
        if let trimStart, let trimEnd {
            guard trimEnd > trimStart else {
                throw ProjectEditorError.invalidNumber("Trim end must be greater than trim start.")
            }
            trimRange = EditTimeRange(startSeconds: trimStart, endSeconds: trimEnd)
        } else {
            trimRange = nil
        }

        let cuts = try cutRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Cut start")
            let end = try parseSeconds(row.endSeconds, label: "Cut end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Cut end must be greater than cut start.")
            }
            return TimelineCut(
                id: row.id,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                reason: row.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : row.reason,
                isEnabled: row.isEnabled
            )
        }

        let speedRegions = try speedRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Speed start")
            let end = try parseSeconds(row.endSeconds, label: "Speed end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Speed end must be greater than speed start.")
            }
            return SpeedRegion(
                id: row.id,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                playbackRate: try parsePositive(row.playbackRate, label: "Speed rate")
            )
        }

        let zoomRegions = try zoomRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Zoom start")
            let end = try parseSeconds(row.endSeconds, label: "Zoom end")
            let scale = try parsePositive(row.scale, label: "Zoom scale")
            let centerX = try parseUnitInterval(row.centerX, label: "Zoom X")
            let centerY = try parseUnitInterval(row.centerY, label: "Zoom Y")
            let size = try parseUnitInterval(row.size, label: "Zoom size")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Zoom end must be greater than zoom start.")
            }
            guard size > 0 else {
                throw ProjectEditorError.invalidNumber("Zoom size must be greater than zero.")
            }
            let halfSize = size / 2
            let normalizedCenterX = min(max(centerX, halfSize), 1 - halfSize)
            let normalizedCenterY = min(max(centerY, halfSize), 1 - halfSize)
            return ZoomRegion(
                id: row.id,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                focusRect: NormalizedEditRect(
                    x: normalizedCenterX - halfSize,
                    y: normalizedCenterY - halfSize,
                    width: size,
                    height: size
                ),
                scale: scale,
                isEnabled: row.isEnabled,
                focusMode: row.focusMode,
                easing: row.easing
            )
        }

        let existing = lastEditDecisionList ?? defaultEditDecisionList(projectURL: projectURL, manifest: manifest)
        return EditDecisionList(
            id: existing.id,
            sourceMediaURL: manifest.media.screen.map { ProjectBundle.fileURL(for: $0, in: projectURL) },
            sourceDurationSeconds: duration,
            trimRange: trimRange,
            cuts: cuts,
            speedRegions: speedRegions,
            zoomRegions: zoomRegions,
            markers: existing.markers
        )
    }

    private func editMarkerKind(for kind: ProjectTimelineMarkerKind) -> TimelineMarkerKind {
        switch kind {
        case .chapter:
            .chapter
        case .retake:
            .retake
        case .presenterNote, .segment:
            .note
        }
    }

    private func chooseDestination(defaultPath: String, fileType: RenderFileType, onChoose: (URL) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Choose Export Destination"
        panel.nameFieldStringValue = URL(fileURLWithPath: defaultPath).lastPathComponent
        if let contentType = UTType(filenameExtension: fileType.fileExtension) {
            panel.allowedContentTypes = [contentType]
        }
        panel.canCreateDirectories = true

        if !defaultPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: defaultPath).deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        onChoose(url)
    }

    private func chooseDirectory(defaultPath: String, title: String, onChoose: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        let trimmed = defaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onChoose(url)
    }

    private func chooseLessonPreset(title: String) throws -> LessonPreset? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let contentType = Self.lessonPresetContentType {
            panel.allowedContentTypes = [contentType]
        }
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return try LessonPresetFile.load(from: url)
    }

    private func refreshDefaultDestinations() {
        guard let projectURL else { return }
        let baseName = projectURL.deletingPathExtension().lastPathComponent
        let root = projectURL.deletingLastPathComponent()
        let fileExtension = renderFileType.fileExtension
        if renderDestinationPath.isEmpty || URL(fileURLWithPath: renderDestinationPath).pathExtension != fileExtension {
            renderDestinationPath = root.appendingPathComponent("\(baseName)-render.\(fileExtension)").path
        }
        if trimDestinationPath.isEmpty || URL(fileURLWithPath: trimDestinationPath).pathExtension != fileExtension {
            trimDestinationPath = root.appendingPathComponent("\(baseName)-trim.\(fileExtension)").path
        }
        if rawAssetDestinationPath.isEmpty {
            rawAssetDestinationPath = root.appendingPathComponent("Raw Assets", isDirectory: true).path
        }
        if sharePackageDestinationPath.isEmpty {
            sharePackageDestinationPath = root.appendingPathComponent("Lesson Shares", isDirectory: true).path
        }
        if shareFinalVideoPath.isEmpty {
            shareFinalVideoPath = renderDestinationPath
        }
    }

    private func destinationURL(path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectEditorError.invalidDestination
        }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
    }

    private func directoryURL(path: String, fallback: URL) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath, isDirectory: true)
    }

    private func optionalFileURL(path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
    }

    private static func expandedURL(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    private static func projectURLWithExtension(_ url: URL) -> URL {
        url.pathExtension.lowercased() == "dmlm" ? url : url.appendingPathExtension("dmlm")
    }

    private static func presetURLWithExtension(_ url: URL) -> URL {
        url.pathExtension.lowercased() == LessonPresetFile.fileExtension
            ? url
            : url.appendingPathExtension(LessonPresetFile.fileExtension)
    }

    private static var editableVideoContentTypes: [UTType] {
        [.mpeg4Movie, .quickTimeMovie]
    }

    private static var lessonPresetContentType: UTType? {
        UTType(filenameExtension: LessonPresetFile.fileExtension) ?? .json
    }

    private static var captionImportContentTypes: [UTType] {
        ["json", "vtt", "srt", "txt", "md"].compactMap { UTType(filenameExtension: $0) }
    }

    private static func presetPreviewSummary(_ preview: LessonPresetApplyPreview) -> String {
        [
            "Preset: \(preview.presetName)",
            "Writes editor settings: \(preview.writesEditorSettings ? "yes" : "no")",
            "Updates capture settings: \(preview.updatesCaptureSettings ? "yes" : "no")",
            "Updates export preset IDs: \(preview.updatesExportPresets ? "yes" : "no")",
            "Preserves: \(preview.preservedProjectFields.joined(separator: ", "))"
        ].joined(separator: "\n")
    }

    private static func imageMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        default: "image/png"
        }
    }

    private static func audioMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "m4a": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "caf": "audio/x-caf"
        default: "audio/*"
        }
    }

    private static func uniqueCanvasBackgroundURL(for sourceURL: URL, projectURL: URL) throws -> URL {
        let backgroundDirectory = projectURL.appendingPathComponent("backgrounds", isDirectory: true)
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let fileExtension = ["jpg", "jpeg", "png"].contains(sourceExtension) ? sourceExtension : "png"
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let destinationURL = backgroundDirectory.appendingPathComponent("canvas-background\(suffix).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
        }
        return backgroundDirectory.appendingPathComponent("canvas-background-\(UUID().uuidString.lowercased()).\(fileExtension)")
    }

    private static func uniqueOverlayAssetURL(for sourceURL: URL, projectURL: URL) throws -> URL {
        let assetDirectory = projectURL.appendingPathComponent("overlays/assets", isDirectory: true)
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let fileExtension = ["jpg", "jpeg", "png"].contains(sourceExtension) ? sourceExtension : "png"
        let baseName = fileSlug(sourceURL.deletingPathExtension().lastPathComponent)
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let destinationURL = assetDirectory.appendingPathComponent("\(baseName)\(suffix).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
        }
        return assetDirectory.appendingPathComponent("\(baseName)-\(UUID().uuidString.lowercased()).\(fileExtension)")
    }

    private static func uniqueAudioAssetURL(for sourceURL: URL, projectURL: URL) throws -> URL {
        let assetDirectory = projectURL.appendingPathComponent("audio/assets", isDirectory: true)
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let fileExtension = ["m4a", "mp3", "wav", "caf", "aiff", "aif"].contains(sourceExtension) ? sourceExtension : "m4a"
        let baseName = fileSlug(sourceURL.deletingPathExtension().lastPathComponent)
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let destinationURL = assetDirectory.appendingPathComponent("\(baseName)\(suffix).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
        }
        return assetDirectory.appendingPathComponent("\(baseName)-\(UUID().uuidString.lowercased()).\(fileExtension)")
    }

    private static var lessonProjectContentType: UTType? {
        UTType(filenameExtension: "dmlm")
    }

    private static func lessonTitle(from projectURL: URL) -> String {
        let title = projectURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled Lesson" : title
    }

    private static func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func tags(from value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func annotationColor(from hex: String) -> RGBAColor {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6, raw.allSatisfy({ $0.isHexDigit }), let value = UInt32(raw, radix: 16) else {
            return .yellow
        }
        return RGBAColor(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func projectHasZoomRegions(_ projectURL: URL) -> Bool {
        guard let editDecisionList = try? EditDecisionListFile.load(fromProject: projectURL) else {
            return false
        }
        return !editDecisionList.enabledZoomRegions.isEmpty
    }

    private static func captionSourceFile(in manifest: ProjectManifest) -> ProjectFile? {
        if let transcript = manifest.media.transcripts.first(where: {
            $0.mimeType == "application/json" || $0.relativePath.lowercased().hasSuffix(".json")
        }) {
            return transcript
        }
        if let caption = manifest.media.captions.first(where: {
            $0.mimeType == "application/json" || $0.relativePath.lowercased().hasSuffix(".json")
        }) {
            return caption
        }
        return manifest.media.captions.first ?? manifest.media.transcripts.first
    }

    private func parseSeconds(_ value: String, label: String) throws -> Double {
        guard let seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProjectEditorError.invalidNumber("\(label) must be a non-negative number.")
        }
        do {
            return try NumericInputValidation.nonNegativeSeconds(seconds, label: label)
        } catch {
            throw ProjectEditorError.invalidNumber(error.localizedDescription)
        }
    }

    private func parsePositive(_ value: String, label: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProjectEditorError.invalidNumber("\(label) must be a positive number.")
        }
        do {
            return try NumericInputValidation.positiveNumber(number, label: label)
        } catch {
            throw ProjectEditorError.invalidNumber(error.localizedDescription)
        }
    }

    private func parseNonNegative(_ value: String, label: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProjectEditorError.invalidNumber("\(label) must be a non-negative number.")
        }
        do {
            return try NumericInputValidation.nonNegativeNumber(number, label: label)
        } catch {
            throw ProjectEditorError.invalidNumber(error.localizedDescription)
        }
    }

    private func parseUnitInterval(_ value: String, label: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProjectEditorError.invalidNumber("\(label) must be between 0 and 1.")
        }
        do {
            return try NumericInputValidation.unitInterval(number, label: label)
        } catch {
            throw ProjectEditorError.invalidNumber(error.localizedDescription)
        }
    }

    private func parseDimension(_ value: String, label: String) throws -> Int {
        guard let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProjectEditorError.invalidNumber("\(label) must be from \(NumericInputValidation.minCanvasDimension) through \(NumericInputValidation.maxCanvasDimension) pixels.")
        }
        do {
            return try NumericInputValidation.canvasDimension(number, label: label)
        } catch {
            throw ProjectEditorError.invalidNumber(error.localizedDescription)
        }
    }

    private func optionalSeconds(_ value: String, label: String) throws -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try parseSeconds(trimmed, label: label)
    }

    private func defaultAnnotationEnd(after start: Double) -> Double {
        let fallback = start + 3
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? fallback)
        return max(min(fallback, duration), start + 0.5)
    }

    private static func formatSecondsForEditing(_ seconds: Double) -> String {
        if seconds.rounded() == seconds {
            return String(Int(seconds))
        }
        return String(format: "%.2f", seconds)
    }

    private static func formatNormalized(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func formatClock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let wholeSeconds = Int(seconds)
        let minutes = wholeSeconds / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, remainder)
    }

    private static func defaultOverlayRow(
        id: String = "overlay-\(UUID().uuidString)",
        kind: OverlayKind,
        start: Double,
        end: Double,
        zIndex: Int
    ) -> EditableOverlayRow {
        EditableOverlayRow(
            id: id,
            kind: kind,
            startSeconds: formatSecondsForEditing(start),
            endSeconds: formatSecondsForEditing(end),
            text: kind == .callout ? "Callout" : "Title",
            x: kind == .text ? "0.22" : (kind == .highlight ? "0.26" : "0.30"),
            y: kind == .text ? "0.12" : (kind == .highlight ? "0.28" : "0.30"),
            width: kind == .text ? "0.56" : (kind == .highlight ? "0.48" : "0.32"),
            height: kind == .text ? "0.14" : (kind == .highlight ? "0.28" : "0.20"),
            opacity: "1",
            fontSize: kind == .callout ? "28" : "34",
            fadeInSeconds: "0.18",
            fadeOutSeconds: "0.18",
            animationPreset: kind == .text ? .slideUp : .none,
            cornerRadius: kind == .highlight ? "18" : "12",
            highlightMode: .dim,
            highlightShape: .roundedRectangle,
            blurRadius: "12",
            featherRadius: "18",
            textColor: .white,
            fillColor: kind == .rectangle || kind == .ellipse ? .yellow : RGBAColor(red: 0.02, green: 0.02, blue: 0.025, alpha: kind == .highlight ? 0.58 : 0.68),
            strokeColor: .yellow,
            imagePath: "",
            zIndex: zIndex,
            isEnabled: true
        )
    }

    private static func editableOverlayRow(from overlay: OverlayItem) -> EditableOverlayRow {
        EditableOverlayRow(
            id: overlay.id,
            kind: overlay.kind,
            startSeconds: formatSecondsForEditing(overlay.timeRange.startSeconds),
            endSeconds: formatSecondsForEditing(overlay.timeRange.endSeconds),
            text: overlay.style.text,
            x: formatNormalized(overlay.frame.x),
            y: formatNormalized(overlay.frame.y),
            width: formatNormalized(overlay.frame.width),
            height: formatNormalized(overlay.frame.height),
            opacity: formatNormalized(overlay.opacity),
            fontSize: formatSecondsForEditing(overlay.style.fontSize),
            fadeInSeconds: formatSecondsForEditing(overlay.animation.fadeInSeconds),
            fadeOutSeconds: formatSecondsForEditing(overlay.animation.fadeOutSeconds),
            animationPreset: overlay.animation.preset,
            cornerRadius: formatSecondsForEditing(overlay.style.cornerRadius),
            highlightMode: overlay.style.highlightMode ?? .dim,
            highlightShape: overlay.style.highlightShape ?? .roundedRectangle,
            blurRadius: formatSecondsForEditing(overlay.style.blurRadius ?? 12),
            featherRadius: formatSecondsForEditing(overlay.style.featherRadius ?? 18),
            textColor: overlay.style.textColor,
            fillColor: overlay.style.backgroundColor ?? overlay.style.fillColor ?? .yellow,
            strokeColor: overlay.style.strokeColor,
            imagePath: overlay.style.imagePath ?? "",
            zIndex: overlay.zIndex,
            isEnabled: overlay.isEnabled
        )
    }

    private static func editableSpeedRow(from speed: SpeedRegion) -> EditableSpeedRow {
        EditableSpeedRow(
            id: speed.id,
            startSeconds: formatSecondsForEditing(speed.range.startSeconds),
            endSeconds: formatSecondsForEditing(speed.range.endSeconds),
            playbackRate: formatSecondsForEditing(speed.playbackRate)
        )
    }

    private static func editableAudioVolumeRegionRow(from region: EditorAudioVolumeRegion) -> EditableAudioVolumeRegionRow {
        EditableAudioVolumeRegionRow(
            id: region.id,
            track: region.track,
            startSeconds: formatSecondsForEditing(region.range.startSeconds),
            endSeconds: formatSecondsForEditing(region.range.endSeconds),
            gain: formatSecondsForEditing(region.gain),
            fadeInSeconds: formatSecondsForEditing(region.fadeInSeconds),
            fadeOutSeconds: formatSecondsForEditing(region.fadeOutSeconds),
            isEnabled: region.isEnabled
        )
    }

    private static func editableCaptionRow(from segment: TranscriptSegment) -> EditableCaptionRow {
        EditableCaptionRow(
            id: segment.id,
            startSeconds: formatSecondsForEditing(segment.startSeconds),
            endSeconds: formatSecondsForEditing(segment.endSeconds),
            text: segment.text
        )
    }

    private static func editableCameraRegionRow(from region: CameraLayoutRegion) -> EditableCameraRegionRow {
        EditableCameraRegionRow(
            id: region.id,
            startSeconds: formatSecondsForEditing(region.range.startSeconds),
            endSeconds: formatSecondsForEditing(region.range.endSeconds),
            preset: region.preset,
            layoutAnimation: region.animation,
            transitionSeconds: formatSecondsForEditing(region.transitionSeconds),
            isEnabled: region.isEnabled
        )
    }

    private static func editableCameraReactionRow(from reaction: CameraReaction) -> EditableCameraReactionRow {
        EditableCameraReactionRow(
            id: reaction.id,
            startSeconds: formatSecondsForEditing(reaction.range.startSeconds),
            endSeconds: formatSecondsForEditing(reaction.range.endSeconds),
            text: reaction.text,
            isEnabled: reaction.isEnabled
        )
    }

    private static func keyboardLabel(for event: KeyboardMetadataEvent) -> String {
        var parts: [String] = []
        if event.modifiers.contains(.control) {
            parts.append("Control")
        }
        if event.modifiers.contains(.option) {
            parts.append("Option")
        }
        if event.modifiers.contains(.shift) {
            parts.append("Shift")
        }
        if event.modifiers.contains(.command) {
            parts.append("Command")
        }

        let trimmedKey = event.characters?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let trimmedKey, !trimmedKey.isEmpty {
            parts.append(trimmedKey)
        } else {
            parts.append("Key \(event.keyCode)")
        }
        return parts.joined(separator: " + ")
    }

    private static func fileSlug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "lesson" : collapsed
    }

    private func setMessage(_ value: String) {
        message = SafePathDisplay.redactingAbsolutePaths(in: value)
        messageIsError = false
    }

    private func setError(_ value: String) {
        message = SafePathDisplay.redactingAbsolutePaths(in: value)
        messageIsError = true
    }

    func parseRegionValue(_ value: String, label: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), number >= 0 else {
            throw ProjectEditorError.invalidNumber("\(label) must be a non-negative number.")
        }
        return number
    }
}

extension PictureInPictureCorner {
    var title: String {
        switch self {
        case .topLeading: "Top Left"
        case .topTrailing: "Top Right"
        case .bottomLeading: "Bottom Left"
        case .bottomTrailing: "Bottom Right"
        }
    }
}

extension PictureInPictureAspectRatio {
    var title: String {
        switch self {
        case .original: "Original"
        case .square1x1: "1:1"
        case .portrait2x3: "2:3"
        case .landscape3x2: "3:2"
        case .widescreen16x9: "16:9"
        }
    }
}

extension PictureInPictureFrameShape {
    var title: String {
        switch self {
        case .roundedRectangle: "Rounded"
        case .square: "Square"
        case .circle: "Circle"
        }
    }
}

enum ProjectEditorError: Error, LocalizedError {
    case projectRequired
    case invalidDestination
    case invalidNumber(String)
    case invalidMetadata(String)
    case destinationExists(String)
    case editValidationFailed
    case templateNotFound(String)
    case frameExportFailed
    case unsupportedVideoType(String)

    var errorDescription: String? {
        switch self {
        case .projectRequired:
            "Open a project first."
        case .invalidDestination:
            "Choose an export destination."
        case .invalidNumber(let message):
            message
        case .invalidMetadata(let message):
            message
        case .destinationExists(let path):
            "Export destination already exists: \(path)"
        case .editValidationFailed:
            "Edit decisions have validation errors. Fix the cut or trim ranges before saving."
        case .templateNotFound(let id):
            "Lesson template was not found: \(id)"
        case .frameExportFailed:
            "Could not export the current preview frame."
        case .unsupportedVideoType(let fileName):
            "Choose an MP4 or MOV video file to import. Unsupported file: \(fileName)"
        }
    }
}
