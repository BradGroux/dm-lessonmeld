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
            )
        )

        try EditorSettingsFile.save(settings, toProject: temp.url)

        #expect(EditorSettingsFile.exists(in: temp.url))
        #expect(try EditorSettingsFile.load(fromProject: temp.url) == settings)
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
