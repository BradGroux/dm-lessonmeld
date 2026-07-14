import AVFoundation
import CoreMedia
import CoreVideo
@testable import DMLessonMeldCore
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

    @Test("Render plan preserves embedded system audio metadata")
    func renderPlanPreservesEmbeddedSystemAudioMetadata() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let destinationURL = temp.url.appendingPathComponent("exports/lesson.mp4")

        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Embedded Audio"),
            media: ProjectMedia(
                screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                embeddedAudio: ProjectEmbeddedAudio(screenVideo: [.systemAudio])
            )
        )

        let plan = try RenderPlan.make(
            manifest: manifest,
            projectURL: projectURL,
            destinationURL: destinationURL
        )

        #expect(plan.embeddedAudio?.screenVideo == [.systemAudio])
        #expect(plan.audioSources.isEmpty)
        #expect(plan.screenVideo.relativePath == "screen.mp4")
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

    @Test("Render inspection loads audio settings and accepts speed regions")
    func renderInspectionLoadsAudioSettingsAndAcceptsSpeedRegions() throws {
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
        #expect(!inspection.issues.contains {
            $0.severity == .error && ($0.path?.hasPrefix("speedRegions") ?? false)
        })
    }

    @Test("Render plan compiles trim and enabled cuts into retained source ranges")
    func renderPlanCompilesRetainedSourceRanges() throws {
        let plan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Edited Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo)
                )
            ),
            projectURL: URL(fileURLWithPath: "/tmp/Lesson.dmlm"),
            destinationURL: URL(fileURLWithPath: "/tmp/lesson.mp4"),
            editDecisionList: EditDecisionList(
                id: "lesson-edit",
                sourceDurationSeconds: 10,
                trimRange: EditTimeRange(startSeconds: 1, endSeconds: 9),
                cuts: [
                    TimelineCut(id: "first", range: EditTimeRange(startSeconds: 2, endSeconds: 4)),
                    TimelineCut(id: "disabled", range: EditTimeRange(startSeconds: 5, endSeconds: 6), isEnabled: false),
                    TimelineCut(id: "second", range: EditTimeRange(startSeconds: 7, endSeconds: 8))
                ]
            )
        )

        #expect(plan.retainedSourceRanges == [
            EditTimeRange(startSeconds: 1, endSeconds: 2),
            EditTimeRange(startSeconds: 4, endSeconds: 7),
            EditTimeRange(startSeconds: 8, endSeconds: 9)
        ])
    }

    @Test("Render plan preserves trim-only edits and ignores disabled-only cuts")
    func renderPlanHandlesTrimOnlyAndDisabledCuts() throws {
        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Edited Lesson"),
            media: ProjectMedia(screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo))
        )
        let projectURL = URL(fileURLWithPath: "/tmp/Lesson.dmlm")
        let destinationURL = URL(fileURLWithPath: "/tmp/lesson.mp4")

        let trimOnlyPlan = try RenderPlan.make(
            manifest: manifest,
            projectURL: projectURL,
            destinationURL: destinationURL,
            editDecisionList: EditDecisionList(
                id: "trim-only",
                sourceDurationSeconds: 10,
                trimRange: EditTimeRange(startSeconds: 2, endSeconds: 6)
            )
        )
        let disabledCutPlan = try RenderPlan.make(
            manifest: manifest,
            projectURL: projectURL,
            destinationURL: destinationURL,
            editDecisionList: EditDecisionList(
                id: "disabled-cut",
                sourceDurationSeconds: 10,
                cuts: [
                    TimelineCut(
                        id: "disabled",
                        range: EditTimeRange(startSeconds: 2, endSeconds: 6),
                        isEnabled: false
                    )
                ]
            )
        )

        #expect(trimOnlyPlan.retainedSourceRanges == [EditTimeRange(startSeconds: 2, endSeconds: 6)])
        #expect(disabledCutPlan.retainedSourceRanges == nil)
    }

    @Test("Render plan drops cut markers and maps retained markers to output time")
    func renderPlanMapsMarkersToOutputTime() throws {
        let plan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Marked Lesson"),
                media: ProjectMedia(screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo)),
                markers: [
                    ProjectTimelineMarker(id: "intro", kind: .chapter, timeSeconds: 0.5, title: "Intro"),
                    ProjectTimelineMarker(id: "removed", kind: .retake, timeSeconds: 1.5, title: "Removed"),
                    ProjectTimelineMarker(id: "middle", kind: .chapter, timeSeconds: 3, title: "Middle"),
                    ProjectTimelineMarker(id: "ending", kind: .segment, timeSeconds: 5, title: "Ending")
                ]
            ),
            projectURL: URL(fileURLWithPath: "/tmp/Lesson.dmlm"),
            destinationURL: URL(fileURLWithPath: "/tmp/lesson.mp4"),
            editDecisionList: EditDecisionList(
                id: "marked-edit",
                sourceDurationSeconds: 6,
                cuts: [
                    TimelineCut(id: "remove-retake", range: EditTimeRange(startSeconds: 1, endSeconds: 2))
                ],
                speedRegions: [
                    SpeedRegion(
                        id: "fast-middle",
                        range: EditTimeRange(startSeconds: 2, endSeconds: 4),
                        playbackRate: 2
                    )
                ]
            )
        )

        #expect(plan.markers.map(\.id) == ["intro", "middle", "ending"])
        #expect(plan.markers.map(\.timeSeconds) == [0.5, 1.5, 3])
    }

    @Test("Render plan rejects invalid retained edit decisions")
    func renderPlanRejectsInvalidRetainedEditDecisions() {
        #expect(throws: RenderPlanError.self) {
            try RenderPlan.make(
                manifest: ProjectManifest(
                    metadata: LessonMetadata(lessonTitle: "Invalid Edit"),
                    media: ProjectMedia(screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo))
                ),
                projectURL: URL(fileURLWithPath: "/tmp/Lesson.dmlm"),
                destinationURL: URL(fileURLWithPath: "/tmp/lesson.mp4"),
                editDecisionList: EditDecisionList(
                    id: "invalid-edit",
                    sourceDurationSeconds: 6,
                    cuts: [
                        TimelineCut(
                            id: "invalid-cut",
                            range: EditTimeRange(startSeconds: .nan, durationSeconds: 1)
                        )
                    ]
                )
            )
        }
    }

    @Test("Render validation rejects overlapping speed regions")
    func renderValidationRejectsOverlappingSpeedRegions() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let destinationURL = temp.url.appendingPathComponent("exports/lesson.mp4")
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Speed Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4")
                )
            ),
            to: projectURL
        )
        try EditDecisionListFile.save(
            EditDecisionList(
                id: "lesson-edit",
                sourceDurationSeconds: 8,
                speedRegions: [
                    SpeedRegion(
                        id: "speed-a",
                        range: EditTimeRange(startSeconds: 1, endSeconds: 4),
                        playbackRate: 1.5
                    ),
                    SpeedRegion(
                        id: "speed-b",
                        range: EditTimeRange(startSeconds: 3, endSeconds: 6),
                        playbackRate: 0.75
                    )
                ]
            ),
            toProject: projectURL
        )

        let inspection = try AVFoundationRenderService().inspect(
            projectURL: projectURL,
            destinationURL: destinationURL
        )

        #expect(inspection.issues.contains {
            $0.severity == .error &&
                $0.path == "speedRegions[1].range" &&
                $0.message == "Speed regions must not overlap."
        })
    }

    @Test("Render caption source ignores non JSON transcript sidecars")
    func renderCaptionSourceIgnoresNonJSONTranscriptSidecars() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let destinationURL = temp.url.appendingPathComponent("exports/lesson.mp4")
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("media"), withIntermediateDirectories: true)
        try Data("video".utf8).write(to: projectURL.appendingPathComponent("media/screen.mp4"))
        try Data("# Transcript".utf8).write(to: projectURL.appendingPathComponent("transcript.md"))
        try Data(#"{"title":"Transcript","segments":[]}"#.utf8).write(to: projectURL.appendingPathComponent("transcript.json"))
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Caption Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                    transcripts: [
                        ProjectFile(relativePath: "transcript.md", role: .transcript, mimeType: "text/markdown"),
                        ProjectFile(relativePath: "transcript.json", role: .transcript, mimeType: "application/json")
                    ]
                )
            ),
            to: projectURL
        )

        let inspection = try AVFoundationRenderService().inspect(
            projectURL: projectURL,
            destinationURL: destinationURL
        )

        #expect(inspection.plan?.captionSource?.relativePath == "transcript.json")
    }

    @Test("Timeline retiming mapper converts source times to output times")
    func timelineRetimingMapperConvertsSourceTimesToOutputTimes() {
        let mapper = TimelineRetimingMapper(
            speedRegions: [
                SpeedRegion(
                    id: "fast",
                    range: EditTimeRange(startSeconds: 2, endSeconds: 4),
                    playbackRate: 2
                ),
                SpeedRegion(
                    id: "slow",
                    range: EditTimeRange(startSeconds: 6, endSeconds: 8),
                    playbackRate: 0.5
                )
            ],
            sourceDurationSeconds: 10
        )

        let mappedRange = mapper.outputRange(forSourceRange: EditTimeRange(startSeconds: 1, endSeconds: 5))

        #expect(mapper.outputTime(forSourceTime: 1) == 1)
        #expect(mapper.outputTime(forSourceTime: 3) == 2.5)
        #expect(mapper.outputTime(forSourceTime: 5) == 4)
        #expect(mapper.outputTime(forSourceTime: 7) == 7)
        #expect(mapper.outputDuration(forSourceDuration: 10) == 11)
        #expect(mappedRange == EditTimeRange(startSeconds: 1, endSeconds: 4))
    }

    @Test("Timeline retiming mapper removes cuts before applying speed regions")
    func timelineRetimingMapperRemovesCutsBeforeSpeedRegions() {
        let mapper = TimelineRetimingMapper(
            speedRegions: [
                SpeedRegion(
                    id: "fast",
                    range: EditTimeRange(startSeconds: 1, endSeconds: 5),
                    playbackRate: 2
                )
            ],
            retainedSourceRanges: [
                EditTimeRange(startSeconds: 0, endSeconds: 2),
                EditTimeRange(startSeconds: 4, endSeconds: 8)
            ],
            sourceDurationSeconds: 10
        )

        #expect(mapper.outputTime(forSourceTime: 1.5) == 1.25)
        #expect(mapper.outputTime(forSourceTime: 3) == 1.5)
        #expect(mapper.outputTime(forSourceTime: 4.5) == 1.75)
        #expect(mapper.outputTime(forSourceTime: 7) == 4)
        #expect(mapper.outputDuration(forSourceDuration: 10) == 5)
        #expect(!mapper.isSourceTimeRetained(3))
        #expect(mapper.isSourceTimeRetained(4.5))
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

    @Test("Render preset defaults keep legacy JSON readable and validate advanced formats")
    func renderPresetDefaultsAndAdvancedFormatValidation() throws {
        let legacy = try DMLessonJSON.decoder().decode(
            RenderPreset.self,
            from: Data(#"{"fileType":"mp4","quality":"highest"}"#.utf8)
        )
        #expect(legacy.resolution == .source)
        #expect(legacy.frameRate == .source)
        #expect(legacy.codec == .h264)
        #expect(legacy.hardwareAccelerationEnabled)

        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let plan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Unsupported"),
                media: ProjectMedia(screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo))
            ),
            projectURL: projectURL,
            destinationURL: temp.url.appendingPathComponent("lesson.mp4"),
            preset: RenderPreset(codec: .proRes, alphaChannelEnabled: true, animatedGIFEnabled: true)
        )

        let messages = plan.validate().map(\.message)
        #expect(messages.contains("ProRes export requires MOV output."))
        #expect(messages.contains("Alpha-channel export is not available in this build. Disable alpha until the renderer has an alpha-capable pipeline."))
        #expect(messages.contains("Animated GIF export is not available in this build. Use MP4 or MOV until the image-sequence renderer is implemented."))

        let proResPlan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "ProRes"),
                media: ProjectMedia(screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo))
            ),
            projectURL: projectURL,
            destinationURL: temp.url.appendingPathComponent("lesson.mov"),
            preset: RenderPreset(fileType: .mov, codec: .proRes)
        )
        #expect(proResPlan.validate().isEmpty)
    }

    @Test("Render preset resolution and frame rate drive composition output")
    func renderPresetResolutionAndFrameRateDriveCompositionOutput() async throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let mediaURL = projectURL.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        let screenURL = mediaURL.appendingPathComponent("screen.mp4")
        let outputURL = temp.url.appendingPathComponent("exports/lesson.mp4")
        try await SyntheticVideoWriter.write(
            outputURL: screenURL,
            size: CGSize(width: 320, height: 180),
            color: (red: 20, green: 96, blue: 160),
            frameCount: 60,
            fps: 30
        )
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Preset Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4")
                )
            ),
            to: projectURL
        )
        let plan = try AVFoundationRenderService().makePlan(
            projectURL: projectURL,
            destinationURL: outputURL,
            preset: RenderPreset(resolution: .p720, frameRate: .fps24)
        )

        #expect(plan.validate(options: .export).isEmpty)
        let renderedURL = try await AVFoundationRenderService().export(plan: plan)
        let track = try await firstVideoTrack(renderedURL)
        let naturalSize = try await track.load(.naturalSize)
        let nominalFrameRate = try await track.load(.nominalFrameRate)

        #expect(naturalSize == CGSize(width: 1280, height: 720))
        #expect(abs(nominalFrameRate - 24) < 0.5)
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

    @Test("Validation rejects direct render plan source URLs outside the project")
    func validationRejectsDirectRenderPlanExternalURLs() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let externalURL = temp.url.appendingPathComponent("external.mp4")
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("media"), withIntermediateDirectories: true)
        try Data("project video".utf8).write(to: projectURL.appendingPathComponent("media/screen.mp4"))
        try Data("external video".utf8).write(to: externalURL)

        let plan = RenderPlan(
            projectURL: projectURL,
            destinationURL: temp.url.appendingPathComponent("lesson.mp4"),
            screenVideo: RenderMediaSource(
                role: .screenVideo,
                relativePath: "media/screen.mp4",
                url: externalURL,
                mimeType: "video/mp4"
            )
        )

        let issues = plan.validate(options: .export)

        #expect(issues.contains {
            $0.severity == .error &&
                $0.path == "media/screen.mp4" &&
                $0.message == "screenVideo source URL must match its project-local relative path."
        })
    }

    @Test("Validation rejects excessive final canvas dimensions")
    func validationRejectsExcessiveFinalCanvasDimensions() {
        let projectURL = URL(fileURLWithPath: "/tmp/Lesson.dmlm")
        let plan = RenderPlan(
            projectURL: projectURL,
            destinationURL: URL(fileURLWithPath: "/tmp/lesson.mp4"),
            preset: RenderPreset(resolution: .p2160),
            screenVideo: RenderMediaSource(
                role: .screenVideo,
                relativePath: "screen.mp4",
                url: projectURL.appendingPathComponent("screen.mp4"),
                mimeType: "video/mp4"
            ),
            canvas: EditorCanvasSettings(
                aspectRatio: .custom,
                customSize: EditorCanvasCustomSize(width: 7_680, height: 16)
            )
        )

        let issues = plan.validate()

        #expect(issues.contains {
            $0.severity == .error &&
                $0.path == "canvas" &&
                $0.message.contains("Canvas render dimensions")
        })
    }

    @Test("Final canvas dimension guard enforces finite sane even bounds")
    func finalCanvasDimensionGuardEnforcesBounds() {
        let invalidSizes = [
            CGSize(width: CGFloat.nan, height: 1_080),
            CGSize(width: 14, height: 1_080),
            CGSize(width: 1_919, height: 1_080),
            CGSize(width: 7_682, height: 1_080)
        ]

        for size in invalidSizes {
            #expect(!RenderPlanValidator.canvasRenderDimensionIssues(size).isEmpty)
        }
        #expect(RenderPlanValidator.canvasRenderDimensionIssues(
            CGSize(width: 1_920, height: 1_080)
        ).isEmpty)
    }

    @Test("Validation rejects negative normalized origins in direct render plans")
    func validationRejectsNegativeNormalizedOrigins() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        var focusRect = NormalizedEditRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        focusRect.x = -0.1
        let plan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo)
                )
            ),
            projectURL: projectURL,
            destinationURL: temp.url.appendingPathComponent("lesson.mp4"),
            editDecisionList: EditDecisionList(
                id: "edits",
                zoomRegions: [
                    ZoomRegion(
                        id: "bad-origin",
                        range: EditTimeRange(startSeconds: 0, durationSeconds: 1),
                        focusRect: focusRect,
                        scale: 2
                    )
                ]
            )
        )

        let issues = plan.validate()

        #expect(issues.contains {
            $0.severity == .error && $0.path == "zoomRegions[0].focusRect"
        })
    }

    @Test("Decoded normalized edit rectangles are clamped")
    func decodedNormalizedEditRectsAreClamped() throws {
        let decoded = try DMLessonJSON.decoder().decode(
            NormalizedEditRect.self,
            from: Data(#"{"x":-0.5,"y":1.5,"width":2,"height":-1}"#.utf8)
        )

        #expect(decoded.x == 0)
        #expect(decoded.y == 1)
        #expect(decoded.width == 1)
        #expect(decoded.height == 0)
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

    @Test("Validation rejects oversized render sidecars")
    func validationRejectsOversizedRenderSidecars() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let annotationsURL = projectURL.appendingPathComponent("annotations.json")
        try Data(repeating: UInt8(ascii: "{"), count: RenderSidecarLimits.maxSidecarBytes + 1)
            .write(to: annotationsURL, options: [.atomic])

        let plan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo),
                    annotations: ProjectFile(relativePath: "annotations.json", role: .annotations, mimeType: "application/json")
                )
            ),
            projectURL: projectURL,
            destinationURL: temp.url.appendingPathComponent("lesson.mp4")
        )

        let issues = plan.validate()

        #expect(issues.contains {
            $0.severity == .error &&
                $0.path == "annotations.json" &&
                $0.message.contains("too large to render safely")
        })
    }

    @Test("Validation rejects render sidecars above item limits")
    func validationRejectsRenderSidecarsAboveItemLimits() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let overlaysURL = projectURL.appendingPathComponent("overlays.json")
        let overlays = (0...RenderSidecarLimits.maxOverlays).map {
            OverlayItem(
                id: "overlay-\($0)",
                kind: .text,
                timeRange: EditTimeRange(startSeconds: 0, durationSeconds: 1),
                frame: NormalizedEditRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2)
            )
        }
        try DMLessonJSON.encoder().encode(OverlayStore(overlays: overlays))
            .write(to: overlaysURL, options: [.atomic])

        let plan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo),
                    overlays: ProjectFile(relativePath: "overlays.json", role: .overlays, mimeType: "application/json")
                )
            ),
            projectURL: projectURL,
            destinationURL: temp.url.appendingPathComponent("lesson.mp4")
        )

        let issues = plan.validate()

        #expect(issues.contains {
            $0.severity == .error &&
                $0.path == "overlays.json" &&
                $0.message.contains("contains too many overlays")
        })
    }

    @Test("Validation rejects cursor metadata above item limits")
    func validationRejectsCursorMetadataAboveItemLimits() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let cursorURL = projectURL.appendingPathComponent("cursor-metadata.json")
        let clicks = (0...RenderSidecarLimits.maxCursorClicks).map { index in
            CursorClick(
                timestampSeconds: Double(index) / 60,
                position: NormalizedCapturePoint(x: 0.5, y: 0.5),
                button: .left,
                phase: .down
            )
        }
        try DMLessonJSON.encoder().encode(InteractionMetadataDocument(
            captureSize: CGSize(width: 1280, height: 720),
            clicks: clicks
        )).write(to: cursorURL, options: [.atomic])

        let plan = try RenderPlan.make(
            manifest: ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Lesson"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo),
                    cursorMetadata: ProjectFile(relativePath: "cursor-metadata.json", role: .cursorMetadata, mimeType: "application/json")
                )
            ),
            projectURL: projectURL,
            destinationURL: temp.url.appendingPathComponent("lesson.mp4")
        )

        let issues = plan.validate()

        #expect(issues.contains {
            $0.severity == .error &&
                $0.path == "cursor-metadata.json.clicks" &&
                $0.message.contains("contains too many clicks")
        })
    }

    @Test("Click sound writer handles longer timelines with bounded buffers")
    func clickSoundWriterHandlesLongerTimelinesWithBoundedBuffers() async throws {
        let soundURL = try AVFoundationRenderService().writeClickSoundTrack(
            clicks: [
                CursorClick(timestampSeconds: 0.2, position: NormalizedCapturePoint(x: 0.2, y: 0.2)),
                CursorClick(timestampSeconds: 18.8, position: NormalizedCapturePoint(x: 0.8, y: 0.8), button: .right)
            ],
            settings: EditorClickEffectSettings(soundEnabled: true, soundVolume: 0.7),
            durationSeconds: 20
        )
        defer { try? FileManager.default.removeItem(at: soundURL) }

        let asset = AVURLAsset(url: soundURL)
        let duration = try await asset.load(.duration)
        let attributes = try FileManager.default.attributesOfItem(atPath: soundURL.path)
        let byteCount = try #require(attributes[.size] as? Int64)

        #expect(abs(duration.seconds - 20) < 0.25)
        #expect(byteCount > 0)
        #expect(RenderAudioBounds.clickAudioChunkFrames < AVAudioFrameCount(20 * RenderAudioBounds.clickSampleRate))
    }

    @Test("Background music loop policy caps tiny or excessive loops")
    func backgroundMusicLoopPolicyCapsTinyOrExcessiveLoops() {
        #expect(!RenderAudioBounds.shouldLoopBackgroundMusic(
            sourceAvailableSeconds: RenderAudioBounds.minimumLoopableSourceDurationSeconds / 2,
            desiredDurationSeconds: 60,
            loopEnabled: true
        ))
        #expect(!RenderAudioBounds.shouldLoopBackgroundMusic(
            sourceAvailableSeconds: 1,
            desiredDurationSeconds: Double(RenderAudioBounds.maxBackgroundMusicLoopInsertions + 1),
            loopEnabled: true
        ))
        #expect(RenderAudioBounds.shouldLoopBackgroundMusic(
            sourceAvailableSeconds: 2,
            desiredDurationSeconds: 6,
            loopEnabled: true
        ))
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
            destinationURL: URL(fileURLWithPath: "/tmp/lesson.mp4"),
            editDecisionList: EditDecisionList(
                id: "codable-edit",
                sourceDurationSeconds: 10,
                trimRange: EditTimeRange(startSeconds: 1, endSeconds: 9)
            )
        )

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(RenderPlan.self, from: data)
        var legacyObject = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyObject.removeValue(forKey: "retainedSourceRanges")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacyDecoded = try JSONDecoder().decode(RenderPlan.self, from: legacyData)

        #expect(decoded == plan)
        #expect(legacyDecoded.retainedSourceRanges == nil)
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

    @Test("PiP style timeline follows camera layout and hidden regions")
    func pipStyleTimelineFollowsCameraLayoutAndHiddenRegions() {
        let defaultPlacement = PictureInPicturePlacement(
            corner: .bottomTrailing,
            widthRatio: 0.2,
            marginRatio: 0.05,
            aspectRatio: .widescreen16x9,
            frameShape: .roundedRectangle,
            borderEnabled: true,
            shadowEnabled: true
        )
        let overlay = PictureInPictureOverlay(
            source: RenderMediaSource(
                role: .webcamVideo,
                relativePath: "media/webcam.mp4",
                url: URL(fileURLWithPath: "/tmp/webcam.mp4")
            ),
            placement: defaultPlacement
        )
        let camera = EditorCameraSettings(
            defaultPlacement: defaultPlacement,
            layoutRegions: [
                CameraLayoutRegion(
                    id: "side-by-side",
                    range: EditTimeRange(startSeconds: 2, endSeconds: 4),
                    preset: .sideBySide,
                    animation: .fade,
                    transitionSeconds: 0.4
                ),
                CameraLayoutRegion(
                    id: "hidden",
                    range: EditTimeRange(startSeconds: 6, endSeconds: 8),
                    preset: .hidden,
                    animation: .fade,
                    transitionSeconds: 0.4
                )
            ]
        )

        let segments = PictureInPictureStyleTimeline.segments(
            overlay: overlay,
            camera: camera,
            sourceDisplaySize: CGSize(width: 640, height: 360),
            renderSize: CGSize(width: 1280, height: 720),
            durationSeconds: 10
        )

        #expect(segments.map(\.range) == [
            EditTimeRange(startSeconds: 0, endSeconds: 2),
            EditTimeRange(startSeconds: 2, endSeconds: 4),
            EditTimeRange(startSeconds: 4, endSeconds: 6),
            EditTimeRange(startSeconds: 8, endSeconds: 10)
        ])
        #expect(segments[1].id == "side-by-side")
        #expect(segments[1].geometry.frame.width > segments[0].geometry.frame.width)
        #expect(!segments.contains { $0.range.overlaps(EditTimeRange(startSeconds: 6, endSeconds: 8)) })
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
            ),
            captions: EditorCaptionSettings(
                placement: .top,
                fontSize: 28,
                textColor: .yellow,
                maxLineCount: 2,
                safeMarginRatio: 0.08
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
        #expect(inspection.plan?.captions == canvasSettings.captions)
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

    @Test("Exports synthetic media with click sounds and tiny looped music")
    func exportsSyntheticMediaWithClickSoundsAndTinyLoopedMusic() async throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let mediaURL = projectURL.appendingPathComponent("media", isDirectory: true)
        let audioURL = projectURL.appendingPathComponent("audio/tiny.caf")
        let cursorURL = projectURL.appendingPathComponent("cursor-metadata.json")
        let outputURL = temp.url.appendingPathComponent("exports/lesson.mp4")
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)

        try await SyntheticVideoWriter.write(
            outputURL: mediaURL.appendingPathComponent("screen.mp4"),
            size: CGSize(width: 160, height: 90),
            color: (red: 28, green: 38, blue: 58)
        )
        try SyntheticAudioWriter.write(outputURL: audioURL, frameCount: 1)
        try DMLessonJSON.encoder().encode(InteractionMetadataDocument(
            captureSize: CGSize(width: 160, height: 90),
            clicks: [
                CursorClick(timestampSeconds: 0.15, position: NormalizedCapturePoint(x: 0.25, y: 0.25), button: .left, phase: .down),
                CursorClick(timestampSeconds: 0.65, position: NormalizedCapturePoint(x: 0.7, y: 0.5), button: .right, phase: .down)
            ]
        )).write(to: cursorURL, options: [.atomic])
        try EditorSettingsFile.save(
            EditorSettings(
                cursor: EditorCursorSettings(clickEffects: EditorClickEffectSettings(soundEnabled: true, soundVolume: 0.6)),
                audio: EditorAudioSettings(
                    backgroundMusic: EditorBackgroundMusicSettings(
                        relativePath: "audio/tiny.caf",
                        durationSeconds: 1,
                        loop: true
                    )
                )
            ),
            toProject: projectURL
        )
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Audio Bounds"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                    cursorMetadata: ProjectFile(relativePath: "cursor-metadata.json", role: .cursorMetadata, mimeType: "application/json")
                )
            ),
            to: projectURL
        )

        let renderedURL = try await AVFoundationRenderService().export(
            projectURL: projectURL,
            destinationURL: outputURL,
            preset: RenderPreset(fileType: .mp4)
        )

        let asset = AVURLAsset(url: renderedURL)
        let duration = try await asset.load(.duration)

        #expect(renderedURL.pathExtension == "mp4")
        #expect(duration.seconds > 0.5)
    }

    @Test("Exports synthetic media with speed-region retiming")
    func exportsSyntheticMediaWithSpeedRegionRetiming() async throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let mediaURL = projectURL.appendingPathComponent("media/screen.mp4")
        let outputURL = temp.url.appendingPathComponent("exports/lesson.mp4")

        try await SyntheticVideoWriter.write(
            outputURL: mediaURL,
            size: CGSize(width: 320, height: 180),
            color: (red: 40, green: 80, blue: 180)
        )
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Speed Export"),
                media: ProjectMedia(screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo))
            ),
            to: projectURL
        )
        try EditDecisionListFile.save(
            EditDecisionList(
                id: "lesson-edit",
                sourceDurationSeconds: 1,
                speedRegions: [
                    SpeedRegion(
                        id: "speed-fast",
                        range: EditTimeRange(startSeconds: 0, endSeconds: 1),
                        playbackRate: 2
                    )
                ]
            ),
            toProject: projectURL
        )

        let renderedURL = try await AVFoundationRenderService().export(
            projectURL: projectURL,
            destinationURL: outputURL,
            preset: RenderPreset(fileType: .mp4)
        )

        let asset = AVURLAsset(url: renderedURL)
        let duration = try await asset.load(.duration)

        #expect(renderedURL.pathExtension == "mp4")
        #expect(abs(duration.seconds - 0.5) < 0.25)
    }

    @Test("Exports only retained source ranges from the full render path")
    func exportsOnlyRetainedSourceRanges() async throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let mediaURL = projectURL.appendingPathComponent("media/screen.mp4")
        let outputURL = temp.url.appendingPathComponent("exports/lesson.mp4")

        try await SyntheticVideoWriter.write(
            outputURL: mediaURL,
            size: CGSize(width: 320, height: 180),
            color: (red: 50, green: 100, blue: 180),
            frameCount: 30,
            fps: 15
        )
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Cut Export"),
                media: ProjectMedia(screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo))
            ),
            to: projectURL
        )
        try EditDecisionListFile.save(
            EditDecisionList(
                id: "lesson-edit",
                sourceDurationSeconds: 2,
                cuts: [
                    TimelineCut(id: "remove-middle", range: EditTimeRange(startSeconds: 0.5, endSeconds: 1.5))
                ]
            ),
            toProject: projectURL
        )

        let renderedURL = try await AVFoundationRenderService().export(
            projectURL: projectURL,
            destinationURL: outputURL,
            preset: RenderPreset(fileType: .mp4)
        )

        let duration = try await AVURLAsset(url: renderedURL).load(.duration).seconds
        #expect(abs(duration - 1) < 0.25)
    }

    @Test("Keeps mixed media tracks aligned across cuts and speed regions")
    func keepsMixedMediaAlignedAcrossCutsAndSpeedRegions() async throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let screenURL = projectURL.appendingPathComponent("media/screen.mp4")
        let webcamURL = projectURL.appendingPathComponent("media/webcam.mp4")
        let microphoneURL = projectURL.appendingPathComponent("media/microphone.caf")
        let outputURL = temp.url.appendingPathComponent("exports/lesson.mp4")

        try await SyntheticVideoWriter.write(
            outputURL: screenURL,
            size: CGSize(width: 320, height: 180),
            color: (red: 40, green: 90, blue: 170),
            frameCount: 30,
            fps: 15
        )
        try await SyntheticVideoWriter.write(
            outputURL: webcamURL,
            size: CGSize(width: 160, height: 90),
            color: (red: 170, green: 80, blue: 50),
            frameCount: 30,
            fps: 15
        )
        try SyntheticAudioWriter.write(outputURL: microphoneURL, frameCount: 88_200)
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "Mixed Edit"),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo),
                    webcam: ProjectFile(relativePath: "media/webcam.mp4", role: .webcamVideo),
                    microphoneAudio: ProjectFile(relativePath: "media/microphone.caf", role: .microphoneAudio)
                )
            ),
            to: projectURL
        )
        try EditDecisionListFile.save(
            EditDecisionList(
                id: "mixed-edit",
                sourceDurationSeconds: 2,
                cuts: [
                    TimelineCut(id: "remove-middle", range: EditTimeRange(startSeconds: 0.5, endSeconds: 1))
                ],
                speedRegions: [
                    SpeedRegion(
                        id: "speed-tail",
                        range: EditTimeRange(startSeconds: 1, endSeconds: 2),
                        playbackRate: 2
                    )
                ]
            ),
            toProject: projectURL
        )

        let renderedURL = try await AVFoundationRenderService().export(
            projectURL: projectURL,
            destinationURL: outputURL,
            preset: RenderPreset(fileType: .mp4)
        )
        let asset = AVURLAsset(url: renderedURL)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        #expect(abs(duration - 1) < 0.25)
        #expect(videoTracks.count == 1)
        #expect(!audioTracks.isEmpty)
        for track in videoTracks + audioTracks {
            let trackDuration = try await track.load(.timeRange).duration.seconds
            #expect(abs(trackDuration - duration) < 0.25)
        }
    }

    @Test("Exports synthetic media as ProRes MOV")
    func exportsSyntheticMediaAsProResMOV() async throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let mediaURL = projectURL.appendingPathComponent("media/screen.mp4")
        let outputURL = temp.url.appendingPathComponent("exports/lesson.mov")

        try await SyntheticVideoWriter.write(
            outputURL: mediaURL,
            size: CGSize(width: 320, height: 180),
            color: (red: 20, green: 120, blue: 220)
        )
        try ProjectBundle.writeManifest(
            ProjectManifest(
                metadata: LessonMetadata(lessonTitle: "ProRes Export"),
                media: ProjectMedia(screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo))
            ),
            to: projectURL
        )

        let renderedURL = try await AVFoundationRenderService().export(
            projectURL: projectURL,
            destinationURL: outputURL,
            preset: RenderPreset(fileType: .mov, codec: .proRes)
        )

        let asset = AVURLAsset(url: renderedURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let formatDescriptions = try await tracks.first?.load(.formatDescriptions) ?? []
        let codecNames = formatDescriptions.map { CMFormatDescriptionGetMediaSubType($0).fourCCString }

        #expect(renderedURL.pathExtension == "mov")
        #expect(codecNames.contains("apcn"))
    }
}

private extension FourCharCode {
    var fourCCString: String {
        let bytes = [
            UInt8((self >> 24) & 0xff),
            UInt8((self >> 16) & 0xff),
            UInt8((self >> 8) & 0xff),
            UInt8(self & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(self)"
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

private func firstVideoTrack(_ url: URL) async throws -> AVAssetTrack {
    let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
    return try #require(tracks.first)
}

private enum SyntheticVideoWriter {
    static func write(
        outputURL: URL,
        size: CGSize,
        color: (red: UInt8, green: UInt8, blue: UInt8),
        frameCount: Int = 15,
        fps: Int32 = 15
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

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let pixelBuffer = try makePixelBuffer(size: size, color: color)
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
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

private enum SyntheticAudioWriter {
    static func write(
        outputURL: URL,
        frameCount: AVAudioFrameCount,
        sampleRate: Double = 44_100,
        channelCount: AVAudioChannelCount = 1
    ) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            throw RenderExportError.unableToCreateCompositionTrack
        }

        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(2 * Double.pi * 220 * Double(frame) / sampleRate) * 0.12)
            for channel in 0..<Int(channelCount) {
                channels[channel][frame] = sample
            }
        }

        let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        try file.write(from: buffer)
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
