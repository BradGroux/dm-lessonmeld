import ApplicationServices
import AppKit
import DMLessonMeldCore
import IOKit.hid
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var preferences: AppPreferencesController
    @Environment(\.dismiss) private var dismiss
    @State private var screenGranted = ScreenCapturePermission.isGranted
    @State private var microphoneGranted = MicrophonePermission.isGranted
    @State private var cameraGranted = CameraPermission.isGranted
    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var inputMonitoringGranted = InputMonitoringPermission.isGranted
    var onOpenSettings: () -> Void = {}

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        permissionSection
                        defaultsAndPrivacySection
                        footer
                    }
                    .id("onboarding-top")
                    .padding(.top, 64)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                    .frame(width: max(760, min(geometry.size.width, 1040)), alignment: .topLeading)
                }
                .onAppear {
                    refresh()
                    DispatchQueue.main.async {
                        proxy.scrollTo("onboarding-top", anchor: .top)
                    }
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 980, minHeight: 640, idealHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "record.circle")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Set Up \(AppBrand.displayName)")
                .font(.system(size: 30, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("A local-first recorder for curriculum builders. Pick the capture permissions and defaults once, then record workshops without chasing setup every time.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capture Permissions")
                .font(.headline)

            PermissionSetupRow(
                title: "Screen Recording",
                detail: "Required for screen, window, and region recordings.",
                granted: screenGranted,
                actionTitle: screenGranted ? "Open Settings" : "Grant Access"
            ) {
                _ = ScreenCapturePermission.requestAccess()
                open(ScreenCapturePermission.privacySettingsURL)
                refresh()
            }

            PermissionSetupRow(
                title: "Microphone",
                detail: "Used for instructor voice tracks and local captions/transcripts.",
                granted: microphoneGranted,
                actionTitle: microphoneGranted ? "Open Settings" : "Grant Access"
            ) {
                Task {
                    _ = await MicrophonePermission.requestAccess()
                    await MainActor.run {
                        open(MicrophonePermission.privacySettingsURL)
                        refresh()
                    }
                }
            }

            PermissionSetupRow(
                title: "Camera",
                detail: "Used for webcam picture-in-picture and talking-head segments.",
                granted: cameraGranted,
                actionTitle: cameraGranted ? "Open Settings" : "Grant Access"
            ) {
                Task {
                    _ = await CameraPermission.requestAccess()
                    await MainActor.run {
                        open(CameraPermission.privacySettingsURL)
                        refresh()
                    }
                }
            }

            PermissionSetupRow(
                title: "Accessibility",
                detail: "Used for reliable global shortcuts, overlay control, and future annotation automation.",
                granted: accessibilityGranted,
                actionTitle: accessibilityGranted ? "Open Settings" : "Grant Access"
            ) {
                AccessibilityPermission.requestAccess()
                open(AccessibilityPermission.privacySettingsURL)
                refresh()
            }

            PermissionSetupRow(
                title: "Input Monitoring",
                detail: "Used for local click, shortcut, and teaching interaction metadata.",
                granted: inputMonitoringGranted,
                actionTitle: inputMonitoringGranted ? "Open Settings" : "Grant Access"
            ) {
                _ = InputMonitoringPermission.requestAccess()
                open(InputMonitoringPermission.privacySettingsURL)
                refresh()
            }
        }
    }

    private var defaultsAndPrivacySection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                defaultsSection
                privacySection
            }

            VStack(alignment: .leading, spacing: 14) {
                defaultsSection
                privacySection
            }
        }
    }

    private var defaultsSection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Teaching Defaults", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Toggle("Record microphone by default", isOn: binding(\.capture.captureMicrophone))
                Toggle("Record webcam by default", isOn: binding(\.capture.captureWebcam))
                Toggle("Package LearnHouse exports by default", isOn: binding(\.export.defaultLearnHousePackage))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var privacySection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Local-Only Posture", systemImage: "lock.shield")
                    .font(.headline)
                Toggle("Keep media paths out of agent manifests", isOn: invertedBinding(\.privacy.includeMediaPathsInAgentManifests))
                Toggle("Keep transcripts out of agent manifests unless requested", isOn: invertedBinding(\.privacy.includeTranscriptReferencesInAgentManifests))
                Toggle("Allow Git backups for non-sensitive settings/templates", isOn: binding(\.privacy.allowGitBackupsForSettings))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                footerButtonsLeading

                Spacer()

                footerButtonsTrailing
            }

            VStack(alignment: .leading, spacing: 10) {
                footerButtonsLeading
                footerButtonsTrailing
            }
        }
    }

    private var footerButtonsLeading: some View {
        Button {
            refresh()
        } label: {
            Label("Check Again", systemImage: "arrow.clockwise")
        }
    }

    private var footerButtonsTrailing: some View {
        HStack {
            Button("Open Settings") {
                onOpenSettings()
            }

            Button("Use Screen Only") {
                preferences.update { snapshot in
                    snapshot.capture.captureMicrophone = false
                    snapshot.capture.captureWebcam = false
                }
                preferences.completeOnboarding()
                dismiss()
            }
            .disabled(!screenGranted)

            Button("Continue") {
                preferences.update { snapshot in
                    if !microphoneGranted {
                        snapshot.capture.captureMicrophone = false
                    }
                    if !cameraGranted {
                        snapshot.capture.captureWebcam = false
                    }
                }
                preferences.completeOnboarding()
                dismiss()
            }
            .disabled(!screenGranted)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func refresh() {
        screenGranted = ScreenCapturePermission.isGranted
        microphoneGranted = MicrophonePermission.isGranted
        cameraGranted = CameraPermission.isGranted
        accessibilityGranted = AccessibilityPermission.isGranted
        inputMonitoringGranted = InputMonitoringPermission.isGranted
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<LessonMeldPreferences, Value>) -> Binding<Value> {
        Binding {
            preferences.snapshot[keyPath: keyPath]
        } set: { value in
            preferences.update { $0[keyPath: keyPath] = value }
        }
    }

    private func invertedBinding(_ keyPath: WritableKeyPath<LessonMeldPreferences, Bool>) -> Binding<Bool> {
        Binding {
            !preferences.snapshot[keyPath: keyPath]
        } set: { value in
            preferences.update { $0[keyPath: keyPath] = !value }
        }
    }
}

private enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

private enum InputMonitoringPermission {
    static var isGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}

private struct PermissionSetupRow: View {
    var title: String
    var detail: String
    var granted: Bool
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        SettingsCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    statusIcon
                    rowText
                    Spacer(minLength: 12)
                    statusBadge
                    actionButton
                }

                HStack(alignment: .top, spacing: 14) {
                    statusIcon
                    VStack(alignment: .leading, spacing: 10) {
                        rowText
                        HStack {
                            statusBadge
                            actionButton
                        }
                    }
                }
            }
        }
    }

    private var statusIcon: some View {
        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(granted ? .green : .orange)
            .frame(width: 30)
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusBadge: some View {
        Text(granted ? "Granted" : "Needed")
            .font(.caption.weight(.semibold))
            .foregroundStyle(granted ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((granted ? Color.green : Color.orange).opacity(0.12), in: Capsule())
    }

    private var actionButton: some View {
        Button(actionTitle, action: action)
            .frame(width: 120)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LessonMeldCard {
            content
        }
    }
}
