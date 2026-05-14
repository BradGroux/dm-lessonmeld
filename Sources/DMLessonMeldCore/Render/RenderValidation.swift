import Foundation

public struct RenderValidationOptions: Codable, Equatable, Sendable {
    public var checkFileExistence: Bool
    public var checkDestinationDoesNotExist: Bool

    public init(checkFileExistence: Bool = false, checkDestinationDoesNotExist: Bool = false) {
        self.checkFileExistence = checkFileExistence
        self.checkDestinationDoesNotExist = checkDestinationDoesNotExist
    }

    public static let export = RenderValidationOptions(
        checkFileExistence: true,
        checkDestinationDoesNotExist: true
    )
}

public struct RenderValidationIssue: Codable, Equatable, Sendable {
    public var severity: Severity
    public var message: String
    public var path: String?

    public init(severity: Severity, message: String, path: String? = nil) {
        self.severity = severity
        self.message = message
        self.path = path
    }

    public enum Severity: String, Codable, Sendable {
        case warning
        case error
    }
}

public struct RenderValidationError: Error, Equatable, LocalizedError, Sendable {
    public var issues: [RenderValidationIssue]

    public init(issues: [RenderValidationIssue]) {
        self.issues = issues
    }

    public var errorDescription: String? {
        issues.map(\.message).joined(separator: " ")
    }
}

public enum RenderPlanValidator {
    public static func validate(
        _ plan: RenderPlan,
        options: RenderValidationOptions = RenderValidationOptions(),
        fileManager: FileManager = .default
    ) -> [RenderValidationIssue] {
        var issues: [RenderValidationIssue] = []

        if plan.screenVideo.relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Screen video path is required."
            ))
        }

        if !plan.destinationURL.isFileURL {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Render destination must be a local file URL.",
                path: plan.destinationURL.path
            ))
        }

        let expectedExtension = plan.preset.fileType.fileExtension
        if plan.destinationURL.pathExtension.lowercased() != expectedExtension {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Render destination extension must match \(expectedExtension).",
                path: plan.destinationURL.path
            ))
        }

        validatePreset(plan.preset, issues: &issues)
        if plan.webcamOverlay != nil {
            validatePictureInPicture(plan.webcamOverlay!.placement, issues: &issues)
        }

        validateZoomRegions(plan.zoomRegions, issues: &issues)
        validateSpeedRegions(plan.speedRegions, issues: &issues)
        validateCameraSettings(plan.camera, issues: &issues)
        validateAudioSettings(plan.audio, projectURL: plan.projectURL, issues: &issues, fileManager: fileManager, checkFileExistence: options.checkFileExistence)
        validateCaptionSettings(plan.captions, issues: &issues)
        if let annotationSource = plan.annotationSource {
            validateAnnotations(annotationSource, issues: &issues, fileManager: fileManager)
        }
        if let captionSource = plan.captionSource {
            validateCaptions(captionSource, issues: &issues, fileManager: fileManager)
        }
        if let overlaySource = plan.overlaySource {
            validateOverlays(overlaySource, projectURL: plan.projectURL, issues: &issues, fileManager: fileManager)
        }

        if options.checkFileExistence {
            for source in plan.requiredMediaSources {
                if !fileManager.fileExists(atPath: source.url.path) {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "\(source.role.rawValue) file is missing.",
                        path: source.relativePath
                    ))
                }
            }
        }

        if options.checkDestinationDoesNotExist, fileManager.fileExists(atPath: plan.destinationURL.path) {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Render destination already exists.",
                path: plan.destinationURL.path
            ))
        }

        return issues
    }

    private static func validatePreset(_ preset: RenderPreset, issues: inout [RenderValidationIssue]) {
        if preset.maxConcurrentExports < 1 || preset.maxConcurrentExports > 8 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Render concurrency must be between 1 and 8.",
                path: "preset.maxConcurrentExports"
            ))
        }

        if preset.resolution != .source {
            issues.append(RenderValidationIssue(
                severity: .warning,
                message: "Resolution override is recorded in the render plan, but the current renderer still uses source or canvas sizing.",
                path: "preset.resolution"
            ))
        }

        if preset.frameRate != .source {
            issues.append(RenderValidationIssue(
                severity: .warning,
                message: "Frame-rate override is recorded in the render plan, but the current renderer still uses source timing.",
                path: "preset.frameRate"
            ))
        }

        if preset.codec == .hevc {
            issues.append(RenderValidationIssue(
                severity: .warning,
                message: "HEVC codec selection is recorded in the render plan, but AVFoundation currently chooses the concrete codec from the export preset.",
                path: "preset.codec"
            ))
        }

        if !preset.hardwareAccelerationEnabled || preset.maxConcurrentExports > 1 {
            issues.append(RenderValidationIssue(
                severity: .warning,
                message: "Performance controls are recorded in the render plan for export queues, but the current single-render path may not use every setting.",
                path: "preset"
            ))
        }

        if preset.codec == .proRes || preset.proResEnabled {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "ProRes export is not implemented yet.",
                path: "preset.codec"
            ))
        }

        if preset.alphaChannelEnabled {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Alpha-channel export is not implemented yet.",
                path: "preset.alphaChannelEnabled"
            ))
        }

        if preset.animatedGIFEnabled {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Animated GIF export is not implemented yet.",
                path: "preset.animatedGIFEnabled"
            ))
        }
    }

    private static func validatePictureInPicture(
        _ placement: PictureInPicturePlacement,
        issues: inout [RenderValidationIssue]
    ) {
        if placement.widthRatio <= 0 || placement.widthRatio >= 1 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Picture-in-picture width ratio must be greater than 0 and less than 1."
            ))
        }

        if placement.marginRatio < 0 || placement.marginRatio >= 0.5 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Picture-in-picture margin ratio must be greater than or equal to 0 and less than 0.5."
            ))
        }
    }

    private static func validateZoomRegions(
        _ zoomRegions: [ZoomRegion],
        issues: inout [RenderValidationIssue]
    ) {
        for (index, region) in zoomRegions.enumerated() {
            let path = "zoomRegions[\(index)]"
            if !region.range.startSeconds.isFinite ||
                !region.range.durationSeconds.isFinite ||
                region.range.startSeconds < 0 ||
                region.range.durationSeconds <= 0 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Zoom region range must be finite and positive.",
                    path: "\(path).range"
                ))
            }

            if !region.scale.isFinite || region.scale <= 1 || region.scale > 6 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Zoom scale must be finite, greater than 1, and no more than 6.",
                    path: "\(path).scale"
                ))
            }

            if region.focusRect.width <= 0 ||
                region.focusRect.height <= 0 ||
                region.focusRect.x + region.focusRect.width > 1 ||
                region.focusRect.y + region.focusRect.height > 1 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Zoom focus rect must have positive size and stay inside the normalized frame.",
                    path: "\(path).focusRect"
                ))
            }
        }
    }

    private static func validateSpeedRegions(
        _ speedRegions: [SpeedRegion],
        issues: inout [RenderValidationIssue]
    ) {
        for (index, region) in speedRegions.enumerated() {
            let path = "speedRegions[\(index)]"
            if !region.range.startSeconds.isFinite ||
                !region.range.durationSeconds.isFinite ||
                region.range.startSeconds < 0 ||
                region.range.durationSeconds <= 0 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Speed region range must be finite, non-negative, and positive.",
                    path: "\(path).range"
                ))
            }

            if !region.playbackRate.isFinite || region.playbackRate <= 0 || region.playbackRate > 8 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Speed region rate must be finite, greater than 0, and no more than 8x.",
                    path: "\(path).playbackRate"
                ))
            }

            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Speed regions are saved in the editor, but full render retiming is not supported yet. Remove speed regions before export.",
                path: path
            ))
        }
    }

    private static func validateCameraSettings(
        _ camera: EditorCameraSettings,
        issues: inout [RenderValidationIssue]
    ) {
        validatePictureInPicture(camera.defaultPlacement, issues: &issues)
        for (index, region) in camera.layoutRegions.enumerated() {
            let path = "camera.layoutRegions[\(index)]"
            if !region.range.startSeconds.isFinite ||
                !region.range.durationSeconds.isFinite ||
                region.range.startSeconds < 0 ||
                region.range.durationSeconds <= 0 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Camera layout region range must be finite, non-negative, and positive.",
                    path: "\(path).range"
                ))
            }
            if !region.transitionSeconds.isFinite || region.transitionSeconds < 0 || region.transitionSeconds > 2 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Camera layout transition must be finite and between 0 and 2 seconds.",
                    path: "\(path).transitionSeconds"
                ))
            }
            if let placement = region.placement {
                validatePictureInPicture(placement, issues: &issues)
            }
        }
        for (index, reaction) in camera.reactions.enumerated() {
            let path = "camera.reactions[\(index)]"
            if !reaction.range.startSeconds.isFinite ||
                !reaction.range.durationSeconds.isFinite ||
                reaction.range.startSeconds < 0 ||
                reaction.range.durationSeconds <= 0 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Camera reaction range must be finite, non-negative, and positive.",
                    path: "\(path).range"
                ))
            }
            if reaction.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Camera reaction text is required.",
                    path: "\(path).text"
                ))
            }
        }
    }

    private static func validateAudioSettings(
        _ audio: EditorAudioSettings,
        projectURL: URL,
        issues: inout [RenderValidationIssue],
        fileManager: FileManager,
        checkFileExistence: Bool
    ) {
        let trackSettings: [(String, EditorAudioTrackSettings)] = [
            ("audio.screenAudio", audio.screenAudio),
            ("audio.microphoneAudio", audio.microphoneAudio),
            ("audio.systemAudio", audio.systemAudio)
        ]
        for (path, settings) in trackSettings {
            validateGain(settings.gain, path: "\(path).gain", issues: &issues)
        }

        for (index, region) in audio.volumeRegions.enumerated() {
            let path = "audio.volumeRegions[\(index)]"
            validateRange(region.range, path: "\(path).range", issues: &issues, messagePrefix: "Audio volume region")
            validateGain(region.gain, path: "\(path).gain", issues: &issues)
            validateFiniteNonNegative(region.fadeInSeconds, path: "\(path).fadeInSeconds", issues: &issues)
            validateFiniteNonNegative(region.fadeOutSeconds, path: "\(path).fadeOutSeconds", issues: &issues)
        }

        guard let backgroundMusic = audio.backgroundMusic else { return }
        let musicPath = backgroundMusic.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if musicPath.isEmpty {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Background music path is required.",
                path: "audio.backgroundMusic.relativePath"
            ))
        } else {
            do {
                let musicURL = try ProjectBundle.projectLocalFileURL(
                    for: ProjectFile(relativePath: musicPath, role: .attachment),
                    in: projectURL
                )
                if checkFileExistence, !fileManager.fileExists(atPath: musicURL.path) {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "Background music file is missing.",
                        path: musicPath
                    ))
                }
            } catch {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Background music must be a project-local relative path.",
                    path: musicPath
                ))
            }
        }
        validateGain(backgroundMusic.gain, path: "audio.backgroundMusic.gain", issues: &issues)
        validateGain(backgroundMusic.duckedGain, path: "audio.backgroundMusic.duckedGain", issues: &issues)
        validateFiniteNonNegative(backgroundMusic.startSeconds, path: "audio.backgroundMusic.startSeconds", issues: &issues)
        validateFiniteNonNegative(backgroundMusic.sourceStartSeconds, path: "audio.backgroundMusic.sourceStartSeconds", issues: &issues)
        if let durationSeconds = backgroundMusic.durationSeconds,
           (!durationSeconds.isFinite || durationSeconds <= 0) {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Background music duration must be finite and positive.",
                path: "audio.backgroundMusic.durationSeconds"
            ))
        }
        validateFiniteNonNegative(backgroundMusic.fadeInSeconds, path: "audio.backgroundMusic.fadeInSeconds", issues: &issues)
        validateFiniteNonNegative(backgroundMusic.fadeOutSeconds, path: "audio.backgroundMusic.fadeOutSeconds", issues: &issues)
    }

    private static func validateRange(
        _ range: EditTimeRange,
        path: String,
        issues: inout [RenderValidationIssue],
        messagePrefix: String
    ) {
        if !range.startSeconds.isFinite ||
            !range.durationSeconds.isFinite ||
            range.startSeconds < 0 ||
            range.durationSeconds <= 0 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "\(messagePrefix) range must be finite, non-negative, and positive.",
                path: path
            ))
        }
    }

    private static func validateGain(
        _ gain: Double,
        path: String,
        issues: inout [RenderValidationIssue]
    ) {
        if !gain.isFinite || gain < 0 || gain > 2 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Audio gain must be finite and between 0 and 2.",
                path: path
            ))
        }
    }

    private static func validateFiniteNonNegative(
        _ value: Double,
        path: String,
        issues: inout [RenderValidationIssue]
    ) {
        if !value.isFinite || value < 0 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Audio timing values must be finite and non-negative.",
                path: path
            ))
        }
    }

    private static func validateAnnotations(
        _ source: RenderMediaSource,
        issues: inout [RenderValidationIssue],
        fileManager: FileManager
    ) {
        guard fileManager.fileExists(atPath: source.url.path) else { return }
        do {
            let data = try Data(contentsOf: source.url)
            let store = try DMLessonJSON.decoder().decode(AnnotationStore.self, from: data)
            for (index, annotation) in store.annotations.enumerated() {
                let path = "annotations[\(index)]"
                if let timeRange = annotation.timeRange, !timeRange.isValid {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "Annotation time range must be finite, non-negative, and end after start.",
                        path: "\(path).timeRange"
                    ))
                }

                switch annotation.coordinateSpace {
                case .normalizedCapture:
                    let points = annotation.normalizedPoints ?? []
                    if points.isEmpty {
                        issues.append(RenderValidationIssue(
                            severity: .error,
                            message: "Normalized annotations must include normalized points.",
                            path: "\(path).normalizedPoints"
                        ))
                    }
                    if points.contains(where: { !$0.isValid }) {
                        issues.append(RenderValidationIssue(
                            severity: .error,
                            message: "Normalized annotation points must stay inside the capture frame.",
                            path: "\(path).normalizedPoints"
                        ))
                    }
                case .legacyCanvasPoints:
                    issues.append(RenderValidationIssue(
                        severity: .warning,
                        message: "Legacy point annotations render in canvas coordinates; normalized capture coordinates are preferred.",
                        path: "\(path).points"
                    ))
                }
            }
        } catch {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Annotation sidecar could not be decoded.",
                path: source.relativePath
            ))
        }
    }

    private static func validateCaptionSettings(
        _ settings: EditorCaptionSettings,
        issues: inout [RenderValidationIssue]
    ) {
        if settings.fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Caption font name is required.",
                path: "captions.fontName"
            ))
        }
        if !settings.fontSize.isFinite || settings.fontSize < 12 || settings.fontSize > 96 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Caption font size must be finite and between 12 and 96.",
                path: "captions.fontSize"
            ))
        }
        if settings.maxLineCount < 1 || settings.maxLineCount > 5 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Caption line count must be between 1 and 5.",
                path: "captions.maxLineCount"
            ))
        }
        if !settings.safeMarginRatio.isFinite || settings.safeMarginRatio < 0 || settings.safeMarginRatio > 0.25 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Caption safe margin must be finite and between 0 and 0.25.",
                path: "captions.safeMarginRatio"
            ))
        }
    }

    private static func validateCaptions(
        _ source: RenderMediaSource,
        issues: inout [RenderValidationIssue],
        fileManager: FileManager
    ) {
        guard fileManager.fileExists(atPath: source.url.path) else { return }
        do {
            let data = try Data(contentsOf: source.url)
            let transcript = try DMLessonJSON.decoder().decode(TranscriptDocument.self, from: data)
            for (index, segment) in transcript.segments.enumerated() {
                let path = "captions[\(index)]"
                if !segment.startSeconds.isFinite ||
                    !segment.endSeconds.isFinite ||
                    segment.startSeconds < 0 ||
                    segment.endSeconds <= segment.startSeconds {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "Caption timing must be finite, non-negative, and end after start.",
                        path: "\(path).range"
                    ))
                }
                if segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "Caption text is required.",
                        path: "\(path).text"
                    ))
                }
            }
        } catch {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Caption sidecar could not be decoded.",
                path: source.relativePath
            ))
        }
    }

    private static func validateOverlays(
        _ source: RenderMediaSource,
        projectURL: URL,
        issues: inout [RenderValidationIssue],
        fileManager: FileManager
    ) {
        guard fileManager.fileExists(atPath: source.url.path) else { return }
        do {
            let data = try Data(contentsOf: source.url)
            let store = try DMLessonJSON.decoder().decode(OverlayStore.self, from: data)
            for (index, overlay) in store.overlays.enumerated() {
                let path = "overlays[\(index)]"
                if !overlay.timeRange.startSeconds.isFinite ||
                    !overlay.timeRange.durationSeconds.isFinite ||
                    overlay.timeRange.startSeconds < 0 ||
                    overlay.timeRange.durationSeconds <= 0 {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "Overlay time range must be finite, non-negative, and positive.",
                        path: "\(path).timeRange"
                    ))
                }
                if overlay.frame.width <= 0 ||
                    overlay.frame.height <= 0 ||
                    overlay.frame.x + overlay.frame.width > 1 ||
                    overlay.frame.y + overlay.frame.height > 1 {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "Overlay frame must have positive size and stay inside the normalized frame.",
                        path: "\(path).frame"
                    ))
                }
                if let blurRadius = overlay.style.blurRadius, (!blurRadius.isFinite || blurRadius < 0) {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "Overlay blur radius must be finite and non-negative.",
                        path: "\(path).style.blurRadius"
                    ))
                }
                if let featherRadius = overlay.style.featherRadius, (!featherRadius.isFinite || featherRadius < 0) {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "Overlay feather radius must be finite and non-negative.",
                        path: "\(path).style.featherRadius"
                    ))
                }
                if overlay.kind == .image {
                    let imagePath = overlay.style.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if imagePath.isEmpty {
                        issues.append(RenderValidationIssue(
                            severity: .error,
                            message: "Image overlays require a project-local image path.",
                            path: "\(path).style.imagePath"
                        ))
                    } else {
                        let imageFile = ProjectFile(relativePath: imagePath, role: .attachment)
                        let imageURL: URL
                        do {
                            imageURL = try ProjectBundle.projectLocalFileURL(for: imageFile, in: projectURL)
                        } catch {
                            issues.append(RenderValidationIssue(
                                severity: .error,
                                message: "Image overlay asset must be a project-local relative path.",
                                path: imagePath
                            ))
                            continue
                        }
                        if !fileManager.fileExists(atPath: imageURL.path) {
                            issues.append(RenderValidationIssue(
                                severity: .error,
                                message: "Image overlay asset is missing.",
                                path: imagePath
                            ))
                        }
                    }
                }
            }
        } catch {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Overlay sidecar could not be decoded.",
                path: source.relativePath
            ))
        }
    }
}

extension RenderPlan {
    var requiredMediaSources: [RenderMediaSource] {
        var sources = [screenVideo]
        if let webcamOverlay {
            sources.append(webcamOverlay.source)
        }
        sources.append(contentsOf: audioSources)
        if let cursorSource {
            sources.append(cursorSource)
        }
        if let annotationSource {
            sources.append(annotationSource)
        }
        if let overlaySource {
            sources.append(overlaySource)
        }
        if let captionSource {
            sources.append(captionSource)
        }
        return sources
    }
}
