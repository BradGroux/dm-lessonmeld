import ApplicationServices
import AppKit
import DMLessonMeldCore
import IOKit.hid

enum AppPermissionID: String, CaseIterable, Identifiable {
    case screen
    case microphone
    case camera
    case accessibility
    case inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screen:
            "Screen Recording"
        case .microphone:
            "Microphone"
        case .camera:
            "Camera"
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
        }
    }

    var shortTitle: String {
        switch self {
        case .screen:
            "Screen"
        case .microphone:
            "Mic"
        case .camera:
            "Camera"
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input"
        }
    }

    var systemImage: String {
        switch self {
        case .screen:
            "display"
        case .microphone:
            "mic"
        case .camera:
            "web.camera"
        case .accessibility:
            "accessibility"
        case .inputMonitoring:
            "keyboard"
        }
    }

    var settingsURL: URL {
        switch self {
        case .screen:
            ScreenCapturePermission.privacySettingsURL
        case .microphone:
            MicrophonePermission.privacySettingsURL
        case .camera:
            CameraPermission.privacySettingsURL
        case .accessibility:
            AccessibilityPermission.privacySettingsURL
        case .inputMonitoring:
            InputMonitoringPermission.privacySettingsURL
        }
    }
}

enum PermissionPreflightNeed: Equatable {
    case required
    case optional
    case unused

    var isBlocking: Bool {
        self == .required
    }

    var title: String {
        switch self {
        case .required:
            "Required"
        case .optional:
            "Optional"
        case .unused:
            "Off"
        }
    }
}

struct PermissionPreflightItem: Identifiable, Equatable {
    var id: AppPermissionID
    var detail: String
    var isGranted: Bool
    var need: PermissionPreflightNeed

    var isMissing: Bool {
        !isGranted && need != .unused
    }

    var isBlocking: Bool {
        !isGranted && need.isBlocking
    }

    var statusTitle: String {
        if isGranted {
            return "Ready"
        }
        switch need {
        case .required:
            return "Needs Access"
        case .optional:
            return "Optional"
        case .unused:
            return "Off"
        }
    }
}

struct PermissionPreflightSnapshot: Equatable {
    var items: [PermissionPreflightItem]

    var blockingItems: [PermissionPreflightItem] {
        items.filter(\.isBlocking)
    }

    var optionalMissingItems: [PermissionPreflightItem] {
        items.filter { $0.isMissing && !$0.isBlocking }
    }

    var canContinue: Bool {
        blockingItems.isEmpty
    }

    var summary: String {
        if let firstBlocker = blockingItems.first {
            let names = blockingItems.map(\.id.shortTitle).joined(separator: ", ")
            return "\(names) required for this recording. Grant \(firstBlocker.id.shortTitle) access or change the capture options."
        }
        if !optionalMissingItems.isEmpty {
            let names = optionalMissingItems.map(\.id.shortTitle).joined(separator: ", ")
            return "Ready to record. Optional permissions missing: \(names)."
        }
        return "Ready to record with the selected capture options."
    }

    func item(_ id: AppPermissionID) -> PermissionPreflightItem? {
        items.first { $0.id == id }
    }
}

enum PermissionPreflight {
    static func recorder(
        captureMicrophone: Bool,
        captureWebcam: Bool,
        captureInteractionMetadata: Bool,
        includeAutomationPermissions: Bool = false
    ) -> PermissionPreflightSnapshot {
        snapshot(
            screenGranted: ScreenCapturePermission.isGranted,
            microphoneGranted: MicrophonePermission.isGranted,
            cameraGranted: CameraPermission.isGranted,
            accessibilityGranted: AccessibilityPermission.isGranted,
            inputMonitoringGranted: InputMonitoringPermission.isGranted,
            captureMicrophone: captureMicrophone,
            captureWebcam: captureWebcam,
            captureInteractionMetadata: captureInteractionMetadata,
            includeAutomationPermissions: includeAutomationPermissions
        )
    }

    static func onboarding(preferences: LessonMeldPreferences) -> PermissionPreflightSnapshot {
        snapshot(
            screenGranted: ScreenCapturePermission.isGranted,
            microphoneGranted: MicrophonePermission.isGranted,
            cameraGranted: CameraPermission.isGranted,
            accessibilityGranted: AccessibilityPermission.isGranted,
            inputMonitoringGranted: InputMonitoringPermission.isGranted,
            captureMicrophone: preferences.capture.captureMicrophone,
            captureWebcam: preferences.capture.captureWebcam,
            captureInteractionMetadata: preferences.capture.captureInteractionMetadata,
            includeAutomationPermissions: true
        )
    }

    static func snapshot(
        screenGranted: Bool,
        microphoneGranted: Bool,
        cameraGranted: Bool,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        captureMicrophone: Bool,
        captureWebcam: Bool,
        captureInteractionMetadata: Bool,
        includeAutomationPermissions: Bool
    ) -> PermissionPreflightSnapshot {
        var items = [
            PermissionPreflightItem(
                id: .screen,
                detail: "Required for screen, window, and region recordings.",
                isGranted: screenGranted,
                need: .required
            ),
            PermissionPreflightItem(
                id: .microphone,
                detail: captureMicrophone
                    ? "Required because microphone capture is enabled."
                    : "Optional voice capture; off for the selected recording flow.",
                isGranted: microphoneGranted,
                need: captureMicrophone ? .required : .unused
            ),
            PermissionPreflightItem(
                id: .camera,
                detail: captureWebcam
                    ? "Required because webcam capture is enabled."
                    : "Optional picture-in-picture capture; off for the selected recording flow.",
                isGranted: cameraGranted,
                need: captureWebcam ? .required : .unused
            )
        ]

        if includeAutomationPermissions || captureInteractionMetadata {
            items.append(
                PermissionPreflightItem(
                    id: .inputMonitoring,
                    detail: captureInteractionMetadata
                        ? "Optional for click, shortcut, and teaching interaction metadata."
                        : "Optional local click, shortcut, and interaction metadata.",
                    isGranted: inputMonitoringGranted,
                    need: captureInteractionMetadata ? .optional : .unused
                )
            )
        }

        if includeAutomationPermissions {
            items.append(
                PermissionPreflightItem(
                    id: .accessibility,
                    detail: "Optional for reliable global shortcuts, overlay control, and future automation.",
                    isGranted: accessibilityGranted,
                    need: .optional
                )
            )
        }

        return PermissionPreflightSnapshot(items: items)
    }
}

enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

enum InputMonitoringPermission {
    static var isGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
