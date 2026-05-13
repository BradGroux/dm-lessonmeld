import CoreGraphics
import DMLessonMeldCore
import Foundation
import Testing

@Suite("Cursor metadata sidecars")
struct CursorMetadataTests {
    @Test("Normalizes cursor samples and click coordinates into capture space")
    func normalizesCursorCoordinates() {
        var recorder = InteractionMetadataRecorder(
            startTimestamp: 10,
            captureRect: CGRect(x: 100, y: 200, width: 800, height: 600)
        )

        recorder.appendCursorSample(point: CGPoint(x: 500, y: 500), timestamp: 11.25)
        recorder.appendClick(point: CGPoint(x: 900, y: 800), timestamp: 12, button: .right, phase: .up, clickCount: 2)

        #expect(recorder.cursorSamples == [
            CursorSample(
                timestampSeconds: 1.25,
                position: NormalizedCapturePoint(x: 0.5, y: 0.5)
            )
        ])
        #expect(recorder.clicks == [
            CursorClick(
                timestampSeconds: 2,
                position: NormalizedCapturePoint(x: 1, y: 1),
                button: .right,
                phase: .up,
                clickCount: 2
            )
        ])
    }

    @Test("Applies pause offset when appending metadata events")
    func appliesPauseOffset() {
        var recorder = InteractionMetadataRecorder(
            startTimestamp: 100,
            captureRect: CGRect(x: 0, y: 0, width: 200, height: 100)
        )

        recorder.addPauseOffset(3.5)
        recorder.appendCursorSample(point: CGPoint(x: 50, y: 25), timestamp: 110)
        recorder.appendClick(point: CGPoint(x: 100, y: 75), timestamp: 111, phase: .down)
        recorder.appendKeystroke(
            timestamp: 112,
            keyCode: 36,
            characters: "\r",
            modifiers: [.command, .shift],
            isRepeat: true
        )

        let document = recorder.document()

        #expect(document.rendersCursorPointer)
        #expect(document.cursorSamples.first?.timestampSeconds == 6.5)
        #expect(document.cursorSamples.first?.position == NormalizedCapturePoint(x: 0.25, y: 0.25))
        #expect(document.clicks.first?.timestampSeconds == 7.5)
        #expect(document.clicks.first?.position == NormalizedCapturePoint(x: 0.5, y: 0.75))
        #expect(document.keystrokes.first == KeyboardMetadataEvent(
            timestampSeconds: 8.5,
            keyCode: 36,
            characters: "\r",
            modifiers: [.command, .shift],
            phase: .down,
            isRepeat: true
        ))
    }

    @Test("Can normalize raw metadata documents after collection")
    func normalizesRawDocumentTimestamps() {
        let document = InteractionMetadataDocument(
            captureSize: CGSize(width: 1920, height: 1080),
            rendersCursorPointer: false,
            cursorSamples: [
                CursorSample(timestampSeconds: 101, position: NormalizedCapturePoint(x: 0.1, y: 0.2))
            ],
            clicks: [
                CursorClick(timestampSeconds: 102, position: NormalizedCapturePoint(x: 0.3, y: 0.4))
            ],
            keystrokes: [
                KeyboardMetadataEvent(timestampSeconds: 103, keyCode: 0, characters: "a")
            ]
        )

        let normalized = document.normalizingTimestamps(relativeTo: 100, pauseOffset: 0.5)

        #expect(!normalized.rendersCursorPointer)
        #expect(normalized.cursorSamples.first?.timestampSeconds == 0.5)
        #expect(normalized.clicks.first?.timestampSeconds == 1.5)
        #expect(normalized.keystrokes.first?.timestampSeconds == 2.5)
    }

    @Test("Encodes and decodes interaction metadata sidecar")
    func codableRoundTrip() throws {
        let document = InteractionMetadataDocument(
            captureSize: CGSize(width: 1280, height: 720),
            cursorSamples: [
                CursorSample(timestampSeconds: 0.1, position: NormalizedCapturePoint(x: 0.2, y: 0.3))
            ],
            clicks: [
                CursorClick(timestampSeconds: 0.2, position: NormalizedCapturePoint(x: 0.4, y: 0.5), button: .left)
            ],
            keystrokes: [
                KeyboardMetadataEvent(
                    timestampSeconds: 0.3,
                    keyCode: 1,
                    characters: "s",
                    modifiers: [.command],
                    phase: .up
                )
            ]
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(InteractionMetadataDocument.self, from: encoded)

        #expect(decoded == document)
    }

    @Test("Decodes legacy interaction metadata without pointer render flag")
    func decodesLegacyMetadataWithoutPointerFlag() throws {
        let json = """
        {
          "schema": "io.digitalmeld.dm-lessonmeld.capture-metadata",
          "version": 1,
          "captureSize": [1280, 720],
          "cursorSamples": [],
          "clicks": [],
          "keystrokes": []
        }
        """
        let decoded = try JSONDecoder().decode(InteractionMetadataDocument.self, from: Data(json.utf8))

        #expect(decoded.rendersCursorPointer)
        #expect(decoded.captureSize == CGSize(width: 1280, height: 720))
    }

    @Test("Recorder can keep click metadata without rendering duplicate cursor")
    func recorderCanDisableSyntheticPointer() {
        var recorder = InteractionMetadataRecorder(
            startTimestamp: 0,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            rendersCursorPointer: false
        )

        recorder.appendCursorSample(point: CGPoint(x: 50, y: 50), timestamp: 1)
        recorder.appendClick(point: CGPoint(x: 50, y: 50), timestamp: 1.1)

        let document = recorder.document()

        #expect(!document.rendersCursorPointer)
        #expect(document.cursorSamples.count == 1)
        #expect(document.clicks.count == 1)
    }
}
