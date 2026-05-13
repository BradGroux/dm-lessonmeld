import CoreGraphics
import Foundation

public enum ScreenCapturePermission {
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static var privacySettingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    }
}
