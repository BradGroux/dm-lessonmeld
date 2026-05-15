import CoreGraphics
import Foundation

public enum EditorNormalizedGeometry {
    public static func contentFrame(
        in containerSize: CGSize,
        padding: CGFloat = 0,
        aspectRatio: CGFloat? = nil
    ) -> CGRect {
        let safePadding = max(0, padding.isFinite ? padding : 0)
        let availableWidth = max(1, containerSize.width - safePadding * 2)
        let availableHeight = max(1, containerSize.height - safePadding * 2)
        let resolvedAspectRatio = max(0.01, aspectRatio ?? (availableWidth / max(availableHeight, 1)))
        let availableRatio = availableWidth / max(availableHeight, 1)

        let contentSize: CGSize
        if availableRatio > resolvedAspectRatio {
            let height = availableHeight
            contentSize = CGSize(width: height * resolvedAspectRatio, height: height)
        } else {
            let width = availableWidth
            contentSize = CGSize(width: width, height: width / resolvedAspectRatio)
        }

        return CGRect(
            x: safePadding + (availableWidth - contentSize.width) / 2,
            y: safePadding + (availableHeight - contentSize.height) / 2,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    public static func topDownFrame(
        for normalizedFrame: NormalizedEditRect,
        in contentFrame: CGRect,
        minimumSize: CGSize = .zero
    ) -> CGRect {
        frame(for: normalizedFrame, in: contentFrame, minimumSize: minimumSize, flipY: false)
    }

    public static func flippedTopDownFrame(
        for normalizedFrame: NormalizedEditRect,
        in contentFrame: CGRect,
        minimumSize: CGSize = .zero
    ) -> CGRect {
        frame(for: normalizedFrame, in: contentFrame, minimumSize: minimumSize, flipY: true)
    }

    public static func renderFrame(for normalizedFrame: NormalizedEditRect, renderSize: CGSize) -> CGRect {
        flippedTopDownFrame(for: normalizedFrame, in: CGRect(origin: .zero, size: renderSize))
    }

    public static func topDownPoint(x: Double, y: Double, in contentFrame: CGRect) -> CGPoint {
        point(x: x, y: y, in: contentFrame, flipY: false)
    }

    public static func flippedTopDownPoint(x: Double, y: Double, in contentFrame: CGRect) -> CGPoint {
        point(x: x, y: y, in: contentFrame, flipY: true)
    }

    public static func flippedTopDownPoint(for normalizedPoint: NormalizedCapturePoint, in contentFrame: CGRect) -> CGPoint {
        flippedTopDownPoint(x: normalizedPoint.x, y: normalizedPoint.y, in: contentFrame)
    }

    public static func renderPoint(for normalizedPoint: NormalizedCapturePoint, renderSize: CGSize) -> CGPoint {
        flippedTopDownPoint(for: normalizedPoint, in: CGRect(origin: .zero, size: renderSize))
    }

    private static func frame(
        for normalizedFrame: NormalizedEditRect,
        in contentFrame: CGRect,
        minimumSize: CGSize,
        flipY: Bool
    ) -> CGRect {
        let frame = contentFrame.standardized
        let width = max(max(0, minimumSize.width), CGFloat(normalizedFrame.width) * frame.width)
        let height = max(max(0, minimumSize.height), CGFloat(normalizedFrame.height) * frame.height)
        let x = frame.minX + CGFloat(normalizedFrame.x) * frame.width
        let normalizedY = flipY ? 1 - CGFloat(normalizedFrame.y + normalizedFrame.height) : CGFloat(normalizedFrame.y)
        let y = frame.minY + normalizedY * frame.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func point(x: Double, y: Double, in contentFrame: CGRect, flipY: Bool) -> CGPoint {
        let frame = contentFrame.standardized
        let resolvedX = CGFloat(x.isFinite ? x : 0)
        let resolvedY = CGFloat(y.isFinite ? y : 0)
        return CGPoint(
            x: frame.minX + resolvedX * frame.width,
            y: frame.minY + (flipY ? 1 - resolvedY : resolvedY) * frame.height
        )
    }
}
