import CoreGraphics
import Foundation

public struct WindowCaptureSource: Codable, Equatable, Identifiable, Sendable {
    public static let redactedTitle = "Window title redacted"

    public var id: UInt32
    public var title: String
    public var ownerName: String
    public var bounds: WindowCaptureBounds?

    public init(id: UInt32, title: String, ownerName: String, bounds: WindowCaptureBounds? = nil) {
        self.id = id
        self.title = title
        self.ownerName = ownerName
        self.bounds = bounds
    }

    public var sizeLabel: String? {
        guard let bounds else { return nil }
        return NumericInputValidation.safeSizeLabel(width: bounds.width, height: bounds.height)
    }

    public func redactedForAutomation(includeTitle: Bool = false) -> WindowCaptureSource {
        guard !includeTitle else { return self }
        return WindowCaptureSource(
            id: id,
            title: Self.redactedTitle,
            ownerName: ownerName,
            bounds: bounds
        )
    }
}

public struct WindowCaptureBounds: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum WindowCaptureSourceProvider {
    public static func availableSources() -> [WindowCaptureSource] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windows.compactMap { info in
            guard let id = uint32Value(info[kCGWindowNumber as String]),
                  intValue(info[kCGWindowLayer as String]) == 0 else {
                return nil
            }

            let owner = stringValue(info[kCGWindowOwnerName as String]) ?? "Unknown App"
            let name = stringValue(info[kCGWindowName as String]) ?? ""
            guard !owner.isEmpty else { return nil }

            let bounds = windowBounds(from: info[kCGWindowBounds as String])
            guard bounds?.width ?? 1 > 0, bounds?.height ?? 1 > 0 else {
                return nil
            }

            return WindowCaptureSource(
                id: id,
                title: name.isEmpty ? owner : name,
                ownerName: owner,
                bounds: bounds
            )
        }
    }

    private static func windowBounds(from value: Any?) -> WindowCaptureBounds? {
        guard let bounds = value as? [String: Any],
              let x = doubleValue(bounds["X"]),
              let y = doubleValue(bounds["Y"]),
              let width = doubleValue(bounds["Width"]),
              let height = doubleValue(bounds["Height"]) else {
            return nil
        }
        return WindowCaptureBounds(x: x, y: y, width: width, height: height)
    }

    private static func stringValue(_ value: Any?) -> String? {
        let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return string.isEmpty ? nil : string
    }

    private static func uint32Value(_ value: Any?) -> UInt32? {
        if let value = value as? UInt32 {
            return value
        }
        if let value = value as? NSNumber {
            return UInt32(truncating: value)
        }
        if let value = value as? Int, value >= 0 {
            return UInt32(value)
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? CGFloat {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }
}
