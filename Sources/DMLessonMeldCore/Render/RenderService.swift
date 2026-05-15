import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import QuartzCore

public typealias RenderProgressHandler = @MainActor @Sendable (Double) -> Void

public protocol RenderService: Sendable {
    func makePlan(projectURL: URL, destinationURL: URL, preset: RenderPreset) throws -> RenderPlan
    func inspect(
        projectURL: URL,
        destinationURL: URL,
        preset: RenderPreset,
        validationOptions: RenderValidationOptions
    ) throws -> RenderInspection
    func export(projectURL: URL, destinationURL: URL, preset: RenderPreset) async throws -> URL
    func export(plan: RenderPlan) async throws -> URL
    func export(plan: RenderPlan, progress: RenderProgressHandler?) async throws -> URL
}

public final class AVFoundationRenderService: RenderService, @unchecked Sendable {
    public init() {}

    public func makePlan(
        projectURL: URL,
        destinationURL: URL,
        preset: RenderPreset = RenderPreset()
    ) throws -> RenderPlan {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let editDecisionList = try loadEditDecisionListIfPresent(projectURL: projectURL)
        let editorSettings = try EditorSettingsFile.loadIfPresent(fromProject: projectURL)
        return try RenderPlan.make(
            manifest: manifest,
            projectURL: projectURL,
            destinationURL: destinationURL,
            preset: preset,
            editDecisionList: editDecisionList,
            editorSettings: editorSettings
        )
    }

    public func inspect(
        projectURL: URL,
        destinationURL: URL,
        preset: RenderPreset = RenderPreset(),
        validationOptions: RenderValidationOptions = RenderValidationOptions()
    ) throws -> RenderInspection {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let editDecisionList = try loadEditDecisionListIfPresent(projectURL: projectURL)
        let editorSettings = try EditorSettingsFile.loadIfPresent(fromProject: projectURL)

        do {
            let plan = try RenderPlan.make(
                manifest: manifest,
                projectURL: projectURL,
                destinationURL: destinationURL,
                preset: preset,
                editDecisionList: editDecisionList,
                editorSettings: editorSettings
            )
            return RenderInspection(
                projectURL: projectURL,
                lessonTitle: manifest.metadata.lessonTitle,
                hasWebcamOverlay: plan.webcamOverlay != nil,
                hasCursorEffects: plan.cursorSource != nil,
                hasAnnotations: plan.annotationSource != nil,
                hasOverlays: plan.overlaySource != nil,
                hasCaptions: plan.captionSource != nil,
                hasZoomRegions: !plan.zoomRegions.isEmpty,
                audioSourceCount: plan.audioSources.count,
                plan: plan,
                issues: plan.validate(options: validationOptions)
            )
        } catch let error as RenderPlanError {
            return RenderInspection(
                projectURL: projectURL,
                lessonTitle: manifest.metadata.lessonTitle,
                hasWebcamOverlay: manifest.media.webcam != nil,
                hasCursorEffects: manifest.media.cursorMetadata != nil,
                hasAnnotations: manifest.media.annotations != nil,
                hasOverlays: manifest.media.overlays != nil,
                hasCaptions: !manifest.media.transcripts.isEmpty || !manifest.media.captions.isEmpty,
                hasZoomRegions: !(editDecisionList?.enabledZoomRegions.isEmpty ?? true),
                audioSourceCount: [manifest.media.microphoneAudio, manifest.media.systemAudio].compactMap { $0 }.count,
                plan: nil,
                issues: [
                    RenderValidationIssue(
                        severity: .error,
                        message: error.localizedDescription
                    )
                ]
            )
        }
    }

    public func export(
        projectURL: URL,
        destinationURL: URL,
        preset: RenderPreset = RenderPreset()
    ) async throws -> URL {
        try await export(plan: makePlan(projectURL: projectURL, destinationURL: destinationURL, preset: preset))
    }

    public func export(plan: RenderPlan) async throws -> URL {
        try await export(plan: plan, progress: nil)
    }

    public func export(plan: RenderPlan, progress: RenderProgressHandler?) async throws -> URL {
        let issues = plan.validate(options: .export)
        let errors = issues.filter { $0.severity == .error }
        if !errors.isEmpty {
            throw RenderValidationError(issues: issues)
        }

        try FileManager.default.createDirectory(
            at: plan.destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if plan.webcamOverlay == nil,
           plan.audioSources.isEmpty,
           plan.cursorSource == nil,
           plan.annotationSource == nil,
           plan.overlaySource == nil,
           plan.captionSource == nil,
           plan.zoomRegions.isEmpty,
           plan.speedRegions.isEmpty,
           plan.audio.isDefault,
           plan.canvas.isDefault {
            return try await exportSingleAsset(plan, progress: progress)
        }

        return try await exportComposition(plan, progress: progress)
    }

    private func exportSingleAsset(_ plan: RenderPlan, progress: RenderProgressHandler?) async throws -> URL {
        let asset = AVURLAsset(url: plan.screenVideo.url)
        guard let session = AVAssetExportSession(asset: asset, presetName: presetName(for: plan.preset)) else {
            throw RenderExportError.unableToCreateExportSession
        }

        try await export(session: session, to: plan.destinationURL, as: plan.preset.fileType, progress: progress)
        return plan.destinationURL
    }

    private func exportComposition(_ plan: RenderPlan, progress: RenderProgressHandler?) async throws -> URL {
        let composition = AVMutableComposition()
        let screenAsset = AVURLAsset(url: plan.screenVideo.url)
        let screenDuration = try await screenAsset.load(.duration)
        let screenVideoTracks = try await screenAsset.loadTracks(withMediaType: .video)
        let interactionMetadata = try plan.cursorSource.map { try loadInteractionMetadata(from: $0.url) }
        var temporaryRenderFiles: [URL] = []
        defer {
            for url in temporaryRenderFiles {
                try? FileManager.default.removeItem(at: url)
            }
        }

        guard let screenVideoTrack = screenVideoTracks.first else {
            throw RenderExportError.missingVideoTrack(plan.screenVideo.relativePath)
        }

        guard let compositionScreenTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RenderExportError.unableToCreateCompositionTrack
        }

        try compositionScreenTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: screenDuration),
            of: screenVideoTrack,
            at: .zero
        )

        let outputDuration = retimedDuration(sourceDuration: screenDuration, speedRegions: plan.speedRegions)

        var audioTracks: [InsertedAudioTrack] = []
        audioTracks += try await insertAudioTracks(
            from: screenAsset,
            role: .screen,
            into: composition,
            duration: screenDuration
        )

        for source in plan.audioSources {
            let audioAsset = AVURLAsset(url: source.url)
            audioTracks += try await insertAudioTracks(
                from: audioAsset,
                role: audioTrackRole(for: source.role),
                into: composition,
                duration: screenDuration
            )
        }

        let screenNaturalSize = try await screenVideoTrack.load(.naturalSize)
        let screenPreferredTransform = try await screenVideoTrack.load(.preferredTransform)
        let screenDisplay = displayGeometry(naturalSize: screenNaturalSize, preferredTransform: screenPreferredTransform)
        let canvasGeometry = plan.canvas.renderGeometry(sourceSize: screenDisplay.size)
        let renderSize = canvasGeometry.renderSize

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: outputDuration)

        let screenInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionScreenTrack)
        let screenBaseTransform = canvasScreenTransform(
            orientedTransform: screenDisplay.transform,
            canvasGeometry: canvasGeometry
        )
        screenInstruction.setTransform(screenBaseTransform, at: .zero)
        screenInstruction.setCropRectangle(canvasGeometry.videoFrame, at: .zero)
        applyZoomRegions(
            plan.zoomRegions,
            to: screenInstruction,
            baseTransform: screenBaseTransform,
            renderSize: renderSize,
            duration: screenDuration
        )

        var layerInstructions = [screenInstruction]
        var webcamGeometry: PictureInPictureRenderGeometry?
        var retimedTracks = [compositionScreenTrack]
        retimedTracks += audioTracks.map(\.track)

        if let webcamOverlay = plan.webcamOverlay {
            let webcamOverlayComposition = try await insertWebcamOverlay(
                webcamOverlay,
                into: composition,
                duration: screenDuration,
                renderSize: renderSize,
                camera: plan.camera
            )
            layerInstructions.insert(webcamOverlayComposition.instruction, at: 0)
            webcamGeometry = webcamOverlayComposition.geometry
            retimedTracks.append(webcamOverlayComposition.track)
        }

        applySpeedRegions(plan.speedRegions, to: retimedTracks, sourceDuration: screenDuration)

        if let backgroundMusic = plan.audio.backgroundMusic {
            audioTracks += try await insertBackgroundMusicTrack(
                backgroundMusic,
                projectURL: plan.projectURL,
                into: composition,
                duration: outputDuration
            )
        }
        if let interactionMetadata {
            try await insertClickSoundTrack(
                for: interactionMetadata.clicks,
                settings: plan.cursor.clickEffects,
                duration: outputDuration,
                into: composition,
                temporaryRenderFiles: &temporaryRenderFiles
            )
        }

        instruction.layerInstructions = layerInstructions

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        try applyOverlayLayersIfNeeded(
            plan: plan,
            videoComposition: videoComposition,
            renderSize: renderSize,
            canvasGeometry: canvasGeometry,
            webcamGeometry: webcamGeometry,
            interactionMetadata: interactionMetadata
        )

        guard let session = AVAssetExportSession(asset: composition, presetName: presetName(for: plan.preset)) else {
            throw RenderExportError.unableToCreateExportSession
        }
        session.videoComposition = videoComposition
        session.audioMix = audioMix(
            for: audioTracks,
            settings: plan.audio,
            duration: outputDuration,
            hasVoiceAudio: plan.audioSources.contains { $0.role == .microphoneAudio || $0.role == .systemAudio }
        )

        try await export(session: session, to: plan.destinationURL, as: plan.preset.fileType, progress: progress)
        return plan.destinationURL
    }

    private func applyOverlayLayersIfNeeded(
        plan: RenderPlan,
        videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        canvasGeometry: EditorCanvasRenderGeometry,
        webcamGeometry: PictureInPictureRenderGeometry?,
        interactionMetadata: InteractionMetadataDocument?
    ) throws {
        let overlayLayers = try overlayLayers(
            plan: plan,
            renderSize: renderSize,
            webcamGeometry: webcamGeometry,
            interactionMetadata: interactionMetadata
        )
        guard !overlayLayers.isEmpty || !plan.canvas.isDefault else { return }

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = false

        if let backgroundLayer = canvasBackgroundLayer(plan.canvas.background, projectURL: plan.projectURL, renderSize: renderSize) {
            parentLayer.addSublayer(backgroundLayer)
        }
        if let shadowLayer = canvasShadowLayer(plan.canvas, geometry: canvasGeometry, renderSize: renderSize) {
            parentLayer.addSublayer(shadowLayer)
        }

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        if canvasGeometry.cornerRadius > 0 {
            let mask = CAShapeLayer()
            mask.frame = parentLayer.bounds
            mask.path = CGPath(
                roundedRect: canvasGeometry.videoFrame,
                cornerWidth: canvasGeometry.cornerRadius,
                cornerHeight: canvasGeometry.cornerRadius,
                transform: nil
            )
            videoLayer.mask = mask
        }
        parentLayer.addSublayer(videoLayer)

        let overlayLayer = CALayer()
        overlayLayer.frame = parentLayer.bounds
        overlayLayer.masksToBounds = true
        for layer in overlayLayers {
            overlayLayer.addSublayer(layer)
        }
        parentLayer.addSublayer(overlayLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private func overlayLayers(
        plan: RenderPlan,
        renderSize: CGSize,
        webcamGeometry: PictureInPictureRenderGeometry?,
        interactionMetadata: InteractionMetadataDocument?
    ) throws -> [CALayer] {
        var layers: [CALayer] = []
        var screenBoundLayers: [CALayer] = []

        if let annotationSource = plan.annotationSource {
            let store = try loadAnnotationStore(from: annotationSource.url)
            if store.isVisible {
                screenBoundLayers.append(contentsOf: store.annotations.filter(\.isVisible).map {
                    annotationLayer(for: $0, renderSize: renderSize)
                })
            }
        }

        if let interactionMetadata {
            screenBoundLayers.append(contentsOf: cursorLayers(for: interactionMetadata, settings: plan.cursor, renderSize: renderSize))
        }

        if !screenBoundLayers.isEmpty {
            let screenBoundContainer = CALayer()
            screenBoundContainer.anchorPoint = .zero
            screenBoundContainer.position = .zero
            screenBoundContainer.bounds = CGRect(origin: .zero, size: renderSize)
            screenBoundContainer.masksToBounds = true
            for layer in screenBoundLayers {
                screenBoundContainer.addSublayer(layer)
            }
            applyOverlayZoomRegions(plan.zoomRegions, to: screenBoundContainer, renderSize: renderSize)
            layers.append(screenBoundContainer)
        }

        if let webcamOverlay = plan.webcamOverlay, let webcamGeometry {
            layers.append(contentsOf: pictureInPictureStyleLayers(
                for: webcamOverlay,
                geometry: webcamGeometry,
                renderSize: renderSize
            ))
        }

        if plan.webcamOverlay != nil {
            layers.append(contentsOf: cameraReactionLayers(for: plan.camera.enabledReactions, renderSize: renderSize))
        }

        if let overlaySource = plan.overlaySource {
            let store = try loadOverlayStore(from: overlaySource.url)
            if store.isVisible {
                layers.append(contentsOf: store.overlays
                    .filter(\.isEnabled)
                    .sorted { $0.zIndex < $1.zIndex }
                    .map { overlayLayer(for: $0, projectURL: plan.projectURL, renderSize: renderSize) })
            }
        }

        if let captionSource = plan.captionSource, plan.captions.burnInEnabled {
            let transcript = try loadTranscript(from: captionSource.url)
            layers.append(contentsOf: transcript.segments.compactMap {
                captionLayer(for: $0, settings: plan.captions, renderSize: renderSize)
            })
        }

        if let interactionMetadata, plan.cursor.keyboardOverlay.isVisible {
            layers.append(contentsOf: keyboardLayers(for: interactionMetadata, settings: plan.cursor.keyboardOverlay, renderSize: renderSize))
        }

        return layers
    }

    private func pictureInPictureStyleLayers(
        for overlay: PictureInPictureOverlay,
        geometry: PictureInPictureRenderGeometry,
        renderSize: CGSize
    ) -> [CALayer] {
        var layers: [CALayer] = []

        if overlay.placement.shadowEnabled {
            let shadowLayer = CAShapeLayer()
            shadowLayer.frame = geometry.frame
            shadowLayer.path = pictureInPicturePath(
                frameShape: overlay.placement.frameShape,
                bounds: shadowLayer.bounds,
                cornerRadius: geometry.cornerRadius
            )
            shadowLayer.fillColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.001)
            shadowLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            shadowLayer.shadowOpacity = 0.34
            shadowLayer.shadowRadius = max(5, min(renderSize.width, renderSize.height) * 0.015)
            shadowLayer.shadowOffset = CGSize(
                width: 0,
                height: -max(3, min(renderSize.width, renderSize.height) * 0.006)
            )
            shadowLayer.shadowPath = shadowLayer.path
            layers.append(shadowLayer)
        }

        if overlay.placement.borderEnabled {
            let borderWidth = max(1, min(renderSize.width, renderSize.height) * 0.0018)
            let borderLayer = CAShapeLayer()
            borderLayer.frame = geometry.frame
            borderLayer.path = pictureInPicturePath(
                frameShape: overlay.placement.frameShape,
                bounds: borderLayer.bounds,
                cornerRadius: geometry.cornerRadius,
                inset: borderWidth / 2
            )
            borderLayer.fillColor = nil
            borderLayer.strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.68)
            borderLayer.lineWidth = borderWidth
            layers.append(borderLayer)
        }

        return layers
    }

    private func cameraReactionLayers(for reactions: [CameraReaction], renderSize: CGSize) -> [CALayer] {
        reactions.map { reaction in
            let rect = overlayFrame(reaction.frame, renderSize: renderSize)
            let container = CALayer()
            container.frame = rect

            let text = CATextLayer()
            text.string = reaction.text
            text.font = "Helvetica-Bold" as CFTypeRef
            text.fontSize = max(18, rect.height * 0.58)
            text.alignmentMode = .center
            text.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            text.contentsScale = 2
            text.frame = container.bounds
            container.addSublayer(text)

            let start = reaction.range.startSeconds
            let duration = max(reaction.range.durationSeconds, 0.1)
            container.opacity = 0
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [0, 1, 1, 0]
            animation.keyTimes = [0, 0.18, 0.82, 1]
            animation.beginTime = AVCoreAnimationBeginTimeAtZero + start
            animation.duration = duration
            animation.fillMode = .removed
            animation.isRemovedOnCompletion = true
            container.add(animation, forKey: "camera-reaction-\(reaction.id)")
            return container
        }
    }

    private func pictureInPicturePath(
        frameShape: PictureInPictureFrameShape,
        bounds: CGRect,
        cornerRadius: CGFloat,
        inset: CGFloat = 0
    ) -> CGPath {
        let rect = bounds.insetBy(dx: inset, dy: inset)
        switch frameShape {
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .square:
            return CGPath(rect: rect, transform: nil)
        case .roundedRectangle:
            let radius = max(0, min(cornerRadius - inset, min(rect.width, rect.height) / 2))
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
    }

    private func canvasScreenTransform(
        orientedTransform: CGAffineTransform,
        canvasGeometry: EditorCanvasRenderGeometry
    ) -> CGAffineTransform {
        let crop = canvasGeometry.sourceCropRect
        let frame = canvasGeometry.videoFrame
        let scale = min(frame.width / max(crop.width, 1), frame.height / max(crop.height, 1))
        return orientedTransform
            .concatenating(CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY))
    }

    private func canvasBackgroundLayer(
        _ background: EditorCanvasBackground,
        projectURL: URL,
        renderSize: CGSize
    ) -> CALayer? {
        let frame = CGRect(origin: .zero, size: renderSize)
        switch background.style {
        case .none:
            return nil
        case .solid:
            let layer = CALayer()
            layer.frame = frame
            layer.backgroundColor = cgColor(background.primaryColor, opacity: background.primaryColor.alpha)
            return layer
        case .gradient:
            let layer = CAGradientLayer()
            layer.frame = frame
            layer.colors = [
                cgColor(background.primaryColor, opacity: background.primaryColor.alpha),
                cgColor(background.secondaryColor, opacity: background.secondaryColor.alpha)
            ]
            layer.startPoint = CGPoint(x: 0.05, y: 0.05)
            layer.endPoint = CGPoint(x: 0.95, y: 0.95)
            return layer
        case .image:
            guard let imagePath = background.imagePath,
                  let image = loadCanvasBackgroundImage(projectURL: projectURL, imagePath: imagePath) else {
                return nil
            }
            let layer = CALayer()
            layer.frame = frame
            layer.contents = image
            layer.contentsGravity = .resizeAspectFill
            layer.masksToBounds = true
            return layer
        }
    }

    private func loadCanvasBackgroundImage(projectURL: URL, imagePath: String) -> CGImage? {
        guard let imageURL = try? ProjectBundle.projectLocalFileURL(
            for: ProjectFile(relativePath: imagePath, role: .attachment),
            in: projectURL
        ) else {
            return nil
        }
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func canvasShadowLayer(
        _ canvas: EditorCanvasSettings,
        geometry: EditorCanvasRenderGeometry,
        renderSize: CGSize
    ) -> CALayer? {
        guard canvas.shadow.isEnabled else { return nil }
        let layer = CAShapeLayer()
        layer.frame = geometry.videoFrame
        layer.path = CGPath(
            roundedRect: layer.bounds,
            cornerWidth: geometry.cornerRadius,
            cornerHeight: geometry.cornerRadius,
            transform: nil
        )
        layer.fillColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.001)
        layer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        layer.shadowOpacity = Float(canvas.shadow.opacity)
        layer.shadowRadius = max(1, min(renderSize.width, renderSize.height) * CGFloat(canvas.shadow.radiusRatio))
        layer.shadowOffset = CGSize(width: 0, height: min(renderSize.width, renderSize.height) * CGFloat(canvas.shadow.offsetYRatio))
        layer.shadowPath = layer.path
        return layer
    }

    private func loadAnnotationStore(from url: URL) throws -> AnnotationStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AnnotationStore()
        }
        let data = try Data(contentsOf: url)
        return try DMLessonJSON.decoder().decode(AnnotationStore.self, from: data)
    }

    private func loadOverlayStore(from url: URL) throws -> OverlayStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return OverlayStore()
        }
        let data = try Data(contentsOf: url)
        return try DMLessonJSON.decoder().decode(OverlayStore.self, from: data)
    }

    private func loadTranscript(from url: URL) throws -> TranscriptDocument {
        let data = try Data(contentsOf: url)
        return try DMLessonJSON.decoder().decode(TranscriptDocument.self, from: data)
    }

    private func loadInteractionMetadata(from url: URL) throws -> InteractionMetadataDocument {
        let data = try Data(contentsOf: url)
        return try DMLessonJSON.decoder().decode(InteractionMetadataDocument.self, from: data)
    }

    private func loadEditDecisionListIfPresent(projectURL: URL) throws -> EditDecisionList? {
        guard EditDecisionListFile.exists(in: projectURL) else {
            return nil
        }
        return try EditDecisionListFile.load(fromProject: projectURL)
    }

    private func applySpeedRegions(
        _ speedRegions: [SpeedRegion],
        to tracks: [AVMutableCompositionTrack],
        sourceDuration: CMTime
    ) {
        let sourceDurationSeconds = sourceDuration.seconds.isFinite ? max(0, sourceDuration.seconds) : 0
        guard sourceDurationSeconds > 0 else { return }

        for region in speedRegions.sorted(by: { $0.range.startSeconds > $1.range.startSeconds }) {
            let startSeconds = min(max(0, region.range.startSeconds), sourceDurationSeconds)
            let endSeconds = min(max(startSeconds, region.range.endSeconds), sourceDurationSeconds)
            guard endSeconds > startSeconds, region.playbackRate.isFinite, region.playbackRate > 0 else {
                continue
            }

            let sourceRange = CMTimeRange(
                start: time(startSeconds),
                duration: time(endSeconds - startSeconds)
            )
            let targetDuration = time((endSeconds - startSeconds) / region.playbackRate)
            for track in tracks {
                track.scaleTimeRange(sourceRange, toDuration: targetDuration)
            }
        }
    }

    private func retimedDuration(sourceDuration: CMTime, speedRegions: [SpeedRegion]) -> CMTime {
        let sourceDurationSeconds = sourceDuration.seconds.isFinite ? max(0, sourceDuration.seconds) : 0
        guard sourceDurationSeconds > 0, !speedRegions.isEmpty else { return sourceDuration }

        var durationSeconds = sourceDurationSeconds
        for region in speedRegions {
            let startSeconds = min(max(0, region.range.startSeconds), sourceDurationSeconds)
            let endSeconds = min(max(startSeconds, region.range.endSeconds), sourceDurationSeconds)
            guard endSeconds > startSeconds, region.playbackRate.isFinite, region.playbackRate > 0 else {
                continue
            }
            let sourceRegionDuration = endSeconds - startSeconds
            durationSeconds += (sourceRegionDuration / region.playbackRate) - sourceRegionDuration
        }
        return time(max(0, durationSeconds))
    }

    private func applyZoomRegions(
        _ zoomRegions: [ZoomRegion],
        to instruction: AVMutableVideoCompositionLayerInstruction,
        baseTransform: CGAffineTransform,
        renderSize: CGSize,
        duration: CMTime
    ) {
        guard !zoomRegions.isEmpty else { return }

        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds.isFinite, totalSeconds > 0 else { return }

        for region in zoomRegions.sorted(by: { $0.range.startSeconds < $1.range.startSeconds }) {
            let startSeconds = max(0, min(region.range.startSeconds, totalSeconds))
            let endSeconds = max(startSeconds, min(region.range.endSeconds, totalSeconds))
            guard endSeconds > startSeconds else { continue }

            let regionDuration = endSeconds - startSeconds
            let rampDuration = zoomRampDuration(for: region, regionDuration: regionDuration)
            let zoomTransform = zoomTransform(for: region, baseTransform: baseTransform, renderSize: renderSize)

            if rampDuration > 0 {
                instruction.setTransformRamp(
                    fromStart: baseTransform,
                    toEnd: zoomTransform,
                    timeRange: timeRange(startSeconds: startSeconds, durationSeconds: rampDuration)
                )
            } else {
                instruction.setTransform(zoomTransform, at: time(startSeconds))
            }

            let holdStart = startSeconds + rampDuration
            let outStart = endSeconds - rampDuration
            if outStart > holdStart {
                instruction.setTransform(zoomTransform, at: time(holdStart))
                instruction.setTransform(zoomTransform, at: time(outStart))
            }

            if rampDuration > 0 {
                instruction.setTransformRamp(
                    fromStart: zoomTransform,
                    toEnd: baseTransform,
                    timeRange: timeRange(startSeconds: outStart, durationSeconds: rampDuration)
                )
            }
            instruction.setTransform(baseTransform, at: time(endSeconds))
        }
    }

    private func zoomTransform(
        for region: ZoomRegion,
        baseTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let scale = CGFloat(max(1, region.scale))
        let focusPoint = EditorNormalizedGeometry.flippedTopDownPoint(
            x: region.focusRect.centerX,
            y: region.focusRect.centerY,
            in: CGRect(origin: .zero, size: renderSize)
        )
        let renderCenter = CGPoint(x: renderSize.width / 2, y: renderSize.height / 2)
        let translation = CGAffineTransform(
            translationX: renderCenter.x - focusPoint.x * scale,
            y: renderCenter.y - focusPoint.y * scale
        )
        return baseTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(translation)
    }

    private func applyOverlayZoomRegions(
        _ zoomRegions: [ZoomRegion],
        to layer: CALayer,
        renderSize: CGSize
    ) {
        guard !zoomRegions.isEmpty else { return }

        for region in zoomRegions.sorted(by: { $0.range.startSeconds < $1.range.startSeconds }) {
            let startSeconds = max(0, region.range.startSeconds)
            let endSeconds = max(startSeconds, region.range.endSeconds)
            guard endSeconds > startSeconds else { continue }

            let regionDuration = endSeconds - startSeconds
            let rampDuration = zoomRampDuration(for: region, regionDuration: regionDuration)
            let zoomTransform = zoomTransform(for: region, baseTransform: .identity, renderSize: renderSize)
            let zoom3D = CATransform3DMakeAffineTransform(zoomTransform)
            let identity3D = CATransform3DIdentity

            if rampDuration > 0 {
                let zoomIn = CABasicAnimation(keyPath: "transform")
                zoomIn.fromValue = identity3D
                zoomIn.toValue = zoom3D
                zoomIn.beginTime = AVCoreAnimationBeginTimeAtZero + startSeconds
                zoomIn.duration = rampDuration
                zoomIn.timingFunction = zoomTimingFunction(for: region)
                zoomIn.fillMode = .forwards
                zoomIn.isRemovedOnCompletion = false
                layer.add(zoomIn, forKey: "overlay-zoom-in-\(region.id)")
            }

            let outStart = endSeconds - rampDuration
            if rampDuration > 0 {
                let zoomOut = CABasicAnimation(keyPath: "transform")
                zoomOut.fromValue = zoom3D
                zoomOut.toValue = identity3D
                zoomOut.beginTime = AVCoreAnimationBeginTimeAtZero + outStart
                zoomOut.duration = rampDuration
                zoomOut.timingFunction = zoomTimingFunction(for: region)
                zoomOut.fillMode = .forwards
                zoomOut.isRemovedOnCompletion = false
                layer.add(zoomOut, forKey: "overlay-zoom-out-\(region.id)")
            }
        }
    }

    private func zoomRampDuration(for region: ZoomRegion, regionDuration: Double) -> Double {
        switch region.easing ?? .smooth {
        case .instant:
            0
        case .linear, .smooth:
            min(0.22, regionDuration / 3)
        }
    }

    private func zoomTimingFunction(for region: ZoomRegion) -> CAMediaTimingFunction {
        switch region.easing ?? .smooth {
        case .linear:
            CAMediaTimingFunction(name: .linear)
        case .instant, .smooth:
            CAMediaTimingFunction(name: .easeInEaseOut)
        }
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func timeRange(startSeconds: Double, durationSeconds: Double) -> CMTimeRange {
        CMTimeRange(
            start: time(startSeconds),
            duration: time(max(0, durationSeconds))
        )
    }

    private func cursorLayers(
        for metadata: InteractionMetadataDocument,
        settings: EditorCursorSettings,
        renderSize: CGSize
    ) -> [CALayer] {
        var layers: [CALayer] = []

        if metadata.rendersCursorPointer,
           settings.pointerVisible,
           let cursorLayer = animatedCursorLayer(for: metadata.cursorSamples, settings: settings, renderSize: renderSize) {
            layers.append(cursorLayer)
        }

        if settings.clickEffects.rippleVisible {
            layers.append(contentsOf: metadata.clicks.compactMap {
                clickLayer(for: $0, settings: settings.clickEffects, renderSize: renderSize)
            })
        }

        return layers
    }

    private func animatedCursorLayer(
        for samples: [CursorSample],
        settings: EditorCursorSettings,
        renderSize: CGSize
    ) -> CALayer? {
        let visibleSamples = samples
            .sorted { $0.timestampSeconds < $1.timestampSeconds }
            .map { sample in
                CursorSample(
                    timestampSeconds: sample.timestampSeconds,
                    position: sample.position,
                    isVisible: sample.isVisible && !settings.hiddenRanges.contains { $0.contains(sample.timestampSeconds) }
                )
            }
        guard let first = visibleSamples.first else { return nil }

        let layer = CAShapeLayer()
        let scale = max(0.65, min(renderSize.width / 1920, 1.6)) * CGFloat(settings.pointerScale)
        layer.frame = .zero
        layer.path = cursorPointerPath(style: settings.pointerStyle, scale: scale)
        layer.fillColor = cgColor(settings.pointerFillColor, opacity: settings.pointerFillColor.alpha)
        layer.strokeColor = cgColor(settings.pointerStrokeColor, opacity: settings.pointerStrokeColor.alpha)
        layer.lineWidth = settings.pointerStyle == .touchDot ? max(1.8, 3.2 * scale) : max(1.4, 2.2 * scale)
        layer.lineJoin = .round
        layer.lineCap = .round
        layer.position = renderPoint(first.position, renderSize: renderSize)
        layer.opacity = first.isVisible ? 1 : 0

        guard visibleSamples.count > 1, let last = visibleSamples.last else {
            return layer
        }

        let start = first.timestampSeconds
        let duration = max(last.timestampSeconds - start, 0.05)
        let denominator = duration == 0 ? 1 : duration
        let keyTimes = visibleSamples.map {
            NSNumber(value: min(1, max(0, ($0.timestampSeconds - start) / denominator)))
        }

        let positionAnimation = CAKeyframeAnimation(keyPath: "position")
        positionAnimation.values = visibleSamples.map {
            NSValue(point: renderPoint($0.position, renderSize: renderSize))
        }
        positionAnimation.keyTimes = keyTimes
        positionAnimation.beginTime = AVCoreAnimationBeginTimeAtZero + start
        positionAnimation.duration = duration
        positionAnimation.calculationMode = settings.smoothMovement ? .linear : .discrete
        positionAnimation.fillMode = .forwards
        positionAnimation.isRemovedOnCompletion = false
        layer.add(positionAnimation, forKey: "cursor-position")

        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.values = visibleSamples.map { $0.isVisible ? 1 : 0 }
        opacityAnimation.keyTimes = keyTimes
        opacityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero + start
        opacityAnimation.duration = duration
        opacityAnimation.calculationMode = .discrete
        opacityAnimation.fillMode = .forwards
        opacityAnimation.isRemovedOnCompletion = false
        layer.add(opacityAnimation, forKey: "cursor-opacity")

        return layer
    }

    private func clickLayer(for click: CursorClick, settings: EditorClickEffectSettings, renderSize: CGSize) -> CALayer? {
        guard click.phase == .down else { return nil }

        let scale = max(0.75, min(renderSize.width / 1920, 1.8))
        let radius = CGFloat(19 * scale * Double(click.clickCount) * settings.scale)
        let point = renderPoint(click.position, renderSize: renderSize)
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        let layer = CAShapeLayer()
        layer.frame = rect
        layer.path = CGPath(ellipseIn: layer.bounds, transform: nil)
        layer.fillColor = nil
        layer.strokeColor = cgColor(settings.color, opacity: settings.color.alpha)
        layer.lineWidth = max(3, 4 * scale)
        layer.opacity = 0

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = settings.opacity
        opacity.toValue = 0

        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.45
        scaleAnimation.toValue = 1.9

        let group = CAAnimationGroup()
        group.animations = [opacity, scaleAnimation]
        group.beginTime = AVCoreAnimationBeginTimeAtZero + click.timestampSeconds
        group.duration = settings.durationSeconds
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .removed
        group.isRemovedOnCompletion = true
        layer.add(group, forKey: "click-\(click.timestampSeconds)")

        return layer
    }

    private func cursorPointerPath(style: EditorCursorPointerStyle, scale: CGFloat) -> CGPath {
        if style == .touchDot {
            let radius = 8 * scale
            return CGPath(
                ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
                transform: nil
            )
        }

        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: -34 * scale))
        path.addLine(to: CGPoint(x: 10 * scale, y: -25 * scale))
        path.addLine(to: CGPoint(x: 16 * scale, y: -40 * scale))
        path.addLine(to: CGPoint(x: 24 * scale, y: -36 * scale))
        path.addLine(to: CGPoint(x: 17 * scale, y: -22 * scale))
        path.addLine(to: CGPoint(x: 31 * scale, y: -22 * scale))
        path.closeSubpath()
        return path
    }

    private func renderPoint(_ point: NormalizedCapturePoint, renderSize: CGSize) -> CGPoint {
        EditorNormalizedGeometry.renderPoint(for: point, renderSize: renderSize)
    }

    private func keyboardLayers(
        for metadata: InteractionMetadataDocument,
        settings: EditorKeyboardOverlaySettings,
        renderSize: CGSize
    ) -> [CALayer] {
        metadata.keystrokes.compactMap {
            keyboardLayer(for: $0, settings: settings, renderSize: renderSize)
        }
    }

    private func keyboardLayer(
        for event: KeyboardMetadataEvent,
        settings: EditorKeyboardOverlaySettings,
        renderSize: CGSize
    ) -> CALayer? {
        guard event.phase == .down, !event.isRepeat, let label = keyboardLabel(for: event) else {
            return nil
        }

        let fontSize = max(18, min(renderSize.height * 0.038, 30))
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 9
        let width = min(max(CGFloat(label.count) * fontSize * 0.58 + horizontalPadding * 2, 96), renderSize.width * 0.55)
        let height = fontSize * 1.25 + verticalPadding * 2
        let margin = max(renderSize.width * 0.035, 28)
        let frame = CGRect(
            x: renderSize.width - width - margin,
            y: renderSize.height - height - margin,
            width: width,
            height: height
        )

        let container = CALayer()
        container.frame = frame
        container.opacity = 0

        let background = CALayer()
        background.frame = container.bounds
        background.backgroundColor = CGColor(red: 0.03, green: 0.035, blue: 0.04, alpha: 0.82 * settings.opacity)
        background.cornerRadius = 9
        background.borderColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.18)
        background.borderWidth = 1
        container.addSublayer(background)

        let text = CATextLayer()
        text.string = label
        text.font = "Helvetica-Bold" as CFTypeRef
        text.fontSize = fontSize
        text.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        text.alignmentMode = .center
        text.contentsScale = 2
        text.frame = container.bounds.insetBy(dx: horizontalPadding, dy: verticalPadding)
        container.addSublayer(text)

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 1
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + event.timestampSeconds
        animation.duration = 0.9
        animation.fillMode = .removed
        animation.isRemovedOnCompletion = true
        container.add(animation, forKey: "keyboard-\(event.timestampSeconds)-\(event.keyCode)")
        return container
    }

    private func keyboardLabel(for event: KeyboardMetadataEvent) -> String? {
        let key = keyLabel(for: event)
        guard !key.isEmpty else { return nil }

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
        if event.modifiers.contains(.function) {
            parts.append("Fn")
        }

        if parts.isEmpty, key.count == 1, key.rangeOfCharacter(from: .alphanumerics) != nil {
            return nil
        }

        parts.append(key)
        return parts.joined(separator: "+")
    }

    private func keyLabel(for event: KeyboardMetadataEvent) -> String {
        if let characters = event.characters {
            switch characters {
            case "\r":
                return "Return"
            case "\t":
                return "Tab"
            case " ":
                return "Space"
            case "\u{1B}":
                return "Esc"
            default:
                let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed.uppercased()
                }
            }
        }

        switch event.keyCode {
        case 36:
            return "Return"
        case 48:
            return "Tab"
        case 49:
            return "Space"
        case 51:
            return "Delete"
        case 53:
            return "Esc"
        case 123:
            return "Left"
        case 124:
            return "Right"
        case 125:
            return "Down"
        case 126:
            return "Up"
        default:
            return "Key \(event.keyCode)"
        }
    }

    private func captionLayer(
        for segment: TranscriptSegment,
        settings: EditorCaptionSettings,
        renderSize: CGSize
    ) -> CALayer? {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, segment.endSeconds > segment.startSeconds else {
            return nil
        }

        let maxWidth = min(renderSize.width * 0.82, 980)
        let fontSize = min(max(settings.fontSize, 12), min(renderSize.height * 0.08, 96))
        let lineHeight = fontSize * 1.28
        let estimatedLines = max(1, min(settings.maxLineCount, Int(ceil(Double(text.count) / 42.0))))
        let height = CGFloat(estimatedLines) * lineHeight + 22
        let safeMargin = max(18, min(renderSize.width, renderSize.height) * CGFloat(settings.safeMarginRatio))
        let y: CGFloat
        switch settings.placement {
        case .top:
            y = renderSize.height - safeMargin - height
        case .middle:
            y = (renderSize.height - height) / 2
        case .bottom:
            y = safeMargin
        }
        let frame = CGRect(
            x: (renderSize.width - maxWidth) / 2,
            y: y,
            width: maxWidth,
            height: height
        )

        let container = CALayer()
        container.frame = frame
        container.opacity = 0

        let background = CALayer()
        background.frame = container.bounds
        background.backgroundColor = cgColor(settings.backgroundColor, opacity: 1)
        background.cornerRadius = 10
        container.addSublayer(background)

        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = settings.fontName as CFTypeRef
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = cgColor(settings.textColor, opacity: 1)
        textLayer.alignmentMode = .center
        textLayer.contentsScale = 2
        textLayer.isWrapped = true
        textLayer.frame = container.bounds.insetBy(dx: 18, dy: 10)
        container.addSublayer(textLayer)

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 1
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + segment.startSeconds
        animation.duration = max(segment.endSeconds - segment.startSeconds, 0.05)
        animation.fillMode = .removed
        animation.isRemovedOnCompletion = true
        container.add(animation, forKey: "caption-\(segment.id)")
        return container
    }

    private func overlayLayer(for overlay: OverlayItem, projectURL: URL, renderSize: CGSize) -> CALayer {
        let rect = overlayFrame(overlay.frame, renderSize: renderSize)
        let layer: CALayer

        switch overlay.kind {
        case .text:
            layer = overlayTextLayer(overlay, frame: rect)
        case .rectangle:
            layer = overlayShapeLayer(overlay, frame: rect, path: CGPath(roundedRect: CGRect(origin: .zero, size: rect.size), cornerWidth: overlay.style.cornerRadius, cornerHeight: overlay.style.cornerRadius, transform: nil))
        case .ellipse:
            layer = overlayShapeLayer(overlay, frame: rect, path: CGPath(ellipseIn: CGRect(origin: .zero, size: rect.size), transform: nil))
        case .line:
            layer = overlayShapeLayer(overlay, frame: rect, path: overlayLinePath(in: rect.size, arrow: false))
        case .arrow:
            layer = overlayShapeLayer(overlay, frame: rect, path: overlayLinePath(in: rect.size, arrow: true))
        case .callout:
            layer = overlayCalloutLayer(overlay, frame: rect)
        case .image:
            layer = overlayImageLayer(overlay, projectURL: projectURL, frame: rect)
        case .highlight:
            layer = overlayHighlightLayer(overlay, focusFrame: rect, renderSize: renderSize)
        }

        if overlay.rotationDegrees != 0 {
            layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(overlay.rotationDegrees * .pi / 180)))
        }
        if overlay.style.shadowEnabled, overlay.kind != .highlight {
            layer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            layer.shadowOpacity = 0.28
            layer.shadowRadius = 10
            layer.shadowOffset = CGSize(width: 0, height: -4)
        }
        applyTiming(to: layer, overlay: overlay)
        return layer
    }

    private func overlayHighlightLayer(_ overlay: OverlayItem, focusFrame: CGRect, renderSize: CGSize) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: renderSize)
        let fullFrame = CGRect(origin: .zero, size: renderSize)
        let mode = overlay.style.highlightMode ?? .dim
        let shape = overlay.style.highlightShape ?? .roundedRectangle
        let outsidePath = overlayOutsidePath(focusFrame: focusFrame, fullFrame: fullFrame, shape: shape, cornerRadius: overlay.style.cornerRadius)
        let focusPath = overlayFocusPath(focusFrame, shape: shape, cornerRadius: overlay.style.cornerRadius)
        let tintColor = overlay.style.fillColor ?? RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.58)
        let strokeColor = overlay.style.strokeColor

        if mode == .blur {
            let blurLayer = CALayer()
            blurLayer.frame = fullFrame
            blurLayer.backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.001)
            if let filter = CIFilter(name: "CIGaussianBlur") {
                filter.setValue(max(1, overlay.style.blurRadius ?? 12), forKey: kCIInputRadiusKey)
                blurLayer.backgroundFilters = [filter]
            }
            let mask = CAShapeLayer()
            mask.frame = fullFrame
            mask.path = outsidePath
            mask.fillRule = .evenOdd
            blurLayer.mask = mask
            container.addSublayer(blurLayer)
        }

        if mode != .outline {
            let dimLayer = CAShapeLayer()
            dimLayer.frame = fullFrame
            dimLayer.path = outsidePath
            dimLayer.fillRule = .evenOdd
            let opacityScale = mode == .blur ? 0.35 : 1
            dimLayer.fillColor = cgColor(tintColor, opacity: overlay.opacity * opacityScale)
            container.addSublayer(dimLayer)
        }

        let feather = CGFloat(overlay.style.featherRadius ?? 0)
        if feather > 0, mode != .dim {
            let glow = CAShapeLayer()
            glow.frame = fullFrame
            glow.path = focusPath
            glow.fillColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
            glow.strokeColor = cgColor(strokeColor, opacity: min(overlay.opacity, 1) * 0.28)
            glow.lineWidth = max(8, feather * 2)
            glow.lineJoin = .round
            container.addSublayer(glow)
        }

        let border = CAShapeLayer()
        border.frame = fullFrame
        border.path = focusPath
        border.fillColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        border.strokeColor = cgColor(strokeColor, opacity: overlay.opacity)
        border.lineWidth = max(1, CGFloat(overlay.style.lineWidth))
        border.lineJoin = .round
        border.lineDashPattern = mode == .outline ? nil : [8, 5]
        container.addSublayer(border)
        return container
    }

    private func overlayOutsidePath(
        focusFrame: CGRect,
        fullFrame: CGRect,
        shape: OverlayHighlightShape,
        cornerRadius: Double
    ) -> CGPath {
        let path = CGMutablePath()
        path.addRect(fullFrame)
        path.addPath(overlayFocusPath(focusFrame, shape: shape, cornerRadius: cornerRadius))
        return path
    }

    private func overlayFocusPath(
        _ frame: CGRect,
        shape: OverlayHighlightShape,
        cornerRadius: Double
    ) -> CGPath {
        switch shape {
        case .rectangle:
            CGPath(rect: frame, transform: nil)
        case .roundedRectangle:
            CGPath(
                roundedRect: frame,
                cornerWidth: min(CGFloat(cornerRadius), min(frame.width, frame.height) / 2),
                cornerHeight: min(CGFloat(cornerRadius), min(frame.width, frame.height) / 2),
                transform: nil
            )
        case .ellipse:
            CGPath(ellipseIn: frame, transform: nil)
        }
    }

    private func overlayTextLayer(_ overlay: OverlayItem, frame: CGRect) -> CALayer {
        let container = CALayer()
        container.frame = frame

        if let backgroundColor = overlay.style.backgroundColor {
            let background = CALayer()
            background.frame = container.bounds
            background.backgroundColor = cgColor(backgroundColor, opacity: overlay.opacity)
            background.cornerRadius = min(CGFloat(overlay.style.cornerRadius), min(frame.width, frame.height) / 2)
            container.addSublayer(background)
        }

        let textLayer = CATextLayer()
        textLayer.string = overlay.style.text
        textLayer.font = "Helvetica-Bold" as CFTypeRef
        textLayer.fontSize = CGFloat(overlay.style.fontSize)
        textLayer.foregroundColor = cgColor(overlay.style.textColor, opacity: overlay.opacity)
        textLayer.alignmentMode = .center
        textLayer.contentsScale = 2
        textLayer.isWrapped = true
        textLayer.frame = container.bounds.insetBy(dx: 12, dy: 8)
        container.addSublayer(textLayer)

        return container
    }

    private func overlayCalloutLayer(_ overlay: OverlayItem, frame: CGRect) -> CALayer {
        let container = CALayer()
        container.frame = frame

        let bubblePath = CGMutablePath()
        let bubbleRect = CGRect(x: 0, y: frame.height * 0.18, width: frame.width, height: frame.height * 0.82)
        bubblePath.addRoundedRect(in: bubbleRect, cornerWidth: min(18, bubbleRect.height / 2), cornerHeight: min(18, bubbleRect.height / 2))
        bubblePath.move(to: CGPoint(x: frame.width * 0.22, y: bubbleRect.minY))
        bubblePath.addLine(to: CGPoint(x: frame.width * 0.1, y: 0))
        bubblePath.addLine(to: CGPoint(x: frame.width * 0.34, y: bubbleRect.minY))

        let bubble = CAShapeLayer()
        bubble.frame = container.bounds
        bubble.path = bubblePath
        bubble.fillColor = cgColor(overlay.style.backgroundColor ?? RGBAColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 0.78), opacity: overlay.opacity)
        bubble.strokeColor = cgColor(overlay.style.strokeColor, opacity: overlay.opacity)
        bubble.lineWidth = max(1, CGFloat(overlay.style.lineWidth))
        container.addSublayer(bubble)

        let text = CATextLayer()
        text.string = overlay.style.text
        text.font = "Helvetica-Bold" as CFTypeRef
        text.fontSize = CGFloat(overlay.style.fontSize)
        text.foregroundColor = cgColor(overlay.style.textColor, opacity: overlay.opacity)
        text.alignmentMode = .center
        text.contentsScale = 2
        text.isWrapped = true
        text.frame = bubbleRect.insetBy(dx: 12, dy: 8)
        container.addSublayer(text)
        return container
    }

    private func overlayShapeLayer(_ overlay: OverlayItem, frame: CGRect, path: CGPath) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = frame
        layer.path = path
        layer.fillColor = overlay.style.fillColor.map { cgColor($0, opacity: overlay.opacity) }
        layer.strokeColor = cgColor(overlay.style.strokeColor, opacity: overlay.opacity)
        layer.lineWidth = CGFloat(overlay.style.lineWidth)
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    private func overlayImageLayer(_ overlay: OverlayItem, projectURL: URL, frame: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.opacity = Float(overlay.opacity)
        if let imagePath = overlay.style.imagePath,
           let image = loadOverlayImage(projectURL: projectURL, imagePath: imagePath) {
            layer.contents = image
            layer.contentsGravity = .resizeAspect
            layer.masksToBounds = true
            layer.cornerRadius = min(CGFloat(overlay.style.cornerRadius), min(frame.width, frame.height) / 2)
        }
        return layer
    }

    private func overlayLinePath(in size: CGSize, arrow: Bool) -> CGPath {
        let path = CGMutablePath()
        let start = CGPoint(x: 0, y: size.height * 0.2)
        let end = CGPoint(x: size.width, y: size.height * 0.8)
        path.move(to: start)
        path.addLine(to: end)
        if arrow {
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length: CGFloat = max(12, min(size.width, size.height) * 0.18)
            let spread: CGFloat = .pi / 7
            path.move(to: CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread)))
            path.addLine(to: end)
            path.addLine(to: CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread)))
        }
        return path
    }

    private func overlayFrame(_ normalizedFrame: NormalizedEditRect, renderSize: CGSize) -> CGRect {
        EditorNormalizedGeometry.renderFrame(for: normalizedFrame, renderSize: renderSize)
    }

    private func applyTiming(to layer: CALayer, overlay: OverlayItem) {
        let start = overlay.timeRange.startSeconds
        let duration = max(overlay.timeRange.durationSeconds, 0.05)
        let fadeIn = min(overlay.animation.fadeInSeconds, duration / 2)
        let fadeOut = min(overlay.animation.fadeOutSeconds, duration / 2)
        layer.opacity = 0

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        let visibleOpacity = NSNumber(value: overlay.opacity)
        var values: [NSNumber] = [fadeIn > 0 ? 0 : visibleOpacity]
        var keyTimes: [NSNumber] = [0]
        if fadeIn > 0 {
            values.append(visibleOpacity)
            keyTimes.append(NSNumber(value: fadeIn / duration))
        }
        let fadeOutStart = max(0, (duration - fadeOut) / duration)
        if fadeOutStart > (keyTimes.last?.doubleValue ?? 0) {
            values.append(visibleOpacity)
            keyTimes.append(NSNumber(value: fadeOutStart))
        }
        if fadeOut > 0 {
            values.append(0)
            keyTimes.append(1)
        } else if (keyTimes.last?.doubleValue ?? 0) < 1 {
            values.append(visibleOpacity)
            keyTimes.append(1)
        }
        opacity.values = values
        opacity.keyTimes = keyTimes
        opacity.beginTime = AVCoreAnimationBeginTimeAtZero + start
        opacity.duration = duration
        opacity.fillMode = .removed
        opacity.isRemovedOnCompletion = true
        layer.add(opacity, forKey: "overlay-opacity-\(overlay.id)")

        if overlay.animation.preset == .slideUp, fadeIn > 0 {
            let animation = CABasicAnimation(keyPath: "position.y")
            animation.fromValue = layer.position.y - 24
            animation.toValue = layer.position.y
            animation.beginTime = AVCoreAnimationBeginTimeAtZero + start
            animation.duration = fadeIn
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "overlay-slide-\(overlay.id)")
        } else if overlay.animation.preset == .scaleIn, fadeIn > 0 {
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = 0.92
            animation.toValue = 1
            animation.beginTime = AVCoreAnimationBeginTimeAtZero + start
            animation.duration = fadeIn
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "overlay-scale-\(overlay.id)")
        }
    }

    private func loadOverlayImage(projectURL: URL, imagePath: String) -> CGImage? {
        guard let imageURL = try? ProjectBundle.projectLocalFileURL(
            for: ProjectFile(relativePath: imagePath, role: .attachment),
            in: projectURL
        ) else {
            return nil
        }
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func annotationLayer(for annotation: AnnotationItem, renderSize: CGSize) -> CALayer {
        let points = annotation.canvasPoints(for: renderSize)
        let layer: CALayer
        switch annotation.kind {
        case .pen, .highlighter, .laser:
            layer = pathLayer(
                path: polyline(points, renderSize: renderSize),
                annotation: annotation,
                fillColor: nil
            )
        case .line:
            layer = pathLayer(
                path: endpointLine(points, renderSize: renderSize),
                annotation: annotation,
                fillColor: nil
            )
        case .arrow:
            layer = pathLayer(
                path: arrowPath(points, renderSize: renderSize),
                annotation: annotation,
                fillColor: nil
            )
        case .rectangle:
            let rect = flippedRect(points.boundingRect, renderSize: renderSize)
            layer = pathLayer(
                path: CGPath(rect: rect, transform: nil),
                annotation: annotation,
                fillColor: nil
            )
        case .ellipse:
            let rect = flippedRect(points.boundingRect, renderSize: renderSize)
            layer = pathLayer(
                path: CGPath(ellipseIn: rect, transform: nil),
                annotation: annotation,
                fillColor: nil
            )
        case .whiteboard, .blackboard:
            let rect = flippedRect(points.boundingRect, renderSize: renderSize)
            layer = pathLayer(
                path: CGPath(rect: rect, transform: nil),
                annotation: annotation,
                fillColor: annotation.fillColor
            )
        case .text:
            layer = textLayer(for: annotation, points: points, renderSize: renderSize)
        }
        applyTiming(to: layer, annotation: annotation)
        return layer
    }

    private func pathLayer(
        path: CGPath,
        annotation: AnnotationItem,
        fillColor: RGBAColor?
    ) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = .zero
        layer.path = path
        layer.fillColor = fillColor.map { cgColor($0, opacity: annotation.opacity) }
        layer.strokeColor = cgColor(annotation.color, opacity: annotation.opacity)
        layer.lineWidth = annotation.lineWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    private func textLayer(for annotation: AnnotationItem, points: [CGPoint], renderSize: CGSize) -> CALayer {
        guard let point = points.first else {
            return CALayer()
        }

        let style = annotation.textStyle ?? AnnotationTextStyle()
        let text = annotation.text ?? ""
        let lines = text.components(separatedBy: .newlines)
        let longestLineCount = lines.map(\.count).max() ?? text.count
        let width = max(CGFloat(longestLineCount) * style.fontSize * 0.62, style.fontSize * 2)
        let height = max(CGFloat(max(lines.count, 1)) * style.fontSize * 1.3, style.fontSize)

        let layer = CATextLayer()
        layer.string = text
        layer.fontSize = style.fontSize
        layer.font = fontName(for: style.weight) as CFTypeRef
        layer.foregroundColor = cgColor(annotation.color, opacity: annotation.opacity)
        layer.alignmentMode = .left
        layer.contentsScale = 2
        layer.isWrapped = true
        layer.frame = CGRect(
            x: point.x,
            y: renderSize.height - point.y - height,
            width: width,
            height: height
        )
        return layer
    }

    private func applyTiming(to layer: CALayer, annotation: AnnotationItem) {
        guard let timeRange = annotation.timeRange, timeRange.isValid else { return }
        layer.opacity = 0
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 1
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + timeRange.startSeconds
        animation.duration = max(timeRange.endSeconds - timeRange.startSeconds, 0.05)
        animation.fillMode = .removed
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: "annotation-\(annotation.id.uuidString)")
    }

    private func polyline(_ points: [CGPoint], renderSize: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: flippedPoint(first, renderSize: renderSize))
        for point in points.dropFirst() {
            path.addLine(to: flippedPoint(point, renderSize: renderSize))
        }
        return path
    }

    private func endpointLine(_ points: [CGPoint], renderSize: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: flippedPoint(first, renderSize: renderSize))
        path.addLine(to: flippedPoint(last, renderSize: renderSize))
        return path
    }

    private func arrowPath(_ points: [CGPoint], renderSize: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard let originalStart = points.first, let originalEnd = points.last else { return path }
        let start = flippedPoint(originalStart, renderSize: renderSize)
        let end = flippedPoint(originalEnd, renderSize: renderSize)
        guard start != end else { return path }

        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 18
        let spread: CGFloat = .pi / 7
        let left = CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        )
        let right = CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        )
        path.move(to: left)
        path.addLine(to: end)
        path.addLine(to: right)
        return path
    }

    private func flippedPoint(_ point: CGPoint, renderSize: CGSize) -> CGPoint {
        CGPoint(x: point.x, y: renderSize.height - point.y)
    }

    private func flippedRect(_ rect: CGRect, renderSize: CGSize) -> CGRect {
        CGRect(
            x: rect.minX,
            y: renderSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func cgColor(_ color: RGBAColor, opacity: Double) -> CGColor {
        CGColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha * opacity
        )
    }

    private func fontName(for weight: AnnotationTextWeight) -> String {
        switch weight {
        case .regular:
            "Helvetica"
        case .medium:
            "Helvetica-Medium"
        case .semibold:
            "Helvetica-Bold"
        case .bold:
            "Helvetica-Bold"
        }
    }

    private func insertWebcamOverlay(
        _ overlay: PictureInPictureOverlay,
        into composition: AVMutableComposition,
        duration: CMTime,
        renderSize: CGSize,
        camera: EditorCameraSettings
    ) async throws -> WebcamOverlayComposition {
        let webcamAsset = AVURLAsset(url: overlay.source.url)
        let webcamVideoTracks = try await webcamAsset.loadTracks(withMediaType: .video)
        guard let webcamVideoTrack = webcamVideoTracks.first else {
            throw RenderExportError.missingVideoTrack(overlay.source.relativePath)
        }

        guard let compositionWebcamTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RenderExportError.unableToCreateCompositionTrack
        }

        let webcamDuration = try await webcamAsset.load(.duration)
        try compositionWebcamTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: min(duration, webcamDuration)),
            of: webcamVideoTrack,
            at: .zero
        )

        let naturalSize = try await webcamVideoTrack.load(.naturalSize)
        let preferredTransform = try await webcamVideoTrack.load(.preferredTransform)
        let sourceDisplaySize = displaySize(naturalSize: naturalSize, preferredTransform: preferredTransform)
        let defaultState = webcamRenderState(
            placement: overlay.placement,
            sourceDisplaySize: sourceDisplaySize,
            preferredTransform: preferredTransform,
            renderSize: renderSize
        )

        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionWebcamTrack)
        instruction.setTransform(defaultState.transform, at: .zero)
        instruction.setCropRectangle(defaultState.geometry.cropRect, at: .zero)
        instruction.setOpacity(1, at: .zero)

        let durationSeconds = duration.seconds.isFinite ? max(0, duration.seconds) : 0
        for region in camera.enabledLayoutRegions {
            let startSeconds = min(max(region.range.startSeconds, 0), durationSeconds)
            let endSeconds = min(max(region.range.endSeconds, startSeconds), durationSeconds)
            guard endSeconds > startSeconds else { continue }
            let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
            let end = CMTime(seconds: endSeconds, preferredTimescale: 600)
            let transition = min(region.transitionSeconds, max(0, (endSeconds - startSeconds) / 2))

            if region.preset == .hidden {
                if region.animation == .fade, transition > 0 {
                    let inRange = CMTimeRange(start: start, duration: CMTime(seconds: transition, preferredTimescale: 600))
                    let outRange = CMTimeRange(
                        start: CMTime(seconds: max(startSeconds, endSeconds - transition), preferredTimescale: 600),
                        duration: CMTime(seconds: transition, preferredTimescale: 600)
                    )
                    instruction.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: inRange)
                    instruction.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: outRange)
                } else {
                    instruction.setOpacity(0, at: start)
                    instruction.setOpacity(1, at: end)
                }
                continue
            }

            let state = webcamRenderState(
                placement: region.resolvedPlacement(default: overlay.placement),
                sourceDisplaySize: sourceDisplaySize,
                preferredTransform: preferredTransform,
                renderSize: renderSize
            )
            if region.animation == .fade, transition > 0 {
                let inRange = CMTimeRange(start: start, duration: CMTime(seconds: transition, preferredTimescale: 600))
                instruction.setTransformRamp(fromStart: defaultState.transform, toEnd: state.transform, timeRange: inRange)
                let outRange = CMTimeRange(
                    start: CMTime(seconds: max(startSeconds, endSeconds - transition), preferredTimescale: 600),
                    duration: CMTime(seconds: transition, preferredTimescale: 600)
                )
                instruction.setTransformRamp(fromStart: state.transform, toEnd: defaultState.transform, timeRange: outRange)
            } else {
                instruction.setTransform(state.transform, at: start)
                instruction.setTransform(defaultState.transform, at: end)
            }
            instruction.setCropRectangle(state.geometry.cropRect, at: start)
            instruction.setCropRectangle(defaultState.geometry.cropRect, at: end)
            instruction.setOpacity(1, at: start)
        }

        return WebcamOverlayComposition(
            track: compositionWebcamTrack,
            instruction: instruction,
            geometry: defaultState.geometry
        )
    }

    private func webcamRenderState(
        placement: PictureInPicturePlacement,
        sourceDisplaySize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> WebcamRenderState {
        let geometry = placement.resolvedRenderGeometry(
            sourceSize: sourceDisplaySize,
            renderSize: renderSize
        )
        let horizontalScale = placement.isMirrored ? -geometry.sourceScale : geometry.sourceScale
        let translationX = placement.isMirrored ? geometry.videoFrame.maxX : geometry.videoFrame.minX
        let transform = preferredTransform
            .concatenating(CGAffineTransform(scaleX: horizontalScale, y: geometry.sourceScale))
            .concatenating(CGAffineTransform(translationX: translationX, y: geometry.videoFrame.minY))
        return WebcamRenderState(geometry: geometry, transform: transform)
    }

    private func insertClickSoundTrack(
        for clicks: [CursorClick],
        settings: EditorClickEffectSettings,
        duration: CMTime,
        into composition: AVMutableComposition,
        temporaryRenderFiles: inout [URL]
    ) async throws {
        guard settings.soundEnabled, settings.soundVolume > 0 else { return }
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else { return }

        let visibleClicks = clicks.filter {
            $0.phase == .down && $0.timestampSeconds >= 0 && $0.timestampSeconds <= durationSeconds
        }
        guard !visibleClicks.isEmpty else { return }

        let soundURL = try writeClickSoundTrack(clicks: visibleClicks, settings: settings, durationSeconds: durationSeconds)
        temporaryRenderFiles.append(soundURL)
        let asset = AVURLAsset(url: soundURL)
        _ = try await insertAudioTracks(from: asset, role: .all, into: composition, duration: duration)
    }

    private func writeClickSoundTrack(
        clicks: [CursorClick],
        settings: EditorClickEffectSettings,
        durationSeconds: Double
    ) throws -> URL {
        let sampleRate = 44_100.0
        let channelCount: AVAudioChannelCount = 2
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount) else {
            throw RenderExportError.unableToCreateCompositionTrack
        }

        let frameCount = AVAudioFrameCount(ceil(durationSeconds * sampleRate))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            throw RenderExportError.unableToCreateCompositionTrack
        }
        buffer.frameLength = frameCount

        let maxFrame = Int(frameCount)
        let volume = Float(settings.soundVolume)
        for click in clicks {
            let startFrame = max(0, Int(click.timestampSeconds * sampleRate))
            let toneFrameCount = Int(0.055 * sampleRate)
            let frequency = clickSoundFrequency(for: click.button)
            for frameOffset in 0..<toneFrameCount where startFrame + frameOffset < maxFrame {
                let t = Double(frameOffset) / sampleRate
                let progress = Double(frameOffset) / Double(max(toneFrameCount, 1))
                let envelope = Float(pow(max(0, 1 - progress), 2.2))
                let sample = Float(sin(2 * Double.pi * frequency * t)) * volume * envelope * 0.28
                for channel in 0..<Int(channelCount) {
                    let next = channels[channel][startFrame + frameOffset] + sample
                    channels[channel][startFrame + frameOffset] = min(1, max(-1, next))
                }
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-clicks-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        var fileSettings = format.settings
        fileSettings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: fileSettings)
        try file.write(from: buffer)
        return url
    }

    private func clickSoundFrequency(for button: CursorClickButton) -> Double {
        switch button {
        case .left:
            880
        case .right:
            620
        case .middle:
            740
        case .other:
            520
        }
    }

    private func insertAudioTracks(
        from asset: AVAsset,
        role: EditorAudioTrackRole,
        into composition: AVMutableComposition,
        duration: CMTime
    ) async throws -> [InsertedAudioTrack] {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var insertedTracks: [InsertedAudioTrack] = []
        for audioTrack in audioTracks {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw RenderExportError.unableToCreateCompositionTrack
            }

            let sourceDuration = try await asset.load(.duration)
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: min(duration, sourceDuration)),
                of: audioTrack,
                at: .zero
            )
            insertedTracks.append(InsertedAudioTrack(track: compositionAudioTrack, role: role))
        }
        return insertedTracks
    }

    private func insertBackgroundMusicTrack(
        _ settings: EditorBackgroundMusicSettings,
        projectURL: URL,
        into composition: AVMutableComposition,
        duration: CMTime
    ) async throws -> [InsertedAudioTrack] {
        let relativePath = settings.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relativePath.isEmpty else { return [] }
        let musicURL = try ProjectBundle.projectLocalFileURL(
            for: ProjectFile(relativePath: relativePath, role: .attachment),
            in: projectURL
        )
        let asset = AVURLAsset(url: musicURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else { return [] }
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RenderExportError.unableToCreateCompositionTrack
        }

        let sourceDuration = try await asset.load(.duration)
        let sourceDurationSeconds = max(0, sourceDuration.seconds.isFinite ? sourceDuration.seconds : 0)
        let renderDurationSeconds = max(0, duration.seconds.isFinite ? duration.seconds : 0)
        let startSeconds = min(max(0, settings.startSeconds), renderDurationSeconds)
        let desiredDurationSeconds = min(
            max(0, settings.durationSeconds ?? (renderDurationSeconds - startSeconds)),
            max(0, renderDurationSeconds - startSeconds)
        )
        guard sourceDurationSeconds > 0, desiredDurationSeconds > 0 else {
            return [InsertedAudioTrack(track: compositionTrack, role: .backgroundMusic)]
        }

        let sourceStartSeconds = min(settings.sourceStartSeconds, max(0, sourceDurationSeconds - 0.01))
        var outputCursorSeconds = startSeconds
        let outputEndSeconds = startSeconds + desiredDurationSeconds

        repeat {
            let sourceAvailableSeconds = max(0, sourceDurationSeconds - sourceStartSeconds)
            let segmentDurationSeconds = min(outputEndSeconds - outputCursorSeconds, sourceAvailableSeconds)
            guard segmentDurationSeconds > 0 else { break }

            try compositionTrack.insertTimeRange(
                CMTimeRange(
                    start: CMTime(seconds: sourceStartSeconds, preferredTimescale: 600),
                    duration: CMTime(seconds: segmentDurationSeconds, preferredTimescale: 600)
                ),
                of: audioTrack,
                at: CMTime(seconds: outputCursorSeconds, preferredTimescale: 600)
            )
            outputCursorSeconds += segmentDurationSeconds
        } while settings.loop && outputCursorSeconds < outputEndSeconds

        return [InsertedAudioTrack(track: compositionTrack, role: .backgroundMusic)]
    }

    private func audioTrackRole(for role: RenderMediaRole) -> EditorAudioTrackRole {
        switch role {
        case .microphoneAudio:
            .microphone
        case .systemAudio:
            .system
        default:
            .screen
        }
    }

    private func audioMix(
        for audioTracks: [InsertedAudioTrack],
        settings: EditorAudioSettings,
        duration: CMTime,
        hasVoiceAudio: Bool
    ) -> AVAudioMix? {
        guard !audioTracks.isEmpty else { return nil }

        let parameters = audioTracks.map { insertedTrack in
            let params = AVMutableAudioMixInputParameters(track: insertedTrack.track)
            let baseGain = baseGain(for: insertedTrack.role, settings: settings)
            params.setVolume(Float(baseGain), at: .zero)

            if insertedTrack.role == .backgroundMusic,
               let backgroundMusic = settings.backgroundMusic,
               backgroundMusic.duckUnderVoice,
               hasVoiceAudio {
                applyVolumeRamp(
                    to: params,
                    range: EditTimeRange(startSeconds: 0, durationSeconds: max(0, duration.seconds)),
                    baseGain: backgroundMusic.gain,
                    targetGain: backgroundMusic.duckedGain,
                    fadeInSeconds: min(backgroundMusic.fadeInSeconds, 1),
                    fadeOutSeconds: min(backgroundMusic.fadeOutSeconds, 1)
                )
            }

            for region in settings.enabledVolumeRegions where regionMatches(region.track, insertedTrack.role) {
                applyVolumeRamp(
                    to: params,
                    range: region.range,
                    baseGain: baseGain,
                    targetGain: region.gain,
                    fadeInSeconds: region.fadeInSeconds,
                    fadeOutSeconds: region.fadeOutSeconds
                )
            }
            return params
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }

    private func baseGain(for role: EditorAudioTrackRole, settings: EditorAudioSettings) -> Double {
        if role == .backgroundMusic {
            return settings.backgroundMusic?.gain ?? 1
        }
        let trackSettings = settings.trackSettings(for: role)
        if trackSettings.isMuted || settings.isSoloMuted(role: role) {
            return 0
        }
        return trackSettings.gain
    }

    private func regionMatches(_ regionRole: EditorAudioTrackRole, _ trackRole: EditorAudioTrackRole) -> Bool {
        regionRole == .all || regionRole == trackRole
    }

    private func applyVolumeRamp(
        to params: AVMutableAudioMixInputParameters,
        range: EditTimeRange,
        baseGain: Double,
        targetGain: Double,
        fadeInSeconds: Double,
        fadeOutSeconds: Double
    ) {
        let startSeconds = max(0, range.startSeconds)
        let endSeconds = max(startSeconds, range.endSeconds)
        let durationSeconds = max(0, endSeconds - startSeconds)
        guard durationSeconds > 0 else { return }

        let clampedFadeIn = min(max(0, fadeInSeconds), durationSeconds)
        let clampedFadeOut = min(max(0, fadeOutSeconds), max(0, durationSeconds - clampedFadeIn))
        let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let fadeInEnd = CMTime(seconds: startSeconds + clampedFadeIn, preferredTimescale: 600)
        let fadeOutStart = CMTime(seconds: endSeconds - clampedFadeOut, preferredTimescale: 600)
        let end = CMTime(seconds: endSeconds, preferredTimescale: 600)
        let base = Float(baseGain)
        let target = Float(targetGain)

        if clampedFadeIn > 0 {
            params.setVolumeRamp(
                fromStartVolume: base,
                toEndVolume: target,
                timeRange: CMTimeRange(start: start, end: fadeInEnd)
            )
        } else {
            params.setVolume(target, at: start)
        }

        if fadeOutStart > fadeInEnd {
            params.setVolume(target, at: fadeInEnd)
        }

        if clampedFadeOut > 0 {
            params.setVolumeRamp(
                fromStartVolume: target,
                toEndVolume: base,
                timeRange: CMTimeRange(start: fadeOutStart, end: end)
            )
        }
        params.setVolume(base, at: end)
    }

    private func displaySize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        displayGeometry(naturalSize: naturalSize, preferredTransform: preferredTransform).size
    }

    private func displayGeometry(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> DisplayGeometry {
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let normalize = CGAffineTransform(translationX: -transformed.minX, y: -transformed.minY)
        return DisplayGeometry(
            size: CGSize(width: abs(transformed.width), height: abs(transformed.height)),
            transform: preferredTransform.concatenating(normalize)
        )
    }

    private func presetName(for preset: RenderPreset) -> String {
        if preset.usesProRes {
            return AVAssetExportPresetAppleProRes422LPCM
        }

        if preset.codec == .hevc {
            return AVAssetExportPresetHEVCHighestQuality
        }

        switch preset.quality {
        case .medium:
            return AVAssetExportPresetMediumQuality
        case .highest:
            return AVAssetExportPresetHighestQuality
        }
    }

    private func avFileType(for fileType: RenderFileType) -> AVFileType {
        switch fileType {
        case .mp4:
            .mp4
        case .mov:
            .mov
        }
    }

    private func export(
        session: AVAssetExportSession,
        to destinationURL: URL,
        as fileType: RenderFileType,
        progress: RenderProgressHandler?
    ) async throws {
        let sessionBox = ExportSessionBox(session)
        let progressTask = Task { @MainActor in
            guard let progress else { return }
            progress(Double(sessionBox.session.progress))
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                progress(Double(sessionBox.session.progress))
            }
        }
        defer { progressTask.cancel() }

        do {
            try await session.export(to: destinationURL, as: avFileType(for: fileType))
            await progress?(1)
        } catch is CancellationError {
            session.cancelExport()
            throw RenderExportError.exportCancelled
        } catch {
            throw RenderExportError.exportFailed(error.localizedDescription)
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

private struct WebcamOverlayComposition {
    var track: AVMutableCompositionTrack
    var instruction: AVMutableVideoCompositionLayerInstruction
    var geometry: PictureInPictureRenderGeometry
}

private struct WebcamRenderState {
    var geometry: PictureInPictureRenderGeometry
    var transform: CGAffineTransform
}

private struct InsertedAudioTrack {
    var track: AVMutableCompositionTrack
    var role: EditorAudioTrackRole
}

private struct DisplayGeometry {
    var size: CGSize
    var transform: CGAffineTransform
}

public enum RenderExportError: Error, Equatable, LocalizedError, Sendable {
    case unableToCreateExportSession
    case unableToCreateCompositionTrack
    case missingVideoTrack(String)
    case exportFailed(String)
    case exportCancelled

    public var errorDescription: String? {
        switch self {
        case .unableToCreateExportSession:
            "Unable to create an AVFoundation export session."
        case .unableToCreateCompositionTrack:
            "Unable to create an AVFoundation composition track."
        case .missingVideoTrack(let path):
            "No video track found in \(path)."
        case .exportFailed(let message):
            message
        case .exportCancelled:
            "Render export was cancelled."
        }
    }
}
