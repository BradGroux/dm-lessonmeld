import CoreGraphics
import Foundation

public struct SelectionRect: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var displayID: CGDirectDisplayID
    public var displayFrame: CGRect
    public var backingScaleFactor: CGFloat

    public init(
        rect: CGRect,
        displayID: CGDirectDisplayID,
        displayFrame: CGRect,
        backingScaleFactor: CGFloat = 1
    ) {
        self.rect = rect
        self.displayID = displayID
        self.displayFrame = displayFrame
        self.backingScaleFactor = backingScaleFactor
    }

    public init(
        screenCaptureKitRect: CGRect,
        displayID: CGDirectDisplayID,
        displayFrame: CGRect,
        backingScaleFactor: CGFloat = 1
    ) {
        self.init(
            rect: Self.appKitRect(fromScreenCaptureKitRect: screenCaptureKitRect, displayFrame: displayFrame),
            displayID: displayID,
            displayFrame: displayFrame,
            backingScaleFactor: backingScaleFactor
        )
    }

    public var appKitRect: CGRect {
        rect.standardized
    }

    // AppKit uses a bottom-left display origin, while ScreenCaptureKit expects a
    // top-left, display-local rect.
    public var screenCaptureKitRect: CGRect {
        Self.screenCaptureKitRect(fromAppKitRect: appKitRect, displayFrame: displayFrame)
    }

    public var pixelSize: CGSize {
        CGSize(
            width: screenCaptureKitRect.width * backingScaleFactor,
            height: screenCaptureKitRect.height * backingScaleFactor
        )
    }

    public static func screenCaptureKitRect(fromAppKitRect rect: CGRect, displayFrame: CGRect) -> CGRect {
        let normalized = rect.standardized
        let width = evenRounded(normalized.width)
        let height = evenRounded(normalized.height)
        let localX = (normalized.minX - displayFrame.minX).rounded()
        let localAppKitY = normalized.minY - displayFrame.minY
        let localScreenCaptureKitY = (displayFrame.height - localAppKitY - height).rounded()

        return CGRect(x: localX, y: localScreenCaptureKitY, width: width, height: height)
    }

    public static func appKitRect(fromScreenCaptureKitRect rect: CGRect, displayFrame: CGRect) -> CGRect {
        let normalized = rect.standardized
        let width = evenRounded(normalized.width)
        let height = evenRounded(normalized.height)
        let appKitX = displayFrame.minX + normalized.minX.rounded()
        let appKitY = displayFrame.minY + (displayFrame.height - normalized.minY.rounded() - height)

        return CGRect(x: appKitX, y: appKitY, width: width, height: height)
    }

    private static func evenRounded(_ value: CGFloat) -> CGFloat {
        NumericInputValidation.safeEvenRounded(value)
    }
}
