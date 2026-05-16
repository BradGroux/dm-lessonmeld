import DMLessonMeldCore
import Foundation
import Testing

@Suite("LessonMeld preferences")
struct LessonMeldPreferencesTests {
    @Test("Defaults are local-first and curriculum focused")
    func defaults() {
        let preferences = LessonMeldPreferences()

        #expect(preferences.privacy.localOnlyMode)
        #expect(preferences.privacy.includeMediaPathsInAgentManifests == false)
        #expect(preferences.privacy.includeTranscriptReferencesInAgentManifests == false)
        #expect(preferences.privacy.excludeMediaFromBackups)
        #expect(preferences.integrations.learnHouseEnabled)
        #expect(preferences.integrations.agentManifestsEnabled)
        #expect(preferences.general.defaultTemplateID == "workshop-lesson")
        #expect(preferences.capture.captureMicrophone)
        #expect(preferences.capture.microphoneDeviceID == nil)
        #expect(preferences.capture.captureWebcam)
        #expect(preferences.capture.captureInteractionMetadata == false)
        #expect(preferences.capture.quickRecordDurationSeconds == 300)
        #expect(preferences.capture.webcamFPS == 30)
        #expect(preferences.capture.webcamAspectRatio == .widescreen16x9)
        #expect(preferences.capture.webcamFrameShape == .roundedRectangle)
        #expect(preferences.capture.showFloatingWebcamPreview)
        #expect(preferences.capture.hideRecorderControlsFromCapture == false)
        #expect(preferences.capture.showRecorderControlTooltips)
        #expect(preferences.transcription.enabled == false)
        #expect(preferences.transcription.runtime == .whisperCPP)
        #expect(preferences.transcription.modelPath == TranscriptionPreferences.defaultModelFilePath)
        #expect(preferences.transcription.language == "en")
        #expect(preferences.annotation.paletteHexColors.count == 8)
        #expect(preferences.export.createArchiveByDefault)
        #expect(preferences.onboardingCompleted == false)
    }

    @Test("Normalization clamps risky values and keeps safe fallbacks")
    func normalization() {
        let preferences = LessonMeldPreferences(
            general: GeneralPreferences(defaultProjectDirectory: "", defaultTemplateID: ""),
            capture: CapturePreferences(
                quickRecordDurationSeconds: 0,
                fps: 144,
                microphoneDeviceID: "  built-in-mic  ",
                webcamFPS: 999,
                webcamCornerRadius: 999,
                webcamRelativeSize: 0.01,
                countdownSeconds: 99
            ),
            transcription: TranscriptionPreferences(
                enabled: false,
                modelPath: "   ",
                language: "  EN-US  ",
                autoTranscribeAfterRecording: true
            ),
            annotation: AnnotationPreferences(defaultColorHex: "nope", paletteHexColors: ["00ff00", "invalid"], lineWidth: 100),
            shortcuts: [.quickRecord: "  Option+Command+R  "]
        )

        #expect(preferences.general.defaultProjectDirectory == "~/Movies/DMLessonMeld")
        #expect(preferences.general.defaultTemplateID == "workshop-lesson")
        #expect(preferences.capture.quickRecordDurationSeconds == 1)
        #expect(preferences.capture.fps == 60)
        #expect(preferences.capture.microphoneDeviceID == "built-in-mic")
        #expect(preferences.capture.webcamFPS == 30)
        #expect(preferences.capture.webcamCornerRadius == 64)
        #expect(preferences.capture.webcamRelativeSize == 0.10)
        #expect(preferences.capture.countdownSeconds == 10)
        #expect(preferences.transcription.modelPath == TranscriptionPreferences.defaultModelFilePath)
        #expect(preferences.transcription.language == "en-us")
        #expect(preferences.transcription.autoTranscribeAfterRecording == false)
        #expect(preferences.annotation.defaultColorHex == "#FFD733")
        #expect(preferences.annotation.paletteHexColors == ["#00FF00"])
        #expect(preferences.annotation.lineWidth == 24)
        #expect(preferences.shortcuts[.quickRecord] == "option+command+r")
        #expect(preferences.shortcuts[.showSettings] == "command+,")
    }

    @Test("Preferences round trip through JSON")
    func codableRoundTrip() throws {
        let completedAt = Date(timeIntervalSince1970: 1_715_000_000)
        let preferences = LessonMeldPreferences(
            firstRunCompletedAt: completedAt,
            capture: CapturePreferences(
                quickRecordDurationSeconds: 600,
                captureSystemAudio: true,
                captureMicrophone: true,
                microphoneDeviceID: "external-mic",
                captureWebcam: true
            ),
            transcription: TranscriptionPreferences(
                enabled: true,
                modelPath: "/tmp/ggml-base.en.bin",
                language: "en",
                autoTranscribeAfterRecording: true
            ),
            privacy: PrivacyPreferences(includeMediaPathsInAgentManifests: true)
        )

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(LessonMeldPreferences.self, from: data)

        #expect(decoded == preferences)
        #expect(decoded.onboardingCompleted)
    }

    @Test("Legacy v1 preferences migrate webcam capture and quick record defaults")
    func legacyWebcamDefaultMigration() throws {
        let json = """
        {
          "schemaVersion": 1,
          "capture": {
            "quickRecordDurationSeconds": 5,
            "fps": 60,
            "includeCursor": true,
            "captureSystemAudio": false,
            "captureMicrophone": true,
            "captureWebcam": false,
            "cameraResolution": "1080p",
            "countdownSeconds": 3,
            "rememberLastRegion": true
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(LessonMeldPreferences.self, from: json)

        #expect(decoded.schemaVersion == LessonMeldPreferences.currentSchemaVersion)
        #expect(decoded.capture.captureWebcam)
        #expect(decoded.capture.quickRecordDurationSeconds == 300)
        #expect(decoded.capture.webcamFPS == 30)
        #expect(decoded.capture.showFloatingWebcamPreview)
    }

    @Test("Shortcuts encode as stable JSON object for Git backup")
    func shortcutsEncodeAsObject() throws {
        let data = try JSONEncoder().encode(LessonMeldPreferences())
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let shortcuts = try #require(json["shortcuts"] as? [String: String])

        #expect(shortcuts["showSettings"] == "command+,")
        #expect(shortcuts["quickRecord"] == "option+command+r")
    }

    @Test("Transcription model status reports disabled missing and ready states")
    func transcriptionModelStatus() throws {
        let disabled = TranscriptionModelInspector.status(
            for: TranscriptionPreferences(enabled: false)
        )
        #expect(disabled.state == TranscriptionModelState.disabled)
        #expect(disabled.isReady == false)

        let temp = try TranscriptionPreferenceTestDirectory()
        let modelURL = temp.url.appendingPathComponent("ggml-base.en.bin")
        try Data("model".utf8).write(to: modelURL)

        let ready = TranscriptionModelInspector.status(
            for: TranscriptionPreferences(enabled: true, modelPath: modelURL.path)
        )
        #expect(ready.state == TranscriptionModelState.ready)
        #expect(ready.isReady)
        #expect(ready.expandedModelPath == modelURL.path)

        let missing = TranscriptionModelInspector.status(
            for: TranscriptionPreferences(enabled: true, modelPath: temp.url.appendingPathComponent("missing.bin").path)
        )
        #expect(missing.state == TranscriptionModelState.modelNotFound)
        #expect(missing.isReady == false)
    }
}

private final class TranscriptionPreferenceTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-transcription-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
