import CoreGraphics
import DMLessonMeldCore
import Foundation
import Testing

@Suite("Editor settings")
struct EditorSettingsTests {
    @Test("Editor settings persist as project sidecars")
    func persistsProjectSidecar() throws {
        let temp = try TemporaryDirectory()
        let settings = EditorSettings(
            canvas: EditorCanvasSettings(
                aspectRatio: .portrait4x5,
                background: EditorCanvasBackground(
                    style: .gradient,
                    primaryColor: .purple,
                    secondaryColor: .blue
                ),
                paddingRatio: 0.12,
                insetRatio: 0.04,
                cornerRadiusRatio: 0.06,
                shadow: EditorCanvasShadow(isEnabled: true, opacity: 0.62),
                cropRect: NormalizedEditRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
                customSize: EditorCanvasCustomSize(width: 1200, height: 900)
            ),
            zoom: EditorZoomSettings(automaticClickZoomsEnabled: false),
            cursor: EditorCursorSettings(
                pointerStyle: .touchDot,
                pointerVisible: false,
                smoothMovement: false,
                pointerScale: 1.4,
                pointerFillColor: .cyan,
                hiddenRanges: [
                    EditTimeRange(startSeconds: 1, endSeconds: 3)
                ],
                clickEffects: EditorClickEffectSettings(
                    rippleVisible: true,
                    color: .pink,
                    scale: 1.5,
                    soundEnabled: true,
                    soundVolume: 0.6
                ),
                keyboardOverlay: EditorKeyboardOverlaySettings(isVisible: false)
            ),
            camera: EditorCameraSettings(
                defaultPlacement: PictureInPicturePlacement(
                    corner: .topLeading,
                    widthRatio: 0.32,
                    marginRatio: 0.03,
                    aspectRatio: .square1x1,
                    frameShape: .circle,
                    isMirrored: true,
                    borderEnabled: true
                ),
                layoutRegions: [
                    CameraLayoutRegion(
                        id: "camera-full",
                        range: EditTimeRange(startSeconds: 2, endSeconds: 5),
                        preset: .fullCamera,
                        animation: .fade
                    )
                ],
                reactions: [
                    CameraReaction(
                        id: "reaction-1",
                        range: EditTimeRange(startSeconds: 3, endSeconds: 4),
                        text: "👍"
                    )
                ]
            ),
            audio: EditorAudioSettings(
                screenAudio: EditorAudioTrackSettings(gain: 0.9),
                microphoneAudio: EditorAudioTrackSettings(gain: 1.2, isSoloed: true),
                systemAudio: EditorAudioTrackSettings(gain: 0.3, isMuted: true),
                backgroundMusic: EditorBackgroundMusicSettings(
                    relativePath: "audio/assets/intro.m4a",
                    startSeconds: 1,
                    durationSeconds: 8,
                    gain: 0.25,
                    duckUnderVoice: true,
                    duckedGain: 0.08
                ),
                volumeRegions: [
                    EditorAudioVolumeRegion(
                        id: "duck-1",
                        track: .backgroundMusic,
                        range: EditTimeRange(startSeconds: 2, endSeconds: 6),
                        gain: 0.1,
                        fadeInSeconds: 0.3,
                        fadeOutSeconds: 0.4
                    )
                ]
            ),
            captions: EditorCaptionSettings(
                burnInEnabled: true,
                placement: .top,
                fontName: "Helvetica",
                fontSize: 40,
                textColor: .yellow,
                backgroundColor: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.6),
                maxLineCount: 2,
                safeMarginRatio: 0.1
            )
        )

        try EditorSettingsFile.save(settings, toProject: temp.url)

        #expect(EditorSettingsFile.exists(in: temp.url))
        #expect(try EditorSettingsFile.load(fromProject: temp.url) == settings)
    }

    @Test("Editor settings load rejects oversized sidecars")
    func editorSettingsLoadRejectsOversizedSidecars() throws {
        let temp = try TemporaryDirectory()
        try Data(repeating: UInt8(ascii: "{"), count: RenderSidecarLimits.maxSidecarBytes + 1)
            .write(to: EditorSettingsFile.url(in: temp.url), options: [.atomic])

        #expect(throws: RenderSidecarLimitError.self) {
            try EditorSettingsFile.load(fromProject: temp.url)
        }
    }

    @Test("Decoded editor settings normalize hostile persisted values")
    func decodedSettingsNormalizeHostileValues() throws {
        let encoded = try DMLessonJSON.encoder().encode(EditorSettings(
            camera: EditorCameraSettings(layoutRegions: [
                CameraLayoutRegion(
                    id: "camera-layout",
                    range: EditTimeRange(startSeconds: 0, durationSeconds: 1),
                    preset: .cornerPip
                )
            ]),
            audio: EditorAudioSettings(
                backgroundMusic: EditorBackgroundMusicSettings(relativePath: "music.m4a"),
                volumeRegions: [
                    EditorAudioVolumeRegion(
                        id: "volume",
                        range: EditTimeRange(startSeconds: 0, durationSeconds: 1)
                    )
                ]
            )
        ))
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        var canvas = try #require(root["canvas"] as? [String: Any])
        canvas["aspectRatio"] = "custom"
        canvas["paddingRatio"] = 99
        canvas["insetRatio"] = -99
        canvas["cornerRadiusRatio"] = 99
        canvas["customSize"] = ["width": 999_999, "height": 17]
        var shadow = try #require(canvas["shadow"] as? [String: Any])
        shadow["opacity"] = 99
        shadow["radiusRatio"] = 99
        shadow["offsetYRatio"] = -99
        canvas["shadow"] = shadow
        root["canvas"] = canvas

        var audio = try #require(root["audio"] as? [String: Any])
        var screenAudio = try #require(audio["screenAudio"] as? [String: Any])
        screenAudio["gain"] = 99
        audio["screenAudio"] = screenAudio
        var backgroundMusic = try #require(audio["backgroundMusic"] as? [String: Any])
        backgroundMusic["startSeconds"] = -99
        backgroundMusic["durationSeconds"] = -99
        backgroundMusic["gain"] = 99
        audio["backgroundMusic"] = backgroundMusic
        var volumeRegions = try #require(audio["volumeRegions"] as? [[String: Any]])
        volumeRegions[0]["gain"] = 99
        volumeRegions[0]["fadeInSeconds"] = 99
        volumeRegions[0]["fadeOutSeconds"] = 99
        audio["volumeRegions"] = volumeRegions
        root["audio"] = audio

        var captions = try #require(root["captions"] as? [String: Any])
        captions["fontName"] = "   "
        captions["fontSize"] = 999
        captions["maxLineCount"] = 999
        captions["safeMarginRatio"] = 99
        root["captions"] = captions

        var cursor = try #require(root["cursor"] as? [String: Any])
        var keyboardOverlay = try #require(cursor["keyboardOverlay"] as? [String: Any])
        keyboardOverlay["opacity"] = 99
        cursor["keyboardOverlay"] = keyboardOverlay
        root["cursor"] = cursor

        var camera = try #require(root["camera"] as? [String: Any])
        var layoutRegions = try #require(camera["layoutRegions"] as? [[String: Any]])
        layoutRegions[0]["transitionSeconds"] = 99
        camera["layoutRegions"] = layoutRegions
        root["camera"] = camera

        let hostileData = try JSONSerialization.data(withJSONObject: root)
        let settings = try DMLessonJSON.decoder().decode(EditorSettings.self, from: hostileData)

        #expect(settings.canvas.paddingRatio == 0.45)
        #expect(settings.canvas.insetRatio == 0)
        #expect(settings.canvas.cornerRadiusRatio == 0.25)
        #expect(settings.canvas.customSize == EditorCanvasCustomSize(width: 7_680, height: 18))
        #expect(settings.canvas.shadow.opacity == 1)
        #expect(settings.canvas.shadow.radiusRatio == 0.12)
        #expect(settings.canvas.shadow.offsetYRatio == -0.12)
        #expect(settings.audio?.screenAudio.gain == 2)
        #expect(settings.audio?.backgroundMusic?.startSeconds == 0)
        #expect(settings.audio?.backgroundMusic?.durationSeconds == nil)
        #expect(settings.audio?.backgroundMusic?.gain == 2)
        #expect(settings.audio?.volumeRegions.first?.gain == 2)
        #expect(settings.audio?.volumeRegions.first?.fadeInSeconds == 10)
        #expect(settings.audio?.volumeRegions.first?.fadeOutSeconds == 10)
        #expect(settings.captions?.fontName == "Helvetica-Bold")
        #expect(settings.captions?.fontSize == 96)
        #expect(settings.captions?.maxLineCount == 5)
        #expect(settings.captions?.safeMarginRatio == 0.25)
        #expect(settings.cursor?.keyboardOverlay.opacity == 1)
        #expect(settings.camera?.layoutRegions.first?.transitionSeconds == 2)
    }

    @Test("Canvas geometry resolves aspect, padding, crop, and rounded corners")
    func resolvesCanvasGeometry() {
        let settings = EditorCanvasSettings(
            aspectRatio: .custom,
            background: EditorCanvasBackground(style: .solid, primaryColor: .black),
            paddingRatio: 0.1,
            insetRatio: 0.05,
            cornerRadiusRatio: 0.08,
            shadow: EditorCanvasShadow(isEnabled: true),
            cropRect: NormalizedEditRect(x: 0.25, y: 0, width: 0.5, height: 1),
            customSize: EditorCanvasCustomSize(width: 1080, height: 1080)
        )

        let geometry = settings.renderGeometry(sourceSize: CGSize(width: 1920, height: 1080))

        #expect(geometry.renderSize == CGSize(width: 1080, height: 1080))
        #expect(geometry.sourceCropRect == CGRect(x: 480, y: 0, width: 960, height: 1080))
        #expect(geometry.videoFrame.width < geometry.renderSize.width)
        #expect(geometry.videoFrame.height < geometry.renderSize.height)
        #expect(geometry.cornerRadius > 0)
        #expect(!settings.isDefault)
    }

    @Test("Legacy editor settings decode without camera settings")
    func legacySettingsDecodeWithoutCameraSettings() throws {
        let json = """
        {
          "schemaVersion": 1,
          "canvas": {
            "aspectRatio": "source",
            "background": {
              "style": "none",
              "primaryColor": {"red": 0, "green": 0, "blue": 0, "alpha": 1},
              "secondaryColor": {"red": 0.5, "green": 0.2, "blue": 0.9, "alpha": 1}
            },
            "paddingRatio": 0,
            "insetRatio": 0,
            "cornerRadiusRatio": 0,
            "shadow": {"isEnabled": false, "opacity": 0.34, "radiusRatio": 0.02, "offsetYRatio": -0.008}
          }
        }
        """

        let settings = try DMLessonJSON.decoder().decode(EditorSettings.self, from: Data(json.utf8))

        #expect(settings.camera == nil)
        #expect(settings.audio == nil)
        #expect(settings.captions == nil)
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-editor-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
