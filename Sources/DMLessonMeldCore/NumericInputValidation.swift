import CoreGraphics
import Foundation

public enum NumericInputValidation {
    public static let maxRecordingDurationSeconds: TimeInterval = 6 * 60 * 60
    public static let maxTimelineSeconds: TimeInterval = 24 * 60 * 60
    public static let captureFPSRange = 1...240
    public static let maxCaptureCoordinate: CGFloat = 100_000
    public static let maxCaptureDimension: CGFloat = 16_384
    public static let maxDisplayScale: CGFloat = 8
    public static let minCanvasDimension = 16
    public static let maxCanvasDimension = 7_680
    public static let maxGenericPositiveNumber = 100_000

    public static func recordingDuration(_ value: TimeInterval, label: String = "Duration") throws -> TimeInterval {
        try finite(value, label: label)
        guard value > 0 else {
            throw NumericInputValidationError("\(label) must be greater than zero.")
        }
        guard value <= maxRecordingDurationSeconds else {
            throw NumericInputValidationError("\(label) must be \(format(maxRecordingDurationSeconds)) seconds or less.")
        }
        return value
    }

    public static func sleepNanoseconds(forRecordingDuration value: TimeInterval, label: String = "Duration") throws -> UInt64 {
        let duration = try recordingDuration(value, label: label)
        let nanoseconds = duration * 1_000_000_000
        guard nanoseconds.isFinite, nanoseconds <= Double(UInt64.max) else {
            throw NumericInputValidationError("\(label) is too large to schedule safely.")
        }
        return UInt64(nanoseconds.rounded(.up))
    }

    public static func nonNegativeSeconds(
        _ value: TimeInterval,
        label: String,
        max maxSeconds: TimeInterval = maxTimelineSeconds
    ) throws -> TimeInterval {
        try finite(value, label: label)
        guard value >= 0 else {
            throw NumericInputValidationError("\(label) must be non-negative.")
        }
        guard value <= maxSeconds else {
            throw NumericInputValidationError("\(label) must be \(format(maxSeconds)) seconds or less.")
        }
        return value
    }

    public static func positiveNumber(
        _ value: Double,
        label: String,
        max maxValue: Double = Double(maxGenericPositiveNumber)
    ) throws -> Double {
        try finite(value, label: label)
        guard value > 0 else {
            throw NumericInputValidationError("\(label) must be greater than zero.")
        }
        guard value <= maxValue else {
            throw NumericInputValidationError("\(label) must be \(format(maxValue)) or less.")
        }
        return value
    }

    public static func nonNegativeNumber(
        _ value: Double,
        label: String,
        max maxValue: Double = Double(maxGenericPositiveNumber)
    ) throws -> Double {
        try finite(value, label: label)
        guard value >= 0 else {
            throw NumericInputValidationError("\(label) must be non-negative.")
        }
        guard value <= maxValue else {
            throw NumericInputValidationError("\(label) must be \(format(maxValue)) or less.")
        }
        return value
    }

    public static func unitInterval(_ value: Double, label: String) throws -> Double {
        try finite(value, label: label)
        guard value >= 0, value <= 1 else {
            throw NumericInputValidationError("\(label) must be between 0 and 1.")
        }
        return value
    }

    public static func canvasDimension(_ value: Int, label: String) throws -> Int {
        guard value >= minCanvasDimension, value <= maxCanvasDimension else {
            throw NumericInputValidationError("\(label) must be from \(minCanvasDimension) through \(maxCanvasDimension) pixels.")
        }
        return value
    }

    public static func captureFPS(_ value: Int, label: String = "FPS") throws -> Int {
        guard captureFPSRange.contains(value) else {
            throw NumericInputValidationError("\(label) must be from \(captureFPSRange.lowerBound) through \(captureFPSRange.upperBound).")
        }
        return value
    }

    public static func optionalCaptureFPS(_ value: Int?, label: String = "FPS") throws -> Int? {
        guard let value else { return nil }
        return try captureFPS(value, label: label)
    }

    public static func captureRect(_ rect: CGRect, label: String = "Capture region") throws -> CGRect {
        try finite(Double(rect.origin.x), label: "\(label) x")
        try finite(Double(rect.origin.y), label: "\(label) y")
        try finite(Double(rect.size.width), label: "\(label) width")
        try finite(Double(rect.size.height), label: "\(label) height")
        guard rect.origin.x >= 0, rect.origin.y >= 0 else {
            throw NumericInputValidationError("\(label) origin must be non-negative.")
        }
        guard rect.origin.x <= maxCaptureCoordinate, rect.origin.y <= maxCaptureCoordinate else {
            throw NumericInputValidationError("\(label) origin is too large.")
        }
        guard rect.size.width > 0, rect.size.height > 0 else {
            throw NumericInputValidationError("\(label) width and height must be greater than zero.")
        }
        guard rect.size.width <= maxCaptureDimension, rect.size.height <= maxCaptureDimension else {
            throw NumericInputValidationError("\(label) width and height must be \(Int(maxCaptureDimension)) points or less.")
        }
        return rect
    }

    public static func displayScale(_ value: CGFloat, label: String = "Display scale") throws -> CGFloat {
        try finite(Double(value), label: label)
        guard value > 0, value <= maxDisplayScale else {
            throw NumericInputValidationError("\(label) must be greater than zero and no more than \(format(Double(maxDisplayScale))).")
        }
        return value
    }

    public static func capturePixelSize(
        sourceSize: CGSize,
        displayScale: CGFloat,
        retinaCapture: Bool
    ) throws -> (width: Int, height: Int) {
        _ = try captureRect(CGRect(origin: .zero, size: sourceSize), label: "Capture size")
        let scale = try Self.displayScale(displayScale)
        let multiplier = scale * (retinaCapture ? 2 : 1)
        let width = sourceSize.width * multiplier
        let height = sourceSize.height * multiplier
        try finite(Double(width), label: "Capture pixel width")
        try finite(Double(height), label: "Capture pixel height")
        guard width <= maxCaptureDimension, height <= maxCaptureDimension else {
            throw NumericInputValidationError("Capture pixel size must be \(Int(maxCaptureDimension)) pixels or less per side.")
        }
        return (evenPositiveInt(width), evenPositiveInt(height))
    }

    public static func finite(_ value: Double, label: String) throws {
        guard value.isFinite else {
            throw NumericInputValidationError("\(label) must be finite.")
        }
    }

    public static func safeEvenRounded(_ value: CGFloat, maximum: CGFloat = maxCaptureDimension) -> CGFloat {
        guard value.isFinite else { return 0 }
        let clamped = min(max(0, value), maximum)
        return CGFloat(max(0, Int(clamped.rounded()) & ~1))
    }

    public static func safeSizeLabel(width: Double, height: Double) -> String? {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let safeWidth = min(width, Double(maxCaptureDimension))
        let safeHeight = min(height, Double(maxCaptureDimension))
        return "\(Int(safeWidth.rounded()))x\(Int(safeHeight.rounded()))"
    }

    private static func evenPositiveInt(_ value: CGFloat) -> Int {
        max(2, Int(value.rounded()) & ~1)
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

public struct NumericInputValidationError: Error, Equatable, LocalizedError, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
