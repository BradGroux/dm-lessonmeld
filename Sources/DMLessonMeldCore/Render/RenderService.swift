import AVFoundation
import CoreGraphics
import Foundation

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

enum RenderAudioBounds {
    static let clickSampleRate = 44_100.0
    static let clickToneDurationSeconds = 0.055
    static let clickAudioChunkFrames: AVAudioFrameCount = 16_384
    static let minimumLoopableSourceDurationSeconds = 0.25
    static let maxBackgroundMusicLoopInsertions = 2_000

    static func shouldLoopBackgroundMusic(
        sourceAvailableSeconds: Double,
        desiredDurationSeconds: Double,
        loopEnabled: Bool
    ) -> Bool {
        guard loopEnabled,
              sourceAvailableSeconds.isFinite,
              desiredDurationSeconds.isFinite,
              sourceAvailableSeconds >= minimumLoopableSourceDurationSeconds,
              desiredDurationSeconds > sourceAvailableSeconds else {
            return false
        }
        return estimatedBackgroundMusicLoopInsertions(
            sourceAvailableSeconds: sourceAvailableSeconds,
            desiredDurationSeconds: desiredDurationSeconds
        ) <= maxBackgroundMusicLoopInsertions
    }

    static func estimatedBackgroundMusicLoopInsertions(
        sourceAvailableSeconds: Double,
        desiredDurationSeconds: Double
    ) -> Int {
        guard sourceAvailableSeconds.isFinite,
              desiredDurationSeconds.isFinite,
              sourceAvailableSeconds > 0,
              desiredDurationSeconds > 0 else {
            return 0
        }
        return Int(ceil(desiredDurationSeconds / sourceAvailableSeconds))
    }
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
           plan.canvas.isDefault,
           plan.preset.resolution == .source,
           plan.preset.frameRate == .source {
            return try await exportSingleAsset(plan, progress: progress)
        }

        return try await exportComposition(plan, progress: progress)
    }

    private func exportSingleAsset(_ plan: RenderPlan, progress: RenderProgressHandler?) async throws -> URL {
        let asset = AVURLAsset(url: plan.screenVideo.url)
        guard let session = AVAssetExportSession(asset: asset, presetName: presetName(for: plan.preset)) else {
            throw RenderExportError.unableToCreateExportSession
        }

        try await RenderExportSessionRunner.export(session: session, to: plan.destinationURL, as: plan.preset.fileType, progress: progress)
        return plan.destinationURL
    }

    private func exportComposition(_ plan: RenderPlan, progress: RenderProgressHandler?) async throws -> URL {
        let composition = AVMutableComposition()
        let screenAsset = AVURLAsset(url: plan.screenVideo.url)
        let screenDuration = try await screenAsset.load(.duration)
        let screenVideoTracks = try await screenAsset.loadTracks(withMediaType: .video)
        try Task.checkCancellation()
        let interactionMetadata = try plan.cursorSource.map { try loadInteractionMetadata(from: $0) }
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

        let sourceDurationSeconds = screenDuration.seconds.isFinite ? max(0, screenDuration.seconds) : 0
        let timelineMapper = TimelineRetimingMapper(
            speedRegions: plan.speedRegions,
            sourceDurationSeconds: sourceDurationSeconds
        )
        let outputDuration = time(timelineMapper.outputDuration(forSourceDuration: sourceDurationSeconds))

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
        let screenNominalFrameRate = try await screenVideoTrack.load(.nominalFrameRate)
        let screenDisplay = displayGeometry(naturalSize: screenNaturalSize, preferredTransform: screenPreferredTransform)
        let canvasGeometry = outputCanvasGeometry(
            canvas: plan.canvas,
            sourceSize: screenDisplay.size,
            preset: plan.preset
        )
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
            duration: screenDuration,
            timelineMapper: timelineMapper
        )

        var layerInstructions = [screenInstruction]
        var webcamStyleSegments: [PictureInPictureStyleSegment] = []
        var retimedTracks = [compositionScreenTrack]
        retimedTracks += audioTracks.map(\.track)

        if let webcamOverlay = plan.webcamOverlay {
            let webcamOverlayComposition = try await insertWebcamOverlay(
                webcamOverlay,
                into: composition,
                duration: screenDuration,
                renderSize: renderSize,
                camera: plan.camera,
                timelineMapper: timelineMapper
            )
            layerInstructions.insert(webcamOverlayComposition.instruction, at: 0)
            webcamStyleSegments = webcamOverlayComposition.styleSegments
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
            try Task.checkCancellation()
            try await insertClickSoundTrack(
                for: interactionMetadata.clicks,
                settings: plan.cursor.clickEffects,
                duration: outputDuration,
                timelineMapper: timelineMapper,
                into: composition,
                temporaryRenderFiles: &temporaryRenderFiles
            )
        }

        instruction.layerInstructions = layerInstructions

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration(
            for: plan.preset.frameRate,
            sourceFrameRate: Double(screenNominalFrameRate)
        )
        videoComposition.instructions = [instruction]
        try Task.checkCancellation()
        try applyOverlayLayersIfNeeded(
            plan: plan,
            videoComposition: videoComposition,
            renderSize: renderSize,
            canvasGeometry: canvasGeometry,
            webcamStyleSegments: webcamStyleSegments,
            interactionMetadata: interactionMetadata,
            timelineMapper: timelineMapper
        )

        guard let session = AVAssetExportSession(asset: composition, presetName: presetName(for: plan.preset)) else {
            throw RenderExportError.unableToCreateExportSession
        }
        session.videoComposition = videoComposition
        session.audioMix = RenderAudioMixBuilder.mix(
            for: audioTracks,
            settings: plan.audio,
            duration: outputDuration,
            timelineMapper: timelineMapper,
            hasVoiceAudio: plan.audioSources.contains { $0.role == .microphoneAudio || $0.role == .systemAudio }
        )

        try await RenderExportSessionRunner.export(session: session, to: plan.destinationURL, as: plan.preset.fileType, progress: progress)
        return plan.destinationURL
    }

    private func insertWebcamOverlay(
        _ overlay: PictureInPictureOverlay,
        into composition: AVMutableComposition,
        duration: CMTime,
        renderSize: CGSize,
        camera: EditorCameraSettings,
        timelineMapper: TimelineRetimingMapper
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
            let mappedRange = timelineMapper.outputRange(
                forSourceRange: EditTimeRange(startSeconds: startSeconds, endSeconds: endSeconds)
            )
            let mappedStartSeconds = mappedRange.startSeconds
            let mappedEndSeconds = mappedRange.endSeconds
            let start = CMTime(seconds: mappedStartSeconds, preferredTimescale: 600)
            let end = CMTime(seconds: mappedEndSeconds, preferredTimescale: 600)
            let transition = min(region.transitionSeconds, max(0, mappedRange.durationSeconds / 2))

            if region.preset == .hidden {
                if region.animation == .fade, transition > 0 {
                    let inRange = CMTimeRange(start: start, duration: CMTime(seconds: transition, preferredTimescale: 600))
                    let outRange = CMTimeRange(
                        start: CMTime(seconds: max(mappedStartSeconds, mappedEndSeconds - transition), preferredTimescale: 600),
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
                    start: CMTime(seconds: max(mappedStartSeconds, mappedEndSeconds - transition), preferredTimescale: 600),
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
            styleSegments: PictureInPictureStyleTimeline.segments(
                overlay: overlay,
                camera: camera,
                sourceDisplaySize: sourceDisplaySize,
                renderSize: renderSize,
                durationSeconds: durationSeconds,
                timelineMapper: timelineMapper
            )
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
        timelineMapper: TimelineRetimingMapper,
        into composition: AVMutableComposition,
        temporaryRenderFiles: inout [URL]
    ) async throws {
        guard settings.soundEnabled, settings.soundVolume > 0 else { return }
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else { return }

        let visibleClicks = clicks.filter {
            $0.phase == .down && $0.timestampSeconds >= 0
        }.map {
            CursorClick(
                timestampSeconds: timelineMapper.outputTime(forSourceTime: $0.timestampSeconds),
                position: $0.position,
                button: $0.button,
                phase: $0.phase,
                clickCount: $0.clickCount
            )
        }.filter {
            $0.timestampSeconds <= durationSeconds
        }
        guard !visibleClicks.isEmpty else { return }

        let soundURL = try writeClickSoundTrack(clicks: visibleClicks, settings: settings, durationSeconds: durationSeconds)
        temporaryRenderFiles.append(soundURL)
        let asset = AVURLAsset(url: soundURL)
        _ = try await insertAudioTracks(from: asset, role: .all, into: composition, duration: duration)
    }

    func writeClickSoundTrack(
        clicks: [CursorClick],
        settings: EditorClickEffectSettings,
        durationSeconds: Double
    ) throws -> URL {
        let sampleRate = RenderAudioBounds.clickSampleRate
        let channelCount: AVAudioChannelCount = 2
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount) else {
            throw RenderExportError.unableToCreateCompositionTrack
        }

        let totalFrameCount = Int64(ceil(durationSeconds * sampleRate))
        guard totalFrameCount > 0 else {
            throw RenderExportError.unableToCreateCompositionTrack
        }
        let chunkFrameCapacity = min(
            RenderAudioBounds.clickAudioChunkFrames,
            AVAudioFrameCount(min(totalFrameCount, Int64(AVAudioFrameCount.max)))
        )
        guard chunkFrameCapacity > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCapacity),
              let channels = buffer.floatChannelData else {
            throw RenderExportError.unableToCreateCompositionTrack
        }

        struct ClickTone {
            var startFrame: Int64
            var endFrame: Int64
            var frequency: Double
        }

        let toneFrameCount = Int64(ceil(RenderAudioBounds.clickToneDurationSeconds * sampleRate))
        let volume = Float(settings.soundVolume)
        let tones = clicks.map { click in
            let startFrame = max(0, Int64(click.timestampSeconds * sampleRate))
            return ClickTone(
                startFrame: startFrame,
                endFrame: min(totalFrameCount, startFrame + toneFrameCount),
                frequency: clickSoundFrequency(for: click.button)
            )
        }
        .filter { $0.startFrame < totalFrameCount && $0.endFrame > $0.startFrame }
        .sorted { $0.startFrame < $1.startFrame }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-clicks-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        var fileSettings = format.settings
        fileSettings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: fileSettings)

        var firstRelevantToneIndex = 0
        var chunkStartFrame: Int64 = 0
        while chunkStartFrame < totalFrameCount {
            let remainingFrames = totalFrameCount - chunkStartFrame
            let chunkFrameCount = AVAudioFrameCount(min(Int64(chunkFrameCapacity), remainingFrames))
            let chunkEndFrame = chunkStartFrame + Int64(chunkFrameCount)

            for channel in 0..<Int(channelCount) {
                memset(channels[channel], 0, Int(chunkFrameCount) * MemoryLayout<Float>.stride)
            }
            buffer.frameLength = chunkFrameCount

            while firstRelevantToneIndex < tones.count,
                  tones[firstRelevantToneIndex].endFrame <= chunkStartFrame {
                firstRelevantToneIndex += 1
            }

            var toneIndex = firstRelevantToneIndex
            while toneIndex < tones.count, tones[toneIndex].startFrame < chunkEndFrame {
                let tone = tones[toneIndex]
                let toneStartOffset = max(Int64(0), chunkStartFrame - tone.startFrame)
                let toneEndOffset = min(toneFrameCount, chunkEndFrame - tone.startFrame)
                if toneEndOffset > toneStartOffset {
                    for toneFrameOffset in toneStartOffset..<toneEndOffset {
                        let chunkFrameOffset = Int(tone.startFrame + toneFrameOffset - chunkStartFrame)
                        let t = Double(toneFrameOffset) / sampleRate
                        let progress = Double(toneFrameOffset) / Double(max(toneFrameCount, 1))
                        let envelope = Float(pow(max(0, 1 - progress), 2.2))
                        let sample = Float(sin(2 * Double.pi * tone.frequency * t)) * volume * envelope * 0.28
                        for channel in 0..<Int(channelCount) {
                            let next = channels[channel][chunkFrameOffset] + sample
                            channels[channel][chunkFrameOffset] = min(1, max(-1, next))
                        }
                    }
                }
                toneIndex += 1
            }

            try file.write(from: buffer)
            chunkStartFrame = chunkEndFrame
        }

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
        let sourceDuration = try await asset.load(.duration)
        let sourceDurationSeconds = max(0, sourceDuration.seconds.isFinite ? sourceDuration.seconds : 0)
        let renderDurationSeconds = max(0, duration.seconds.isFinite ? duration.seconds : 0)
        let startSeconds = min(max(0, settings.startSeconds), renderDurationSeconds)
        let desiredDurationSeconds = min(
            max(0, settings.durationSeconds ?? (renderDurationSeconds - startSeconds)),
            max(0, renderDurationSeconds - startSeconds)
        )
        guard sourceDurationSeconds > 0, desiredDurationSeconds > 0 else { return [] }

        let sourceStartSeconds = min(settings.sourceStartSeconds, max(0, sourceDurationSeconds - 0.01))
        let sourceAvailableSeconds = max(0, sourceDurationSeconds - sourceStartSeconds)
        guard sourceAvailableSeconds > 0 else { return [] }
        if settings.loop,
           desiredDurationSeconds > sourceAvailableSeconds,
           sourceAvailableSeconds < RenderAudioBounds.minimumLoopableSourceDurationSeconds {
            return []
        }
        let shouldLoop = RenderAudioBounds.shouldLoopBackgroundMusic(
            sourceAvailableSeconds: sourceAvailableSeconds,
            desiredDurationSeconds: desiredDurationSeconds,
            loopEnabled: settings.loop
        )
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RenderExportError.unableToCreateCompositionTrack
        }
        var outputCursorSeconds = startSeconds
        let outputEndSeconds = startSeconds + desiredDurationSeconds

        repeat {
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
        } while shouldLoop && outputCursorSeconds < outputEndSeconds

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

    private func displaySize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        displayGeometry(naturalSize: naturalSize, preferredTransform: preferredTransform).size
    }

    private func outputCanvasGeometry(
        canvas: EditorCanvasSettings,
        sourceSize: CGSize,
        preset: RenderPreset
    ) -> EditorCanvasRenderGeometry {
        let baseGeometry = canvas.renderGeometry(sourceSize: sourceSize)
        let outputSize = preset.resolution.resolvedRenderSize(baseSize: baseGeometry.renderSize)
        return baseGeometry.scaled(to: outputSize)
    }

    private func frameDuration(for frameRate: RenderFrameRate, sourceFrameRate: Double) -> CMTime {
        let framesPerSecond = frameRate.framesPerSecond
            ?? (sourceFrameRate.isFinite && sourceFrameRate > 0 ? sourceFrameRate : 30)
        return CMTime(seconds: 1 / framesPerSecond, preferredTimescale: 60_000)
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


}



private struct WebcamOverlayComposition {
    var track: AVMutableCompositionTrack
    var instruction: AVMutableVideoCompositionLayerInstruction
    var styleSegments: [PictureInPictureStyleSegment]
}

private struct WebcamRenderState {
    var geometry: PictureInPictureRenderGeometry
    var transform: CGAffineTransform
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
