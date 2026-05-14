import CoreGraphics
import DMLessonMeldCore
import Testing

@Suite("Editor normalized geometry")
struct EditorNormalizedGeometryTests {
    @Test("Aspect-fit content frame respects preview padding")
    func contentFrameRespectsPadding() {
        let frame = EditorNormalizedGeometry.contentFrame(
            in: CGSize(width: 1200, height: 800),
            padding: 100,
            aspectRatio: 16.0 / 9.0
        )

        expectEqual(frame.origin.x, 100)
        expectEqual(frame.origin.y, 118.75)
        expectEqual(frame.width, 1000)
        expectEqual(frame.height, 562.5)
    }

    @Test("Top-down preview frames and flipped render frames share normalized dimensions")
    func mapsNormalizedRectsAcrossCoordinateSystems() {
        let contentFrame = CGRect(x: 100, y: 50, width: 800, height: 450)
        let normalizedFrame = NormalizedEditRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4)

        let previewFrame = EditorNormalizedGeometry.topDownFrame(for: normalizedFrame, in: contentFrame)
        let renderFrame = EditorNormalizedGeometry.flippedTopDownFrame(for: normalizedFrame, in: contentFrame)

        #expect(previewFrame.size == renderFrame.size)
        expectEqual(previewFrame.origin.x, 300)
        expectEqual(previewFrame.origin.y, 140)
        expectEqual(previewFrame.width, 400)
        expectEqual(previewFrame.height, 180)
        expectEqual(renderFrame.origin.x, 300)
        expectEqual(renderFrame.origin.y, 230)
    }

    @Test("Minimum overlay sizes do not change normalized origins")
    func minimumOverlaySizePreservesOrigin() {
        let contentFrame = CGRect(x: 10, y: 20, width: 80, height: 50)
        let normalizedFrame = NormalizedEditRect(x: 0.5, y: 0.4, width: 0.1, height: 0.1)

        let frame = EditorNormalizedGeometry.topDownFrame(
            for: normalizedFrame,
            in: contentFrame,
            minimumSize: CGSize(width: 20, height: 12)
        )

        expectEqual(frame.origin.x, 50)
        expectEqual(frame.origin.y, 40)
        expectEqual(frame.width, 20)
        expectEqual(frame.height, 12)
    }

    @Test("Flipped points match cursor and zoom render coordinates")
    func mapsFlippedPoints() {
        let contentFrame = CGRect(x: 100, y: 50, width: 800, height: 450)

        let point = EditorNormalizedGeometry.flippedTopDownPoint(
            for: NormalizedCapturePoint(x: 0.2, y: 0.25),
            in: contentFrame
        )

        expectEqual(point.x, 260)
        expectEqual(point.y, 387.5)
    }
}

private func expectEqual(_ actual: CGFloat, _ expected: CGFloat, precision: CGFloat = 0.0001) {
    #expect(abs(actual - expected) <= precision)
}
