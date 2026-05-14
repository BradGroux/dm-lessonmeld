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
            )
        ])

        try OverlayStoreFile.save(store, toProject: projectURL)

        let loaded = try OverlayStoreFile.load(fromProject: projectURL)
        #expect(loaded == store)
        #expect(OverlayStoreFile.url(inProject: projectURL).lastPathComponent == "overlays.json")
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
