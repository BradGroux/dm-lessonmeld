import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import QuartzCore

extension AVFoundationRenderService {
    func applyOverlayLayersIfNeeded(
        plan: RenderPlan,
        videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        canvasGeometry: EditorCanvasRenderGeometry,
        webcamStyleSegments: [PictureInPictureStyleSegment],
        interactionMetadata: InteractionMetadataDocument?,
        timelineMapper: TimelineRetimingMapper
    ) throws {
        let overlayLayers = try overlayLayers(
            plan: plan,
            renderSize: renderSize,
            webcamStyleSegments: webcamStyleSegments,
            interactionMetadata: interactionMetadata,
            timelineMapper: timelineMapper
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
        webcamStyleSegments: [PictureInPictureStyleSegment],
        interactionMetadata: InteractionMetadataDocument?,
        timelineMapper: TimelineRetimingMapper
    ) throws -> [CALayer] {
        var layers: [CALayer] = []
        var screenBoundLayers: [CALayer] = []

        if let annotationSource = plan.annotationSource {
            try Task.checkCancellation()
            let store = try loadAnnotationStore(from: annotationSource)
            if store.isVisible {
                for annotation in store.annotations where annotation.isVisible {
                    try Task.checkCancellation()
                    screenBoundLayers.append(annotationLayer(for: annotation, renderSize: renderSize, timelineMapper: timelineMapper))
                }
            }
        }

        if let interactionMetadata {
            try Task.checkCancellation()
            screenBoundLayers.append(contentsOf: try cursorLayers(
                for: interactionMetadata,
                settings: plan.cursor,
                renderSize: renderSize,
                timelineMapper: timelineMapper
            ))
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
            applyOverlayZoomRegions(
                plan.zoomRegions,
                to: screenBoundContainer,
                renderSize: renderSize,
                timelineMapper: timelineMapper
            )
            layers.append(screenBoundContainer)
        }

        if !webcamStyleSegments.isEmpty {
            layers.append(contentsOf: pictureInPictureStyleLayers(
                for: webcamStyleSegments,
                renderSize: renderSize
            ))
        }

        if plan.webcamOverlay != nil {
            layers.append(contentsOf: cameraReactionLayers(
                for: plan.camera.enabledReactions,
                renderSize: renderSize,
                timelineMapper: timelineMapper
            ))
        }

        if let overlaySource = plan.overlaySource {
            try Task.checkCancellation()
            let store = try loadOverlayStore(from: overlaySource)
            if store.isVisible {
                let overlays = store.overlays
                    .filter(\.isEnabled)
                    .sorted { $0.zIndex < $1.zIndex }
                for overlay in overlays {
                    try Task.checkCancellation()
                    layers.append(overlayLayer(
                        for: overlay,
                        projectURL: plan.projectURL,
                        renderSize: renderSize,
                        timelineMapper: timelineMapper
                    ))
                }
            }
        }

        if let captionSource = plan.captionSource, plan.captions.burnInEnabled {
            try Task.checkCancellation()
            let transcript = try loadTranscript(from: captionSource)
            for segment in transcript.segments {
                try Task.checkCancellation()
                if let layer = captionLayer(
                    for: segment,
                    settings: plan.captions,
                    renderSize: renderSize,
                    timelineMapper: timelineMapper
                ) {
                    layers.append(layer)
                }
            }
        }

        if let interactionMetadata, plan.cursor.keyboardOverlay.isVisible {
            try Task.checkCancellation()
            layers.append(contentsOf: try keyboardLayers(
                for: interactionMetadata,
                settings: plan.cursor.keyboardOverlay,
                renderSize: renderSize,
                timelineMapper: timelineMapper
            ))
        }

        return layers
    }

    private func pictureInPictureStyleLayers(
        for segments: [PictureInPictureStyleSegment],
        renderSize: CGSize
    ) -> [CALayer] {
        var layers: [CALayer] = []

        for segment in segments where segment.placement.shadowEnabled {
            let shadowLayer = CAShapeLayer()
            shadowLayer.frame = segment.geometry.frame
            shadowLayer.path = pictureInPicturePath(
                frameShape: segment.placement.frameShape,
                bounds: shadowLayer.bounds,
                cornerRadius: segment.geometry.cornerRadius
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
            applyPictureInPictureStyleTiming(to: shadowLayer, segment: segment)
            layers.append(shadowLayer)
        }

        for segment in segments where segment.placement.borderEnabled {
            let borderWidth = max(1, min(renderSize.width, renderSize.height) * 0.0018)
            let borderLayer = CAShapeLayer()
            borderLayer.frame = segment.geometry.frame
            borderLayer.path = pictureInPicturePath(
                frameShape: segment.placement.frameShape,
                bounds: borderLayer.bounds,
                cornerRadius: segment.geometry.cornerRadius,
                inset: borderWidth / 2
            )
            borderLayer.fillColor = nil
            borderLayer.strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.68)
            borderLayer.lineWidth = borderWidth
            applyPictureInPictureStyleTiming(to: borderLayer, segment: segment)
            layers.append(borderLayer)
        }

        return layers
    }

    private func applyPictureInPictureStyleTiming(
        to layer: CALayer,
        segment: PictureInPictureStyleSegment
    ) {
        let start = segment.range.startSeconds
        let duration = max(segment.range.durationSeconds, 0.05)
        let fade = min(segment.transitionSeconds, duration / 2)
        layer.opacity = 0

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        if fade > 0 {
            let fadeOutStart = max(0, (duration - fade) / duration)
            opacity.values = [0, 1, 1, 0]
            opacity.keyTimes = [
                NSNumber(value: 0),
                NSNumber(value: fade / duration),
                NSNumber(value: fadeOutStart),
                NSNumber(value: 1)
            ]
        } else {
            opacity.values = [1, 1]
            opacity.keyTimes = [NSNumber(value: 0), NSNumber(value: 1)]
        }
        opacity.beginTime = AVCoreAnimationBeginTimeAtZero + start
        opacity.duration = duration
        opacity.fillMode = .removed
        opacity.isRemovedOnCompletion = true
        layer.add(opacity, forKey: "pip-style-\(segment.id)")
    }

    private func cameraReactionLayers(
        for reactions: [CameraReaction],
        renderSize: CGSize,
        timelineMapper: TimelineRetimingMapper
    ) -> [CALayer] {
        reactions.compactMap { reaction in
            let mappedRange = timelineMapper.outputRange(forSourceRange: reaction.range)
            guard mappedRange.durationSeconds > 0 else { return nil }
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

            let start = mappedRange.startSeconds
            let duration = mappedRange.durationSeconds
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

    func canvasScreenTransform(
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

    private func loadAnnotationStore(from source: RenderMediaSource) throws -> AnnotationStore {
        guard FileManager.default.fileExists(atPath: source.url.path) else {
            return AnnotationStore()
        }
        let data = try RenderSidecarLimits.data(contentsOf: source.url, displayPath: source.relativePath)
        let store = try DMLessonJSON.decoder().decode(AnnotationStore.self, from: data)
        try RenderSidecarLimits.checkAnnotationStore(store, displayPath: source.relativePath)
        return store
    }

    private func loadOverlayStore(from source: RenderMediaSource) throws -> OverlayStore {
        guard FileManager.default.fileExists(atPath: source.url.path) else {
            return OverlayStore()
        }
        let data = try RenderSidecarLimits.data(contentsOf: source.url, displayPath: source.relativePath)
        let store = try DMLessonJSON.decoder().decode(OverlayStore.self, from: data)
        try RenderSidecarLimits.checkOverlayStore(store, displayPath: source.relativePath)
        return store
    }

    private func loadTranscript(from source: RenderMediaSource) throws -> TranscriptDocument {
        let data = try RenderSidecarLimits.data(contentsOf: source.url, displayPath: source.relativePath)
        let transcript = try DMLessonJSON.decoder().decode(TranscriptDocument.self, from: data)
        try RenderSidecarLimits.checkTranscript(transcript, displayPath: source.relativePath)
        return transcript
    }

    func loadInteractionMetadata(from source: RenderMediaSource) throws -> InteractionMetadataDocument {
        let data = try RenderSidecarLimits.data(contentsOf: source.url, displayPath: source.relativePath)
        let metadata = try DMLessonJSON.decoder().decode(InteractionMetadataDocument.self, from: data)
        try RenderSidecarLimits.checkInteractionMetadata(metadata, displayPath: source.relativePath)
        return metadata
    }

    func loadEditDecisionListIfPresent(projectURL: URL) throws -> EditDecisionList? {
        guard EditDecisionListFile.exists(in: projectURL) else {
            return nil
        }
        return try EditDecisionListFile.load(fromProject: projectURL)
    }

    func applyZoomRegions(
        _ zoomRegions: [ZoomRegion],
        to instruction: AVMutableVideoCompositionLayerInstruction,
        baseTransform: CGAffineTransform,
        renderSize: CGSize,
        duration: CMTime,
        timelineMapper: TimelineRetimingMapper
    ) {
        guard !zoomRegions.isEmpty else { return }

        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds.isFinite, totalSeconds > 0 else { return }

        for region in zoomRegions.sorted(by: { $0.range.startSeconds < $1.range.startSeconds }) {
            let startSeconds = max(0, min(region.range.startSeconds, totalSeconds))
            let endSeconds = max(startSeconds, min(region.range.endSeconds, totalSeconds))
            guard endSeconds > startSeconds else { continue }

            let mappedRange = timelineMapper.outputRange(
                forSourceRange: EditTimeRange(startSeconds: startSeconds, endSeconds: endSeconds)
            )
            guard mappedRange.durationSeconds > 0 else { continue }
            let mappedStartSeconds = mappedRange.startSeconds
            let mappedEndSeconds = mappedRange.endSeconds
            let regionDuration = mappedRange.durationSeconds
            let rampDuration = zoomRampDuration(for: region, regionDuration: regionDuration)
            let zoomTransform = zoomTransform(for: region, baseTransform: baseTransform, renderSize: renderSize)

            if rampDuration > 0 {
                instruction.setTransformRamp(
                    fromStart: baseTransform,
                    toEnd: zoomTransform,
                    timeRange: timeRange(startSeconds: mappedStartSeconds, durationSeconds: rampDuration)
                )
            } else {
                instruction.setTransform(zoomTransform, at: time(mappedStartSeconds))
            }

            let holdStart = mappedStartSeconds + rampDuration
            let outStart = mappedEndSeconds - rampDuration
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
            instruction.setTransform(baseTransform, at: time(mappedEndSeconds))
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
        renderSize: CGSize,
        timelineMapper: TimelineRetimingMapper
    ) {
        guard !zoomRegions.isEmpty else { return }

        for region in zoomRegions.sorted(by: { $0.range.startSeconds < $1.range.startSeconds }) {
            let startSeconds = max(0, region.range.startSeconds)
            let endSeconds = max(startSeconds, region.range.endSeconds)
            guard endSeconds > startSeconds else { continue }

            let mappedRange = timelineMapper.outputRange(
                forSourceRange: EditTimeRange(startSeconds: startSeconds, endSeconds: endSeconds)
            )
            guard mappedRange.durationSeconds > 0 else { continue }
            let mappedStartSeconds = mappedRange.startSeconds
            let mappedEndSeconds = mappedRange.endSeconds
            let regionDuration = mappedRange.durationSeconds
            let rampDuration = zoomRampDuration(for: region, regionDuration: regionDuration)
            let zoomTransform = zoomTransform(for: region, baseTransform: .identity, renderSize: renderSize)
            let zoom3D = CATransform3DMakeAffineTransform(zoomTransform)
            let identity3D = CATransform3DIdentity

            if rampDuration > 0 {
                let zoomIn = CABasicAnimation(keyPath: "transform")
                zoomIn.fromValue = identity3D
                zoomIn.toValue = zoom3D
                zoomIn.beginTime = AVCoreAnimationBeginTimeAtZero + mappedStartSeconds
                zoomIn.duration = rampDuration
                zoomIn.timingFunction = zoomTimingFunction(for: region)
                zoomIn.fillMode = .forwards
                zoomIn.isRemovedOnCompletion = false
                layer.add(zoomIn, forKey: "overlay-zoom-in-\(region.id)")
            }

            let outStart = mappedEndSeconds - rampDuration
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

    func time(_ seconds: Double) -> CMTime {
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
        renderSize: CGSize,
        timelineMapper: TimelineRetimingMapper
    ) throws -> [CALayer] {
        var layers: [CALayer] = []

        if metadata.rendersCursorPointer,
           settings.pointerVisible,
           let cursorLayer = try animatedCursorLayer(
            for: metadata.cursorSamples,
            settings: settings,
            renderSize: renderSize,
            timelineMapper: timelineMapper
           ) {
            layers.append(cursorLayer)
        }

        if settings.clickEffects.rippleVisible {
            for click in metadata.clicks {
                try Task.checkCancellation()
                if let layer = clickLayer(
                    for: click,
                    settings: settings.clickEffects,
                    renderSize: renderSize,
                    timelineMapper: timelineMapper
                ) {
                    layers.append(layer)
                }
            }
        }

        return layers
    }

    private func animatedCursorLayer(
        for samples: [CursorSample],
        settings: EditorCursorSettings,
        renderSize: CGSize,
        timelineMapper: TimelineRetimingMapper
    ) throws -> CALayer? {
        try Task.checkCancellation()
        let visibleSamples = samples
            .sorted { $0.timestampSeconds < $1.timestampSeconds }
            .filter { timelineMapper.isSourceTimeRetained($0.timestampSeconds) }
            .map { sample in
                CursorSample(
                    timestampSeconds: timelineMapper.outputTime(forSourceTime: sample.timestampSeconds),
                    position: sample.position,
                    isVisible: sample.isVisible && !settings.hiddenRanges.contains { $0.contains(sample.timestampSeconds) }
                )
            }
        try Task.checkCancellation()
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

    private func clickLayer(
        for click: CursorClick,
        settings: EditorClickEffectSettings,
        renderSize: CGSize,
        timelineMapper: TimelineRetimingMapper
    ) -> CALayer? {
        guard click.phase == .down,
              timelineMapper.isSourceTimeRetained(click.timestampSeconds) else {
            return nil
        }

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
        let timestampSeconds = timelineMapper.outputTime(forSourceTime: click.timestampSeconds)
        group.beginTime = AVCoreAnimationBeginTimeAtZero + timestampSeconds
        group.duration = settings.durationSeconds
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .removed
        group.isRemovedOnCompletion = true
        layer.add(group, forKey: "click-\(timestampSeconds)")

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
        renderSize: CGSize,
        timelineMapper: TimelineRetimingMapper
    ) throws -> [CALayer] {
        var layers: [CALayer] = []
        for event in metadata.keystrokes {
            try Task.checkCancellation()
            if let layer = keyboardLayer(
                for: event,
                settings: settings,
                renderSize: renderSize,
                timelineMapper: timelineMapper
            ) {
                layers.append(layer)
            }
        }
        return layers
    }

    private func keyboardLayer(
        for event: KeyboardMetadataEvent,
        settings: EditorKeyboardOverlaySettings,
        renderSize: CGSize,
        timelineMapper: TimelineRetimingMapper
    ) -> CALayer? {
        guard event.phase == .down,
              !event.isRepeat,
              timelineMapper.isSourceTimeRetained(event.timestampSeconds),
              let label = keyboardLabel(for: event) else {
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
        let timestampSeconds = timelineMapper.outputTime(forSourceTime: event.timestampSeconds)
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + timestampSeconds
        animation.duration = 0.9
        animation.fillMode = .removed
        animation.isRemovedOnCompletion = true
        container.add(animation, forKey: "keyboard-\(timestampSeconds)-\(event.keyCode)")
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
        renderSize: CGSize,
        timelineMapper: TimelineRetimingMapper
    ) -> CALayer? {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, segment.endSeconds > segment.startSeconds else {
            return nil
        }
        let mappedStartSeconds = timelineMapper.outputTime(forSourceTime: segment.startSeconds)
        let mappedEndSeconds = timelineMapper.outputTime(forSourceTime: segment.endSeconds)
        guard mappedEndSeconds > mappedStartSeconds else { return nil }
        let mappedDurationSeconds = mappedEndSeconds - mappedStartSeconds

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
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + mappedStartSeconds
        animation.duration = mappedDurationSeconds
        animation.fillMode = .removed
        animation.isRemovedOnCompletion = true
        container.add(animation, forKey: "caption-\(segment.id)")
        return container
    }

    private func overlayLayer(
        for overlay: OverlayItem,
        projectURL: URL,
        renderSize: CGSize,
        timelineMapper: TimelineRetimingMapper
    ) -> CALayer {
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
        applyTiming(to: layer, overlay: overlay, timelineMapper: timelineMapper)
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

    private func applyTiming(
        to layer: CALayer,
        overlay: OverlayItem,
        timelineMapper: TimelineRetimingMapper
    ) {
        let mappedRange = timelineMapper.outputRange(forSourceRange: overlay.timeRange)
        let start = mappedRange.startSeconds
        let duration = mappedRange.durationSeconds
        layer.opacity = 0
        guard duration > 0 else { return }
        let fadeIn = min(overlay.animation.fadeInSeconds, duration / 2)
        let fadeOut = min(overlay.animation.fadeOutSeconds, duration / 2)

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

    private func annotationLayer(
        for annotation: AnnotationItem,
        renderSize: CGSize,
        timelineMapper: TimelineRetimingMapper
    ) -> CALayer {
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
        applyTiming(to: layer, annotation: annotation, timelineMapper: timelineMapper)
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

    private func applyTiming(
        to layer: CALayer,
        annotation: AnnotationItem,
        timelineMapper: TimelineRetimingMapper
    ) {
        guard let timeRange = annotation.timeRange, timeRange.isValid else { return }
        let startSeconds = timelineMapper.outputTime(forSourceTime: timeRange.startSeconds)
        let endSeconds = timelineMapper.outputTime(forSourceTime: timeRange.endSeconds)
        layer.opacity = 0
        guard endSeconds > startSeconds else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 1
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + startSeconds
        animation.duration = endSeconds - startSeconds
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

}
