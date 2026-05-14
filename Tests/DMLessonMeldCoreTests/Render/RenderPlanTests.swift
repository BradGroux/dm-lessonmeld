import AVFoundation
import CoreMedia
import CoreVideo
import DMLessonMeldCore
import Foundation
import ImageIO
import Testing

@Suite("Render plans")
struct RenderPlanTests {
    @Test("Builds a render plan from a project manifest without touching media files")
    func buildsPlanFromManifest() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let destinationURL = temp.url.appendingPathComponent("exports/lesson.mp4")

        let manifest = ProjectManifest(
            metadata: LessonMetadata(courseTitle: "Course", lessonTitle: "Lesson"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                webcam: ProjectFile(relativePath: "media/webcam.mov", role: .webcamVideo, mimeType: "video/quicktime"),
                microphoneAudio: ProjectFile(relativePath: "media/mic.m4a", role: .microphoneAudio, mimeType: "audio/mp4")
            ),
            markers: [
                ProjectTimelineMarker(id: "chapter-1", kind: .chapter, timeSeconds: 0, title: "Start")
            ]
        )
        try ProjectBundle.writeManifest(manifest, to: projectURL)

        let inspection = try AVFoundationRenderService().inspect(
            projectURL: projectURL,
            destinationURL: destinationURL
        )

        let plan = try #require(inspection.plan)
        #expect(inspection.lessonTitle == "Lesson")
        #expect(inspection.hasWebcamOverlay)
        #expect(inspection.audioSourceCount == 1)
        #expect(inspection.issues.isEmpty)
        #expect(plan.screenVideo.url == projectURL.appendingPathComponent("media/screen.mp4"))
        #expect(plan.webcamOverlay?.placement == .defaultBottomTrailing)
        #expect(plan.webcamOverlay?.source.url == projectURL.appendingPathComponent("media/webcam.mov"))
        #expect(plan.audioSources.map(\.role) == [.microphoneAudio])
        #expect(plan.markers.map(\.id) == ["chapter-1"])
    }

    @Test("Render inspection loads project editor canvas settings")
    func renderInspectionLoadsEditorCanvasSettings() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let destinationURL = temp.url.appendingPathComponent("exports/lesson.mp4")
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Canvas Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4")
                )
            ),
            to: projectURL
        )
        let settings = EditorSettings(
            canvas: EditorCanvasSettings(
                aspectRatio: .portrait9x16,
                background: EditorCanvasBackground(style: .gradient, primaryColor: .purple, secondaryColor: .blue),
                paddingRatio: 0.14,
                insetRatio: 0.03,
                cornerRadiusRatio: 0.05,
                shadow: EditorCanvasShadow(isEnabled: true, opacity: 0.48)
            )
        )
        try EditorSettingsFile.save(settings, toProject: projectURL)

        let inspection = try AVFoundationRenderService().inspect(
            projectURL: projectURL,
            destinationURL: destinationURL
        )

        let plan = try #require(inspection.plan)
        #expect(plan.canvas == settings.canvas)
        #expect(!plan.canvas.isDefault)
    }

    @Test("Render inspection loads audio settings and blocks unsupported speed regions")
    func renderInspectionLoadsAudioSettingsAndBlocksSpeedRegions() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let destinationURL = temp.url.appendingPathComponent("exports/lesson.mp4")
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Audio Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                    microphoneAudio: ProjectFile(relativePath: "media/mic.m4a", role: .microphoneAudio, mimeType: "audio/mp4"),
                    systemAudio: ProjectFile(relativePath: "media/system.m4a", role: .systemAudio, mimeType: "audio/mp4")
                )
            ),
            to: projectURL
        )
        let audioSettings = EditorAudioSettings(
            screenAudio: EditorAudioTrackSettings(gain: 0.8),
            microphoneAudio: EditorAudioTrackSettings(gain: 1.1, isSoloed: true),
            systemAudio: EditorAudioTrackSettings(gain: 0.2, isMuted: true),
            backgroundMusic: EditorBackgroundMusicSettings(relativePath: "audio/assets/intro.m4a", startSeconds: 1, durationSeconds: 5),
            volumeRegions: [
                EditorAudioVolumeRegion(
                    id: "duck",
                    track: .backgroundMusic,
                    range: EditTimeRange(startSeconds: 2, endSeconds: 4),
                    gain: 0.12
                )
            ]
        )
        try EditorSettingsFile.save(EditorSettings(audio: audioSettings), toProject: projectURL)
        try EditDecisionListFile.save(
            EditDecisionList(
                id: "lesson-edit",
                sourceDurationSeconds: 10,
                speedRegions: [
                    SpeedRegion(
                        id: "speed-typing",
                        range: EditTimeRange(startSeconds: 4, endSeconds: 7),
                        playbackRate: 2
                    )
                ]
            ),
            toProject: projectURL
        )

        let inspection = try AVFoundationRenderService().inspect(
            projectURL: projectURL,
            destinationURL: destinationURL
        )

        let plan = try #require(inspection.plan)
        #expect(plan.audio == audioSettings)
        #expect(plan.audioSources.map(\.role) == [.microphoneAudio, .systemAudio])
        #expect(plan.speedRegions.map(\.id) == ["speed-typing"])
        #expect(inspection.issues.contains {
            $0.severity == .error && $0.path == "speedRegions[0]"
        })
    }

    @Test("Validation can check missing media only when requested")
    func validationCanSkipFileExistence() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Lesson"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "missing-screen.mp4", role: .screenVideo),
                webcam: ProjectFile(relativePath: "missing-webcam.mp4", role: .webcamVideo)
            )
        )
        let plan = try RenderPlan.make(
            manifest: manifest,
            projectURL: projectURL,
            destinationURL: temp.url.appendingPathComponent("lesson.mov"),
            preset: RenderPreset(fileType: .mov)
        )

        #expect(plan.validate().isEmpty)

        let issues = plan.validate(options: RenderValidationOptions(checkFileExistence: true))
        #expect(issues.filter { $0.severity == .error }.count == 2)
        #expect(issues.map(\.path).contains("missing-screen.mp4"))
        #expect(issues.map(\.path).contains("missing-webcam.mp4"))
    }

    @Test("Rejects render plans with media paths outside the project")
    func rejectsRenderPlansWithExternalMediaPaths() throws {
        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Unsafe"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "/tmp/secret.mp4", role: .screenVideo)
            )
        )

        #expect(throws: ProjectBundleError.self) {
            try RenderPlan.make(
                manifest: manifest,
                projectURL: URL(fileURLWithPath: "/tmp/Lesson.dmlm"),
                destinationURL: URL(fileURLWithPath: "/tmp/lesson.mp4")
            )
        }
    }

    @Test("Validation checks annotation and overlay timing and normalized coordinates")
    func validationChecksAnnotationsAndOverlays() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let annotationsURL = projectURL.appendingPathComponent("annotations.json")
        let overlaysURL = projectURL.appendingPathComponent("overlays.json")
        try DMLessonJSON.encoder().encode(AnnotationStore(annotations: [
            AnnotationItem(
                displayID: 0,
                kind: .arrow,
                points: [CGPoint(x: 0, y: 0)],
                normalizedPoints: [NormalizedAnnotationPoint(x: 1.2, y: 0.5)],
                coordinateSpace: .normalizedCapture,
                timeRange: AnnotationTimeRange(startSeconds: 4, endSeconds: 2),
                color: .yellow
            ),
            AnnotationItem(
                displayID: 0,
                kind: .text,
                points: [CGPoint(x: 12, y: 34)],
                color: .white,
                text: "Legacy"
            )
        ])).write(to: annotationsURL, options: [.atomic])
        try DMLessonJSON.encoder().encode(OverlayStore(overlays: [
            OverlayItem(
                id: "bad-range",
                kind: .text,
                timeRange: EditTimeRange(startSeconds: 3, durationSeconds: -1),
                frame: NormalizedEditRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2)
            ),
            OverlayItem(
                id: "missing-image",
                kind: .image,
                timeRange: EditTimeRange(startSeconds: 0, durationSeconds: 2),
                frame: NormalizedEditRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                style: OverlayStyle(imagePath: "overlays/assets/missing.png")
            )
        ])).write(to: overlaysURL, options: [.atomic])
        let plan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo),
                    annotations: ProjectFile(relativePath: "annotations.json", role: .annotations, mimeType: "application/json"),
                    overlays: ProjectFile(relativePath: "overlays.json", role: .overlays, mimeType: "application/json")
                )
            ),
            projectURL: projectURL,
            destinationURL: temp.url.appendingPathComponent("lesson.mp4")
        )

        let issues = plan.validate()

        #expect(issues.contains {
            $0.severity == .error && $0.path == "annotations[0].timeRange"
        })
        #expect(issues.contains {
            $0.severity == .error && $0.path == "annotations[0].normalizedPoints"
        })
        #expect(issues.contains {
            $0.severity == .warning && $0.path == "annotations[1].points"
        })
        #expect(issues.contains {
            $0.severity == .error && $0.path == "overlays[0].timeRange"
        })
        #expect(issues.contains {
            $0.severity == .error && $0.path == "overlays/assets/missing.png"
        })
    }

    @Test("Validation rejects mismatched destination extension and existing output")
    func validationRejectsBadDestination() throws {
        let temp = try TemporaryDirectory()
        let destinationURL = temp.url.appendingPathComponent("lesson.mov")
        try Data("existing".utf8).write(to: destinationURL)

        let plan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo)
                )
            ),
            projectURL: temp.url,
            destinationURL: destinationURL,
            preset: RenderPreset(fileType: .mp4)
        )

        let issues = plan.validate(options: RenderValidationOptions(checkDestinationDoesNotExist: true))

        #expect(issues.contains {
            $0.message == "Render destination extension must match mp4."
        })
        #expect(issues.contains {
            $0.message == "Render destination already exists."
        })
    }

    @Test("Missing screen video is reported through inspection")
    func missingScreenVideoReportsInspectionIssue() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        try ProjectBundle.writeManifest(
            ProjectManifest(metadata: LessonMetadata(lessonTitle: "No Screen")),
            to: projectURL
        )

        let inspection = try AVFoundationRenderService().inspect(
            projectURL: projectURL,
            destinationURL: temp.url.appendingPathComponent("lesson.mp4")
        )

        #expect(inspection.plan == nil)
        #expect(inspection.issues == [
            RenderValidationIssue(
                severity: .error,
                message: "Project manifest does not reference a screen video."
            )
        ])
    }

    @Test("Render plans round-trip through Codable")
    func renderPlanCodableRoundTrip() throws {
        let plan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo),
                    systemAudio: ProjectFile(relativePath: "system.m4a", role: .systemAudio)
                )
            ),
            projectURL: URL(fileURLWithPath: "/tmp/Lesson.dmlm"),
            destinationURL: URL(fileURLWithPath: "/tmp/lesson.mp4")
        )

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(RenderPlan.self, from: data)

        #expect(decoded == plan)
    }

    @Test("Circle webcam placement always resolves to square")
    func circleWebcamPlacementResolvesToSquare() {
        let placement = PictureInPicturePlacement(
            corner: .bottomTrailing,
            widthRatio: 0.25,
            marginRatio: 0.04,
            aspectRatio: .widescreen16x9,
            frameShape: .circle
        )

        let size = placement.resolvedSize(
            sourceSize: CGSize(width: 1920, height: 1080),
            targetWidth: 480
        )

        #expect(placement.effectiveAspectRatio == .square1x1)
        #expect(size == CGSize(width: 480, height: 480))
    }

    @Test("Non-circle webcam placement preserves chosen aspect")
    func nonCircleWebcamPlacementPreservesChosenAspect() {
        let placement = PictureInPicturePlacement(
            corner: .bottomTrailing,
            widthRatio: 0.25,
            marginRatio: 0.04,
            aspectRatio: .portrait2x3,
            frameShape: .roundedRectangle
        )

        let size = placement.resolvedSize(
            sourceSize: CGSize(width: 1920, height: 1080),
            targetWidth: 400
        )

        #expect(placement.effectiveAspectRatio == .portrait2x3)
        #expect(size == CGSize(width: 400, height: 600))
    }

    @Test("Webcam render geometry fills the requested frame and crops overflow")
    func webcamRenderGeometryFillsRequestedFrame() {
        let placement = PictureInPicturePlacement(
            corner: .bottomLeading,
            widthRatio: 0.5,
            marginRatio: 0,
            aspectRatio: .square1x1,
            frameShape: .roundedRectangle,
            cornerRadius: 18,
            isMirrored: true,
            borderEnabled: true,
            shadowEnabled: true
        )

        let geometry = placement.resolvedRenderGeometry(
            sourceSize: CGSize(width: 400, height: 200),
            renderSize: CGSize(width: 200, height: 100)
        )

        #expect(geometry.frame == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(geometry.cropRect == geometry.frame)
        #expect(geometry.videoFrame == CGRect(x: -50, y: 0, width: 200, height: 100))
        #expect(geometry.sourceScale == 0.5)
        #expect(geometry.cornerRadius == 18)
    }

    @Test("Webcam render geometry places top trailing frames and clamps rounded corners")
    func webcamRenderGeometryPlacesTopTrailingFrame() {
        let placement = PictureInPicturePlacement(
            corner: .topTrailing,
            widthRatio: 0.25,
            marginRatio: 0.1,
            aspectRatio: .widescreen16x9,
            frameShape: .roundedRectangle,
            cornerRadius: 999
        )

        let geometry = placement.resolvedRenderGeometry(
            sourceSize: CGSize(width: 1920, height: 1080),
            renderSize: CGSize(width: 800, height: 600)
        )

        #expect(geometry.frame == CGRect(x: 540, y: 427.5, width: 200, height: 112.5))
        #expect(geometry.videoFrame == geometry.frame)
        #expect(geometry.cornerRadius == 56.25)
    }

    @Test("Circle webcam render geometry uses a square frame and circular radius")
    func circleWebcamRenderGeometryUsesCircularFrame() {
        let placement = PictureInPicturePlacement(
            corner: .bottomTrailing,
            widthRatio: 0.2,
            marginRatio: 0.04,
            aspectRatio: .widescreen16x9,
            frameShape: .circle,
            cornerRadius: 12
        )

        let geometry = placement.resolvedRenderGeometry(
            sourceSize: CGSize(width: 640, height: 480),
            renderSize: CGSize(width: 1000, height: 500)
        )

        #expect(geometry.frame == CGRect(x: 780, y: 20, width: 200, height: 200))
        #expect(geometry.cropRect == geometry.frame)
        #expect(geometry.cornerRadius == 100)
    }

    @Test("Exports synthetic project media with webcam picture-in-picture")
    func exportsSyntheticProjectMediaWithWebcamOverlay() async throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let mediaURL = projectURL.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)

        let screenURL = mediaURL.appendingPathComponent("screen.mp4")
        let webcamURL = mediaURL.appendingPathComponent("webcam.mp4")
        let backgroundURL = projectURL.appendingPathComponent("backgrounds/canvas-background.png")
        let cursorURL = projectURL.appendingPathComponent("cursor-metadata.json")
        let annotationsURL = projectURL.appendingPathComponent("annotations.json")
        let overlaysURL = projectURL.appendingPathComponent("overlays.json")
        let transcriptURL = projectURL.appendingPathComponent("transcript.json")
        let outputURL = temp.url.appendingPathComponent("exports/lesson.mp4")

        try await SyntheticVideoWriter.write(
            outputURL: screenURL,
            size: CGSize(width: 160, height: 90),
            color: (red: 28, green: 38, blue: 58)
        )
        try await SyntheticVideoWriter.write(
            outputURL: webcamURL,
            size: CGSize(width: 64, height: 64),
            color: (red: 240, green: 186, blue: 45)
        )
        try SyntheticImageWriter.write(
            outputURL: backgroundURL,
            size: CGSize(width: 48, height: 48),
            color: CGColor(red: 0.42, green: 0.22, blue: 0.9, alpha: 1)
        )
        try DMLessonJSON.encoder().encode(InteractionMetadataDocument(
            captureSize: CGSize(width: 160, height: 90),
            cursorSamples: [
                CursorSample(timestampSeconds: 0, position: NormalizedCapturePoint(x: 0.2, y: 0.25)),
                CursorSample(timestampSeconds: 0.4, position: NormalizedCapturePoint(x: 0.55, y: 0.45)),
                CursorSample(timestampSeconds: 0.8, position: NormalizedCapturePoint(x: 0.78, y: 0.62))
            ],
            clicks: [
                CursorClick(timestampSeconds: 0.42, position: NormalizedCapturePoint(x: 0.55, y: 0.45), button: .left, phase: .down)
            ],
            keystrokes: [
                KeyboardMetadataEvent(
                    timestampSeconds: 0.55,
                    keyCode: 1,
                    characters: "s",
                    modifiers: [.command],
                    phase: .down
                )
            ]
        )).write(to: cursorURL, options: [.atomic])
        try DMLessonJSON.encoder().encode(AnnotationStore(annotations: [
            AnnotationItem(
                displayID: 0,
                kind: .rectangle,
                points: [CGPoint(x: 18, y: 18), CGPoint(x: 118, y: 60)],
                color: .yellow,
                lineWidth: 5
            ),
            AnnotationItem(
                displayID: 0,
                kind: .text,
                points: [CGPoint(x: 26, y: 68)],
                color: .white,
                text: "Lesson",
                textStyle: AnnotationTextStyle(fontSize: 18, weight: .bold)
            )
        ])).write(to: annotationsURL, options: [.atomic])
        try DMLessonJSON.encoder().encode(OverlayStore(overlays: [
            OverlayItem(
                id: "overlay-title",
                kind: .text,
                timeRange: EditTimeRange(startSeconds: 0.1, durationSeconds: 0.6),
                frame: NormalizedEditRect(x: 0.12, y: 0.1, width: 0.48, height: 0.16),
                opacity: 0.92,
                zIndex: 10,
                style: OverlayStyle(
                    text: "Key idea",
                    fontSize: 18,
                    textColor: .white,
                    fillColor: RGBAColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 0.75),
                    strokeColor: .yellow
                ),
                animation: OverlayAnimation(fadeInSeconds: 0.1, fadeOutSeconds: 0.1, preset: .scaleIn)
            ),
            OverlayItem(
                id: "highlight-1",
                kind: .highlight,
                timeRange: EditTimeRange(startSeconds: 0.2, durationSeconds: 0.5),
                frame: NormalizedEditRect(x: 0.24, y: 0.18, width: 0.36, height: 0.3),
                opacity: 0.65,
                zIndex: 11,
                style: OverlayStyle(
                    fillColor: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.58),
                    strokeColor: .yellow,
                    cornerRadius: 12,
                    shadowEnabled: false,
                    highlightMode: .spotlight,
                    highlightShape: .roundedRectangle,
                    blurRadius: 10,
                    featherRadius: 18
                )
            )
        ])).write(to: overlaysURL, options: [.atomic])
        try DMLessonJSON.encoder().encode(TranscriptDocument(
            language: "en",
            title: "Synthetic Lesson",
            segments: [
                TranscriptSegment(
                    id: "caption-1",
                    startSeconds: 0,
                    endSeconds: 0.8,
                    text: "Caption burn-in works"
                )
            ]
        )).write(to: transcriptURL, options: [.atomic])
        try EditDecisionListFile.save(
            EditDecisionList(
                id: "lesson-edit",
                sourceMediaURL: screenURL,
                sourceDurationSeconds: 1,
                zoomRegions: [
                    ZoomRegion(
                        id: "zoom-1",
                        range: EditTimeRange(startSeconds: 0.1, durationSeconds: 0.5),
                        focusRect: NormalizedEditRect(x: 0.22, y: 0.2, width: 0.45, height: 0.45),
                        scale: 1.55
                    )
                ]
            ),
            toProject: projectURL
        )
        let canvasSettings = EditorSettings(
            canvas: EditorCanvasSettings(
                aspectRatio: .square1x1,
                background: EditorCanvasBackground(
                    style: .image,
                    primaryColor: .purple,
                    imagePath: "backgrounds/canvas-background.png"
                ),
                paddingRatio: 0.08,
                cornerRadiusRatio: 0.06,
                shadow: EditorCanvasShadow(isEnabled: true, opacity: 0.5)
            ),
            cursor: EditorCursorSettings(
                pointerStyle: .touchDot,
                smoothMovement: false,
                hiddenRanges: [EditTimeRange(startSeconds: 0.7, endSeconds: 0.9)],
                clickEffects: EditorClickEffectSettings(soundEnabled: true, soundVolume: 0.5)
            ),
            camera: EditorCameraSettings(
                defaultPlacement: PictureInPicturePlacement(
                    corner: .topLeading,
                    widthRatio: 0.28,
                    marginRatio: 0.04,
                    aspectRatio: .square1x1,
                    frameShape: .circle,
                    isMirrored: true,
                    borderEnabled: true,
                    shadowEnabled: true
                ),
                layoutRegions: [
                    CameraLayoutRegion(
                        id: "camera-hide",
                        range: EditTimeRange(startSeconds: 0.25, durationSeconds: 0.2),
                        preset: .hidden,
                        animation: .fade,
                        transitionSeconds: 0.05
                    ),
                    CameraLayoutRegion(
                        id: "camera-full",
                        range: EditTimeRange(startSeconds: 0.55, durationSeconds: 0.25),
                        preset: .fullCamera,
                        animation: .fade,
                        transitionSeconds: 0.05
                    )
                ],
                reactions: [
                    CameraReaction(
                        id: "camera-reaction",
                        range: EditTimeRange(startSeconds: 0.35, durationSeconds: 0.3),
                        text: "👍"
                    )
                ]
            )
        )
        try EditorSettingsFile.save(canvasSettings, toProject: projectURL)

        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Synthetic Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                    webcam: ProjectFile(relativePath: "media/webcam.mp4", role: .webcamVideo, mimeType: "video/mp4"),
                    cursorMetadata: ProjectFile(relativePath: "cursor-metadata.json", role: .cursorMetadata, mimeType: "application/json"),
                    annotations: ProjectFile(relativePath: "annotations.json", role: .annotations, mimeType: "application/json"),
                    overlays: ProjectFile(relativePath: "overlays.json", role: .overlays, mimeType: "application/json"),
                    transcripts: [
                        ProjectFile(relativePath: "transcript.json", role: .transcript, mimeType: "application/json")
                    ]
                )
            ),
            to: projectURL
        )

        let inspection = try AVFoundationRenderService().inspect(
            projectURL: projectURL,
            destinationURL: outputURL
        )
        #expect(inspection.hasCursorEffects)
        #expect(inspection.hasAnnotations)
        #expect(inspection.hasOverlays)
        #expect(inspection.hasCaptions)
        #expect(inspection.hasZoomRegions)
        #expect(inspection.plan?.cursorSource?.url == cursorURL)
        #expect(inspection.plan?.annotationSource?.url == annotationsURL)
        #expect(inspection.plan?.overlaySource?.url == overlaysURL)
        #expect(inspection.plan?.captionSource?.url == transcriptURL)
        #expect(inspection.plan?.zoomRegions.map(\.id) == ["zoom-1"])
        #expect(inspection.plan?.canvas == canvasSettings.canvas)
        #expect(inspection.plan?.cursor == canvasSettings.cursor)
        #expect(inspection.plan?.camera == canvasSettings.camera)
        #expect(inspection.plan?.webcamOverlay?.placement == canvasSettings.camera?.defaultPlacement)
        var plan = try #require(inspection.plan)
        plan.webcamOverlay?.placement = PictureInPicturePlacement(
            corner: .bottomTrailing,
            widthRatio: 0.32,
            marginRatio: 0.04,
            aspectRatio: .square1x1,
            frameShape: .circle,
            cornerRadius: 64,
            isMirrored: true,
            borderEnabled: true,
            shadowEnabled: true
        )

        let renderedURL = try await AVFoundationRenderService().export(plan: plan)

        let attributes = try FileManager.default.attributesOfItem(atPath: renderedURL.path)
        let byteCount = try #require(attributes[.size] as? Int64)
        #expect(byteCount > 0)
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-render-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private enum SyntheticVideoWriter {
    static func write(
        outputURL: URL,
        size: CGSize,
        color: (red: UInt8, green: UInt8, blue: UInt8)
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        #expect(writer.canAdd(input))
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<15 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let pixelBuffer = try makePixelBuffer(size: size, color: color)
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: 15)
            #expect(adaptor.append(pixelBuffer, withPresentationTime: time))
        }

        input.markAsFinished()
        try await writer.finishWritingOrThrow()
    }

    private static func makePixelBuffer(
        size: CGSize,
        color: (red: UInt8, green: UInt8, blue: UInt8)
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw SyntheticVideoWriterError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw SyntheticVideoWriterError.pixelBufferBaseAddressMissing
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let row = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            let rowStart = row.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let pixel = rowStart.advanced(by: x * 4)
                pixel[0] = color.blue
                pixel[1] = color.green
                pixel[2] = color.red
                pixel[3] = 255
            }
        }

        return pixelBuffer
    }
}

private enum SyntheticImageWriter {
    static func write(outputURL: URL, size: CGSize, color: CGColor) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let bitmapContext = try #require(context)
        bitmapContext.setFillColor(color)
        bitmapContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(bitmapContext.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

private extension AVAssetWriter {
    func finishWritingOrThrow() async throws {
        let writerBox = AssetWriterBox(self)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            finishWriting {
                if let error = writerBox.writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private final class AssetWriterBox: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}

private enum SyntheticVideoWriterError: Error {
    case pixelBufferCreationFailed(CVReturn)
    case pixelBufferBaseAddressMissing
}
