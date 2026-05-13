import CoreGraphics
import DMLessonMeldCore
import Testing

@Suite("Selection rect conversion")
struct SelectionRectTests {
    @Test("Converts AppKit display coordinates to ScreenCaptureKit coordinates")
    func convertsAppKitToScreenCaptureKitCoordinates() {
        let displayFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let selection = SelectionRect(
            rect: CGRect(x: 100, y: 200, width: 641, height: 361),
            displayID: 1,
            displayFrame: displayFrame,
            backingScaleFactor: 2
        )

        #expect(selection.screenCaptureKitRect == CGRect(x: 100, y: 520, width: 640, height: 360))
        #expect(selection.pixelSize == CGSize(width: 1280, height: 720))
    }

    @Test("Converts ScreenCaptureKit coordinates back to AppKit coordinates")
    func convertsScreenCaptureKitToAppKitCoordinates() {
        let displayFrame = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
        let selection = SelectionRect(
            screenCaptureKitRect: CGRect(x: 40, y: 50, width: 800, height: 600),
            displayID: 2,
            displayFrame: displayFrame
        )

        #expect(selection.appKitRect == CGRect(x: -1880, y: 550, width: 800, height: 600))
        #expect(selection.screenCaptureKitRect == CGRect(x: 40, y: 50, width: 800, height: 600))
    }
}
