import DMLessonMeldCore
import Foundation
import Testing

@Suite("Overlay store")
struct OverlayStoreTests {
    @Test("Saves and loads timed video overlays")
    func savesAndLoadsTimedVideoOverlays() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let store = OverlayStore(overlays: [
            OverlayItem(
                id: "title",
                kind: .text,
                timeRange: EditTimeRange(startSeconds: 1, durationSeconds: 3),
                frame: NormalizedEditRect(x: 0.15, y: 0.2, width: 0.7, height: 0.16),
                opacity: 0.88,
                zIndex: 3,
                style: OverlayStyle(
                    text: "Important step",
                    fontSize: 42,
                    textColor: .white,
                    fillColor: RGBAColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 0.7),
                    strokeColor: .yellow
                ),
                animation: OverlayAnimation(fadeInSeconds: 0.25, fadeOutSeconds: 0.4, preset: .slideUp)
            ),
            OverlayItem(
                id: "badge",
                kind: .image,
                timeRange: EditTimeRange(startSeconds: 4, durationSeconds: 2),
                frame: NormalizedEditRect(x: 0.72, y: 0.08, width: 0.18, height: 0.18),
                style: OverlayStyle(imagePath: "overlays/assets/badge.png")
            ),
            OverlayItem(
                id: "focus",
                kind: .highlight,
                timeRange: EditTimeRange(startSeconds: 6, durationSeconds: 2),
                frame: NormalizedEditRect(x: 0.18, y: 0.22, width: 0.42, height: 0.28),
                opacity: 0.72,
                style: OverlayStyle(
                    fillColor: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.55),
                    strokeColor: .yellow,
                    cornerRadius: 20,
                    shadowEnabled: false,
                    highlightMode: .spotlight,
                    highlightShape: .roundedRectangle,
                    blurRadius: 16,
                    featherRadius: 24
                )
            )
        ])

        try OverlayStoreFile.save(store, toProject: projectURL)

        let loaded = try OverlayStoreFile.load(fromProject: projectURL)
        #expect(loaded == store)
        #expect(OverlayStoreFile.url(inProject: projectURL).lastPathComponent == "overlays.json")
    }

    @Test("Overlay load rejects sidecars above item limits")
    func overlayLoadRejectsSidecarsAboveItemLimits() throws {
        let temp = try TemporaryDirectory()
        let projectURL = temp.url.appendingPathComponent("Lesson.dmlm", isDirectory: true)
        let store = OverlayStore(overlays: (0...RenderSidecarLimits.maxOverlays).map { index in
            OverlayItem(
                id: "overlay-\(index)",
                kind: .text,
                timeRange: EditTimeRange(startSeconds: Double(index), durationSeconds: 1)
            )
        })

        try OverlayStoreFile.save(store, toProject: projectURL)

        #expect(throws: RenderSidecarLimitError.self) {
            try OverlayStoreFile.load(fromProject: projectURL)
        }
    }

    @Test("Overlay model clamps unsafe numeric values")
    func clampsUnsafeNumericValues() {
        let item = OverlayItem(
            id: "bad-numbers",
            kind: .callout,
            timeRange: EditTimeRange(startSeconds: 0, durationSeconds: 1),
            frame: NormalizedEditRect(x: -1, y: 2, width: 4, height: -2),
            rotationDegrees: .infinity,
            opacity: 4,
            style: OverlayStyle(fontSize: .infinity, lineWidth: -10, cornerRadius: .nan),
            animation: OverlayAnimation(fadeInSeconds: .infinity, fadeOutSeconds: -1)
        )

        #expect(item.frame.x == 0)
        #expect(item.frame.y == 1)
        #expect(item.frame.width == 1)
        #expect(item.frame.height == 0)
        #expect(item.rotationDegrees == 0)
        #expect(item.opacity == 1)
        #expect(item.style.fontSize == 34)
        #expect(item.style.lineWidth == 0)
        #expect(item.style.cornerRadius == 12)
        #expect(item.animation.fadeInSeconds == 0.18)
        #expect(item.animation.fadeOutSeconds == 0)
    }

    @Test("Legacy overlay styles decode without highlight fields")
    func legacyOverlayStylesDecode() throws {
        let json = """
        {
          "schemaVersion": 1,
          "isVisible": true,
          "overlays": [
            {
              "id": "legacy",
              "kind": "text",
              "timeRange": {"startSeconds": 0, "durationSeconds": 2},
              "frame": {"x": 0.2, "y": 0.2, "width": 0.4, "height": 0.2},
              "rotationDegrees": 0,
              "opacity": 1,
              "zIndex": 0,
              "style": {
                "text": "Legacy",
                "fontSize": 34,
                "textColor": {"red": 1, "green": 1, "blue": 1, "alpha": 1},
                "strokeColor": {"red": 1, "green": 0.86, "blue": 0.2, "alpha": 1},
                "lineWidth": 4,
                "cornerRadius": 12,
                "shadowEnabled": true
              },
              "animation": {"fadeInSeconds": 0.18, "fadeOutSeconds": 0.18, "preset": "none"},
              "isEnabled": true
            }
          ]
        }
        """

        let store = try DMLessonJSON.decoder().decode(OverlayStore.self, from: Data(json.utf8))

        #expect(store.overlays.first?.style.highlightMode == nil)
        #expect(store.overlays.first?.style.highlightShape == nil)
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-overlay-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
