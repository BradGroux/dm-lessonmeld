import AppKit
import DMLessonMeldCore
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

    private var preflight: PermissionPreflightSnapshot {
        PermissionPreflight.snapshot(
            screenGranted: screenGranted,
            microphoneGranted: microphoneGranted,
            cameraGranted: cameraGranted,
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted,
            captureMicrophone: preferences.snapshot.capture.captureMicrophone,
            captureWebcam: preferences.snapshot.capture.captureWebcam,
            captureInteractionMetadata: preferences.snapshot.capture.captureInteractionMetadata,
            includeAutomationPermissions: true
        )
    }

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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
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

            ForEach(preflight.items) { item in
                PermissionSetupRow(item: item, actionTitle: item.isGranted ? "Open Settings" : "Grant Access") {
                    request(item.id)
                }
            }

            Text(preflight.summary)
                .font(.caption)
                .foregroundStyle(preflight.canContinue ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
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

    private func request(_ permission: AppPermissionID) {
        switch permission {
        case .screen:
            _ = ScreenCapturePermission.requestAccess()
            open(permission.settingsURL)
            refresh()
        case .microphone:
            Task {
                _ = await MicrophonePermission.requestAccess()
                await MainActor.run {
                    open(permission.settingsURL)
                    refresh()
                }
            }
        case .camera:
            Task {
                _ = await CameraPermission.requestAccess()
                await MainActor.run {
                    open(permission.settingsURL)
                    refresh()
                }
            }
        case .accessibility:
            AccessibilityPermission.requestAccess()
            open(permission.settingsURL)
            refresh()
        case .inputMonitoring:
            _ = InputMonitoringPermission.requestAccess()
            open(permission.settingsURL)
            refresh()
        }
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

private struct PermissionSetupRow: View {
    var item: PermissionPreflightItem
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
        Image(systemName: item.isGranted ? "checkmark.circle.fill" : item.id.systemImage)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(item.isGranted ? Color.green : (item.isBlocking ? Color.orange : Color.secondary))
            .frame(width: 30)
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(item.id.title)
                    .font(.headline)
                Text(item.need.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.need == .required ? Color.orange : Color.secondary)
            }
            Text(item.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusBadge: some View {
        Text(item.statusTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(item.isGranted ? Color.green : (item.isBlocking ? Color.orange : Color.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((item.isGranted ? Color.green : (item.isBlocking ? Color.orange : Color.secondary)).opacity(0.12), in: Capsule())
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
