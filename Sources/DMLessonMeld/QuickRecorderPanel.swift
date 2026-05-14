@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import CoreMedia
import DMLessonMeldCore
import SwiftUI

struct QuickRecorderPanel: View {
    @ObservedObject var model: QuickRecorderModel
    @ObservedObject var preferences: AppPreferencesController

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Label("Quick Record", systemImage: "record.circle")
                        .font(.headline)

                    Spacer()

                    if model.isRecording || model.isStopping {
                        RecordingStatusPill(
                            isPaused: model.isPaused,
                            isStopping: model.isStopping,
                            elapsed: model.formattedElapsed
                        )
                    }
                }

                Text(model.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        quickRecorderActions
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        quickRecorderActions
                    }
                }

                if let projectPath = model.lastProjectPath {
                    Text(projectPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .onAppear {
            model.applyPreferences(preferences.snapshot)
            model.refreshPermissions(updateMessage: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions(updateMessage: true)
        }
    }

    private var quickRecorderActions: some View {
        Group {
            Button {
                model.presentControlBar(preferences: preferences)
            } label: {
                Label(model.isRecording ? "Show Recording Controls" : "Open Recording Controls", systemImage: "slider.horizontal.3")
            }

            if let lastProjectPath = model.lastProjectPath {
                Button {
                    model.openLastProjectInEditor()
                } label: {
                    Label("Review Last Lesson", systemImage: "film.stack")
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: lastProjectPath)])
                } label: {
                    Label("Reveal Bundle", systemImage: "arrow.up.forward.app")
                }
            }
        }
    }
}

private struct QuickRecordingControlBar: View {
    @ObservedObject var model: QuickRecorderModel
    @ObservedObject var preferences: AppPreferencesController
    @State private var showDisplayPopover = false
    @State private var showCameraPopover = false
    @State private var showMicrophonePopover = false
    @State private var showRegionPopover = false
    @State private var showWindowPopover = false
    @State private var showOptionsPopover = false

    var body: some View {
        HStack(spacing: ControlBarPalette.itemGap) {
            if model.isRecording || model.isStopping {
                recordingControls
            } else if let completion = model.completion {
                completionControls(completion)
            } else {
                setupControls
            }
        }
        .padding(ControlBarPalette.outerPadding)
        .background(ControlBarPalette.background)
        .clipShape(RoundedRectangle(cornerRadius: ControlBarPalette.barCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ControlBarPalette.barCornerRadius)
                .strokeBorder(ControlBarPalette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 14, y: 7)
        .environment(\.controlTooltipsEnabled, model.showRecorderControlTooltips)
        .onAppear {
            model.applyPreferences(preferences.snapshot)
            model.refreshCaptureChoices()
            model.refitControlBar()
        }
        .onChange(of: preferences.snapshot) { _, snapshot in
            model.applyPreferences(snapshot)
            model.refitControlBar()
        }
        .onChange(of: model.controlBarLayoutSignature) { _, _ in
            model.refitControlBar()
        }
    }

    private func completionControls(_ completion: QuickRecordingCompletion) -> some View {
        Group {
            CloseControlBarButton {
                model.dismissCompletion()
            }

            ControlBarDivider()

            VStack(alignment: .leading, spacing: 3) {
                Text(model.isRenderingCompletion ? "Exporting Video" : "Lesson Project Saved")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ControlBarPalette.primaryText)
                Text(model.isRenderingCompletion ? model.formattedCompletionRenderProgress : completion.projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ControlBarPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 190, alignment: .leading)

            ControlBarDivider()

            ControlBarButton(icon: "film.stack", title: "Review") {
                model.openCompletionInEditor()
            }

            ControlBarButton(icon: "square.and.arrow.down", title: model.isRenderingCompletion ? "Exporting" : "Export") {
                model.saveCompletionVideo(preferences.snapshot)
            }
            .disabled(model.isRenderingCompletion)

            ControlBarButton(icon: "folder", title: "Reveal Project") {
                model.revealCompletion()
            }

            ControlBarButton(icon: "doc.on.clipboard", title: "Copy") {
                model.copyCompletionPath()
            }

            ControlBarButton(icon: "shippingbox", title: model.isPackagingCompletion ? "Packing" : "Package") {
                model.packageCompletionForLearnHouse(preferences.snapshot)
            }
            .disabled(model.isPackagingCompletion)

            ControlBarDivider()

            PrimaryControlBarButton(icon: "record.circle.fill", title: "New Recording") {
                model.dismissCompletion()
                model.startRecording(preferences.snapshot)
            }
        }
    }

    private var setupControls: some View {
        Group {
            CloseControlBarButton {
                model.closeControlBar()
            }

            ControlBarDivider()

            ControlBarButton(icon: QuickRecordTarget.screen.iconName, title: "Display", isProminent: model.recordTarget == .screen) {
                model.recordTarget = .screen
                showDisplayPopover.toggle()
            }
            .popover(isPresented: $showDisplayPopover, arrowEdge: .bottom) {
                DisplayPopover(model: model)
                    .padding(14)
                    .frame(width: 240)
            }

            ControlBarButton(icon: "macwindow", title: "Window", isProminent: model.recordTarget == .window) {
                model.recordTarget = .window
                showWindowPopover.toggle()
            }
            .popover(isPresented: $showWindowPopover, arrowEdge: .bottom) {
                WindowPopover(model: model)
                    .padding(14)
                    .frame(width: 260)
            }

            ControlBarButton(icon: "rectangle.dashed", title: "Area", isProminent: model.recordTarget == .region) {
                model.recordTarget = .region
                showRegionPopover.toggle()
            }
            .popover(isPresented: $showRegionPopover, arrowEdge: .bottom) {
                RegionPopover(model: model)
                    .padding(14)
                    .frame(width: 340)
            }

            ControlBarDivider()

            ControlBarButton(
                icon: model.captureWebcam ? "web.camera.fill" : "video.slash",
                title: model.captureWebcam ? "Camera" : "No Cam",
                isProminent: model.captureWebcam,
                isSubdued: !model.captureWebcam
            ) {
                showCameraPopover.toggle()
            }
            .popover(isPresented: $showCameraPopover, arrowEdge: .bottom) {
                CameraPopover(model: model, preferences: preferences)
                    .padding(14)
                    .frame(width: 380)
            }

            ControlBarButton(
                icon: model.captureMicrophone ? "mic.fill" : "mic.slash",
                title: model.captureMicrophone ? "Mic" : "No Mic",
                isProminent: model.captureMicrophone,
                isSubdued: !model.captureMicrophone
            ) {
                showMicrophonePopover.toggle()
            }
            .popover(isPresented: $showMicrophonePopover, arrowEdge: .bottom) {
                MicrophonePopover(model: model, preferences: preferences)
                    .padding(14)
                    .frame(width: 300)
            }

            ControlBarButton(
                icon: model.captureSystemAudio ? "speaker.wave.2.fill" : "speaker.slash",
                title: model.captureSystemAudio ? "Audio" : "No Audio",
                isProminent: model.captureSystemAudio,
                isSubdued: !model.captureSystemAudio
            ) {
                model.captureSystemAudio.toggle()
            }

            ControlBarDivider()

            ControlBarButton(icon: "paintpalette", title: "Annotate") {
                model.toggleAnnotationOverlay(preferences.snapshot)
            }

            permissionActions

            ControlBarButton(icon: "gearshape", title: "Options") {
                showOptionsPopover.toggle()
            }
            .popover(isPresented: $showOptionsPopover, arrowEdge: .bottom) {
                RecordingOptionsPopover(model: model, preferences: preferences)
                    .padding(14)
                    .frame(width: 330)
            }

            ControlBarDivider()

            PrimaryControlBarButton(icon: "record.circle.fill", title: "Start") {
                model.startRecording(preferences.snapshot)
            }
            .disabled(!model.canStart)
            .controlHelp(model.startHelpText, isEnabled: model.showRecorderControlTooltips)
        }
    }

    private var recordingControls: some View {
        Group {
            ControlBarButton(icon: "eye.slash", title: "Hide") {
                model.hideControlBar()
            }
            .disabled(model.isStopping)

            ControlBarDivider()

            Circle()
                .fill(model.isStopping ? Color.secondary : (model.isPaused ? Color.orange : ControlBarPalette.recordFill))
                .frame(width: 11, height: 11)
                .padding(.horizontal, 6)

            Text(model.isStopping ? "Stopping..." : model.formattedElapsed)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(ControlBarPalette.primaryText)
                .frame(minWidth: 68, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: model.recordTarget.iconName)
                if model.captureMicrophone {
                    Image(systemName: "mic.fill")
                }
                if model.captureSystemAudio {
                    Image(systemName: "speaker.wave.2.fill")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ControlBarPalette.secondaryText)
            .padding(.horizontal, 6)

            ControlBarDivider()

            if model.captureWebcam {
                RecordingWebcamPreviewButton(model: model) {
                    showCameraPopover.toggle()
                }
                .popover(isPresented: $showCameraPopover, arrowEdge: .bottom) {
                    CameraPopover(model: model, preferences: preferences)
                        .padding(14)
                        .frame(width: 380)
                }

                ControlBarDivider()
            }

            ControlBarButton(icon: "paintpalette", title: "Annotate") {
                model.toggleAnnotationOverlay(preferences.snapshot)
            }
            .disabled(model.isStopping)

            ControlBarButton(icon: "flag.fill", title: model.recordingMarkerCount == 0 ? "Flag" : "Flag \(model.recordingMarkerCount)") {
                model.markRecording()
            }
            .disabled(model.isStopping)

            ControlBarButton(
                icon: model.isPaused ? "play.fill" : "pause.fill",
                title: model.isPaused ? "Resume" : "Pause",
                isProminent: model.isPaused
            ) {
                model.togglePause()
            }
            .disabled(model.isStopping)

            ControlBarButton(icon: "arrow.clockwise", title: "Restart") {
                model.confirmRestartRecording()
            }
            .disabled(model.isStopping)

            ControlBarButton(icon: "trash", title: "Delete", isDestructive: true) {
                model.confirmDiscardRecording()
            }
            .disabled(model.isStopping)

            PrimaryControlBarButton(icon: "stop.fill", title: "Stop") {
                model.stopRecording()
            }
            .disabled(model.isStopping)
        }
        .frame(height: ControlBarPalette.itemHeight)
    }

    @ViewBuilder private var permissionActions: some View {
        if !model.screenGranted {
            PermissionButton(title: "Screen") {
                model.requestPermission()
            }
        } else if model.captureMicrophone, !model.microphoneGranted {
            PermissionButton(title: "Mic") {
                model.requestMicrophonePermission()
            }
        } else if model.captureWebcam, !model.cameraGranted {
            PermissionButton(title: "Camera") {
                model.requestCameraPermission()
            }
        }
    }
}

private struct RecordingStatusPill: View {
    var isPaused: Bool
    var isStopping: Bool
    var elapsed: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isStopping ? Color.secondary : (isPaused ? Color.orange : Color.red))
                .frame(width: 8, height: 8)
            Text(isStopping ? "Stopping" : elapsed)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
    }
}

private struct CloseControlBarButton: View {
    var action: () -> Void
    @Environment(\.controlTooltipsEnabled) private var tooltipsEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: ControlBarPalette.iconSize, weight: .semibold))
                .foregroundStyle(ControlBarPalette.primaryText)
                .frame(width: ControlBarPalette.itemWidth, height: ControlBarPalette.itemHeight)
                .background(isHovered ? ControlBarPalette.hoverFill : ControlBarPalette.buttonFill, in: RoundedRectangle(cornerRadius: ControlBarPalette.cornerRadius))
                .contentShape(RoundedRectangle(cornerRadius: ControlBarPalette.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .controlHelp("Close", isEnabled: tooltipsEnabled)
        .accessibilityLabel("Close")
    }
}

private struct PermissionButton: View {
    var title: String
    var action: () -> Void
    @Environment(\.controlTooltipsEnabled) private var tooltipsEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "lock.open")
                .font(.system(size: ControlBarPalette.iconSize, weight: .semibold))
            .foregroundStyle(.orange)
            .frame(width: ControlBarPalette.itemWidth, height: ControlBarPalette.itemHeight)
            .background(isHovered ? Color.orange.opacity(0.22) : Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: ControlBarPalette.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .controlHelp("Grant \(title) permission", isEnabled: tooltipsEnabled)
        .accessibilityLabel("Grant \(title) permission")
    }
}

private struct RecordingOptionsPopover: View {
    @ObservedObject var model: QuickRecorderModel
    @ObservedObject var preferences: AppPreferencesController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recording Options")
                .font(.headline)

            Toggle("Auto-stop recording", isOn: $model.autoStopEnabled)

            if model.autoStopEnabled {
                Stepper(
                    "Stop after \(model.formattedMaxDuration)",
                    value: $model.recordDurationSeconds,
                    in: 30...7_200,
                    step: 30
                )
            } else {
                Text("Recordings continue until you press Stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Hide controls from screenshots and recordings", isOn: hiddenFromCaptureBinding)
            Toggle("Show hover tooltips", isOn: tooltipsBinding)
        }
    }

    private var hiddenFromCaptureBinding: Binding<Bool> {
        Binding {
            model.hideRecorderControlsFromCapture
        } set: { value in
            model.setHideRecorderControlsFromCapture(value)
            preferences.update { snapshot in
                snapshot.capture.hideRecorderControlsFromCapture = value
            }
        }
    }

    private var tooltipsBinding: Binding<Bool> {
        Binding {
            model.showRecorderControlTooltips
        } set: { value in
            model.setShowRecorderControlTooltips(value)
            preferences.update { snapshot in
                snapshot.capture.showRecorderControlTooltips = value
            }
        }
    }
}

private struct ControlBarButton: View {
    var icon: String
    var title: String
    var isProminent = false
    var isSubdued = false
    var isDestructive = false
    var action: () -> Void
    @Environment(\.controlTooltipsEnabled) private var tooltipsEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: ControlBarPalette.iconSize, weight: .semibold))
            .foregroundStyle(foregroundStyle)
            .frame(width: ControlBarPalette.itemWidth, height: ControlBarPalette.itemHeight)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: ControlBarPalette.cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: ControlBarPalette.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .controlHelp(title, isEnabled: tooltipsEnabled)
        .accessibilityLabel(title)
    }

    private var foregroundStyle: Color {
        if isDestructive {
            return .red
        }
        if isSubdued {
            return ControlBarPalette.disabledText
        }
        return isProminent ? ControlBarPalette.primaryText : ControlBarPalette.secondaryText
    }

    private var backgroundStyle: Color {
        if isProminent {
            return ControlBarPalette.activeFill
        }
        if isDestructive {
            return Color.red.opacity(0.16)
        }
        if isHovered {
            return ControlBarPalette.hoverFill
        }
        return Color.clear
    }
}

private struct PrimaryControlBarButton: View {
    var icon: String
    var title: String
    var action: () -> Void
    @Environment(\.controlTooltipsEnabled) private var tooltipsEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: ControlBarPalette.iconSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: ControlBarPalette.itemWidth, height: ControlBarPalette.itemHeight)
            .background(isHovered ? ControlBarPalette.recordHoverFill : ControlBarPalette.recordFill, in: RoundedRectangle(cornerRadius: ControlBarPalette.cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: ControlBarPalette.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .controlHelp(title, isEnabled: tooltipsEnabled)
        .accessibilityLabel(title)
    }
}

private struct ControlBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(ControlBarPalette.divider)
            .frame(width: 1, height: 24)
            .padding(.horizontal, ControlBarPalette.dividerInset)
    }
}

private enum ControlBarPalette {
    static let itemWidth: CGFloat = 38
    static let itemHeight: CGFloat = 38
    static let itemGap: CGFloat = 2
    static let outerPadding: CGFloat = 8
    static let dividerInset: CGFloat = 6
    static let cornerRadius: CGFloat = 8
    static let barCornerRadius: CGFloat = 13
    static let iconSize: CGFloat = 17
    static let labelFont = Font.system(size: 13, weight: .semibold)
    static let background = Color(red: 0.09, green: 0.09, blue: 0.10).opacity(0.98)
    static let border = Color.white.opacity(0.14)
    static let divider = Color.white.opacity(0.13)
    static let buttonFill = Color.white.opacity(0.06)
    static let hoverFill = Color.white.opacity(0.11)
    static let activeFill = Color.white.opacity(0.13)
    static let recordFill = Color(red: 0.96, green: 0.17, blue: 0.18)
    static let recordHoverFill = Color(red: 1.0, green: 0.24, blue: 0.25)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.72)
    static let disabledText = Color.white.opacity(0.43)
}

private struct ControlTooltipsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var controlTooltipsEnabled: Bool {
        get { self[ControlTooltipsEnabledKey.self] }
        set { self[ControlTooltipsEnabledKey.self] = newValue }
    }
}

private extension View {
    @ViewBuilder
    func controlHelp(_ text: String, isEnabled: Bool) -> some View {
        if isEnabled {
            help(text)
        } else {
            self
        }
    }
}

private struct DisplayPopover: View {
    @ObservedObject var model: QuickRecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display")
                .font(.headline)

            ForEach(model.displayChoices) { display in
                Button {
                    model.recordTarget = .screen
                    model.selectedDisplayID = display.id
                } label: {
                    HStack {
                        Text(display.displayName)
                        Spacer()
                        if model.selectedDisplayID == display.id {
                            Image(systemName: "checkmark")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            if model.displayChoices.isEmpty {
                Text("No displays were found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CameraPopover: View {
    @ObservedObject var model: QuickRecorderModel
    @ObservedObject var preferences: AppPreferencesController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera")
                .font(.headline)

            WebcamPreviewCard(model: model)

            Toggle("Capture webcam", isOn: captureWebcamBinding)

            Divider()

            if model.cameraChoices.isEmpty {
                Text("No cameras were found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Camera", selection: selectedCameraBinding) {
                    ForEach(model.cameraChoices) { camera in
                        Text(camera.name).tag(camera.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isRecording)
            }

            Picker("Format", selection: webcamAspectRatioBinding) {
                ForEach(WebcamAspectRatio.allCases) { ratio in
                    Text(ratio.displayName).tag(ratio)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.webcamFrameShape == .circle)
            .opacity(model.webcamFrameShape == .circle ? 0.48 : 1)
            .help(model.webcamFrameShape == .circle ? "Circle webcam frames always use a 1:1 crop." : "Choose the webcam frame format.")

            Picker("Frame", selection: webcamFrameShapeBinding) {
                ForEach(WebcamFrameShape.allCases) { shape in
                    Text(shape.displayName).tag(shape)
                }
            }
            .pickerStyle(.segmented)

            if model.webcamFrameShape == .roundedRectangle {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Corner radius: \(Int(model.webcamCornerRadius))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: webcamCornerRadiusBinding, in: 0...64, step: 1)
                }
            }

            HStack(spacing: 12) {
                Picker("Resolution", selection: cameraResolutionBinding) {
                    ForEach(CameraResolution.allCases) { resolution in
                        Text(resolution.rawValue).tag(resolution)
                    }
                }
                .pickerStyle(.menu)

                Picker("FPS", selection: webcamFPSBinding) {
                    ForEach(CapturePreferences.supportedWebcamFPS, id: \.self) { fps in
                        Text("\(fps)").tag(fps)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 14) {
                Toggle("Mirror", isOn: webcamMirrorBinding)
                Toggle("Border", isOn: webcamBorderBinding)
                Toggle("Shadow", isOn: webcamShadowBinding)
            }

            Toggle("Floating preview while recording", isOn: floatingPreviewBinding)
                .disabled(!model.captureWebcam)
        }
    }

    private var captureWebcamBinding: Binding<Bool> {
        Binding {
            model.captureWebcam
        } set: { value in
            model.captureWebcam = value
            preferences.update { snapshot in
                snapshot.capture.captureWebcam = value
            }
        }
    }

    private var selectedCameraBinding: Binding<String> {
        Binding {
            model.selectedCameraID ?? model.cameraChoices.first?.id ?? ""
        } set: { value in
            model.selectedCameraID = value.isEmpty ? nil : value
            model.captureWebcam = true
            preferences.update { snapshot in
                snapshot.capture.captureWebcam = true
            }
        }
    }

    private var cameraResolutionBinding: Binding<CameraResolution> {
        Binding {
            model.cameraResolution
        } set: { value in
            model.cameraResolution = value
            preferences.update { snapshot in
                snapshot.capture.cameraResolution = value
            }
        }
    }

    private var webcamFPSBinding: Binding<Int> {
        Binding {
            model.webcamFPS
        } set: { value in
            model.webcamFPS = value
            preferences.update { snapshot in
                snapshot.capture.webcamFPS = value
            }
        }
    }

    private var webcamAspectRatioBinding: Binding<WebcamAspectRatio> {
        Binding {
            model.webcamAspectRatio
        } set: { value in
            model.webcamAspectRatio = value
            model.updateFloatingWebcamPreviewStyle()
            preferences.update { snapshot in
                snapshot.capture.webcamAspectRatio = value
            }
        }
    }

    private var webcamFrameShapeBinding: Binding<WebcamFrameShape> {
        Binding {
            model.webcamFrameShape
        } set: { value in
            model.webcamFrameShape = value
            model.updateFloatingWebcamPreviewStyle()
            preferences.update { snapshot in
                snapshot.capture.webcamFrameShape = value
            }
        }
    }

    private var webcamCornerRadiusBinding: Binding<Double> {
        Binding {
            model.webcamCornerRadius
        } set: { value in
            model.webcamCornerRadius = value
            model.updateFloatingWebcamPreviewStyle()
            preferences.update { snapshot in
                snapshot.capture.webcamCornerRadius = value
            }
        }
    }

    private var webcamMirrorBinding: Binding<Bool> {
        Binding {
            model.webcamMirror
        } set: { value in
            model.webcamMirror = value
            model.updateFloatingWebcamPreviewStyle()
            preferences.update { snapshot in
                snapshot.capture.webcamMirror = value
            }
        }
    }

    private var webcamBorderBinding: Binding<Bool> {
        Binding {
            model.webcamBorderEnabled
        } set: { value in
            model.webcamBorderEnabled = value
            model.updateFloatingWebcamPreviewStyle()
            preferences.update { snapshot in
                snapshot.capture.webcamBorderEnabled = value
            }
        }
    }

    private var webcamShadowBinding: Binding<Bool> {
        Binding {
            model.webcamShadowEnabled
        } set: { value in
            model.webcamShadowEnabled = value
            model.updateFloatingWebcamPreviewStyle()
            preferences.update { snapshot in
                snapshot.capture.webcamShadowEnabled = value
            }
        }
    }

    private var floatingPreviewBinding: Binding<Bool> {
        Binding {
            model.showFloatingWebcamPreview
        } set: { value in
            model.setShowFloatingWebcamPreview(value)
            preferences.update { snapshot in
                snapshot.capture.showFloatingWebcamPreview = value
            }
        }
    }
}

private struct MicrophonePopover: View {
    @ObservedObject var model: QuickRecorderModel
    @ObservedObject var preferences: AppPreferencesController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Microphone")
                .font(.headline)

            Toggle("Capture microphone", isOn: captureMicrophoneBinding)

            Divider()

            if !model.microphoneGranted {
                Text("Microphone permission is required before devices can be captured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Grant Access") {
                    model.requestMicrophonePermission()
                }
            } else if model.microphoneChoices.isEmpty {
                Text("No microphones were found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Input", selection: selectedMicrophoneBinding) {
                    Text("System Default").tag("")
                    ForEach(model.microphoneChoices) { microphone in
                        Text(microphone.name).tag(microphone.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isRecording || !model.captureMicrophone)
            }

            Text(model.selectedMicrophoneName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .onAppear {
            model.refreshCaptureChoices()
        }
    }

    private var captureMicrophoneBinding: Binding<Bool> {
        Binding {
            model.captureMicrophone
        } set: { value in
            model.captureMicrophone = value
            preferences.update { snapshot in
                snapshot.capture.captureMicrophone = value
            }
        }
    }

    private var selectedMicrophoneBinding: Binding<String> {
        Binding {
            model.selectedMicrophoneID ?? ""
        } set: { value in
            model.selectedMicrophoneID = value.isEmpty ? nil : value
            model.captureMicrophone = true
            preferences.update { snapshot in
                snapshot.capture.microphoneDeviceID = value.isEmpty ? nil : value
                snapshot.capture.captureMicrophone = true
            }
        }
    }
}

private struct WebcamPreviewCard: View {
    @ObservedObject var model: QuickRecorderModel

    var body: some View {
        Group {
            if !model.captureWebcam {
                WebcamPreviewPlaceholder(icon: "video.slash", title: "Webcam is off")
            } else if !model.cameraGranted {
                WebcamPreviewPlaceholder(icon: "lock", title: "Camera permission needed")
            } else if model.cameraChoices.isEmpty {
                WebcamPreviewPlaceholder(icon: "web.camera", title: "No camera found")
            } else if let sessionBox = model.cameraPreviewSession {
                StyledWebcamPreview(model: model) {
                    CameraSessionPreviewView(sessionBox: sessionBox)
                }
            } else {
                WebcamSetupPreview(model: model)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WebcamSetupPreview: View {
    @ObservedObject var model: QuickRecorderModel
    @StateObject private var previewController = WebcamPreviewSessionController()

    var body: some View {
        StyledWebcamPreview(model: model) {
            CameraSessionPreviewView(sessionBox: previewController.sessionBox)
        }
        .onAppear(perform: configurePreview)
        .onDisappear {
            previewController.stop()
        }
        .onChange(of: model.selectedCameraID) { _, _ in
            configurePreview()
        }
        .onChange(of: model.cameraResolution) { _, _ in
            configurePreview()
        }
        .onChange(of: model.webcamFPS) { _, _ in
            configurePreview()
        }
    }

    private func configurePreview() {
        guard model.captureWebcam, model.cameraGranted else { return }
        previewController.configure(
            deviceID: model.selectedCameraID,
            resolution: model.cameraResolution,
            fps: model.webcamFPS
        )
    }
}

private struct RecordingWebcamPreviewButton: View {
    @ObservedObject var model: QuickRecorderModel
    var action: () -> Void
    @Environment(\.controlTooltipsEnabled) private var tooltipsEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if let sessionBox = model.cameraPreviewSession {
                    CameraSessionPreviewView(sessionBox: sessionBox)
                        .scaleEffect(x: model.webcamMirror ? -1 : 1, y: 1)
                } else {
                    Image(systemName: model.cameraGranted ? "web.camera" : "lock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ControlBarPalette.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ControlBarPalette.buttonFill)
                }
            }
            .frame(width: recordingPreviewWidth, height: ControlBarPalette.itemHeight)
            .clipShape(WebcamPreviewClipShape(
                frameShape: model.webcamFrameShape,
                cornerRadius: model.recordingPreviewCornerRadius
            ))
            .overlay(
                WebcamPreviewClipShape(
                    frameShape: model.webcamFrameShape,
                    cornerRadius: model.recordingPreviewCornerRadius
                )
                .strokeBorder(isHovered ? ControlBarPalette.primaryText.opacity(0.35) : ControlBarPalette.border, lineWidth: 1)
            )
            .contentShape(WebcamPreviewClipShape(
                frameShape: model.webcamFrameShape,
                cornerRadius: model.recordingPreviewCornerRadius
            ))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .controlHelp("Webcam preview and settings", isEnabled: tooltipsEnabled)
        .accessibilityLabel("Webcam preview and settings")
    }

    private var recordingPreviewWidth: CGFloat {
        let aspect = model.webcamFrameShape == .circle ? 1 : model.webcamAspectRatio.previewWidthToHeightRatio
        return max(ControlBarPalette.itemHeight, min(76, ControlBarPalette.itemHeight * aspect))
    }
}

private struct FloatingWebcamPreviewPanel: View {
    @ObservedObject var model: QuickRecorderModel

    var body: some View {
        ZStack {
            if let sessionBox = model.cameraPreviewSession {
                CameraSessionPreviewView(sessionBox: sessionBox)
                    .scaleEffect(x: model.webcamMirror ? -1 : 1, y: 1)
            } else {
                ZStack {
                    Color.black.opacity(0.35)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(width: model.floatingWebcamPreviewSize.width, height: model.floatingWebcamPreviewSize.height)
        .clipShape(WebcamPreviewClipShape(
            frameShape: model.webcamFrameShape,
            cornerRadius: model.previewCornerRadius
        ))
        .overlay(
            WebcamPreviewClipShape(
                frameShape: model.webcamFrameShape,
                cornerRadius: model.previewCornerRadius
            )
            .strokeBorder(
                model.webcamBorderEnabled ? Color.white.opacity(0.68) : Color.white.opacity(0.18),
                lineWidth: model.webcamBorderEnabled ? 2 : 1
            )
        )
        .shadow(color: .black.opacity(model.webcamShadowEnabled ? 0.42 : 0), radius: 18, y: 10)
        .background(Color.clear)
    }
}

private struct StyledWebcamPreview<Content: View>: View {
    @ObservedObject var model: QuickRecorderModel
    private let content: Content

    init(model: QuickRecorderModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .aspectRatio(model.webcamPreviewAspectRatio, contentMode: .fit)
            .scaleEffect(x: model.webcamMirror ? -1 : 1, y: 1)
            .clipShape(WebcamPreviewClipShape(
                frameShape: model.webcamFrameShape,
                cornerRadius: model.previewCornerRadius
            ))
            .overlay(
                WebcamPreviewClipShape(
                    frameShape: model.webcamFrameShape,
                    cornerRadius: model.previewCornerRadius
                )
                .strokeBorder(
                    model.webcamBorderEnabled ? Color.white.opacity(0.62) : Color.white.opacity(0.16),
                    lineWidth: model.webcamBorderEnabled ? 2 : 1
                )
            )
            .shadow(color: .black.opacity(model.webcamShadowEnabled ? 0.38 : 0), radius: 16, y: 8)
            .background(Color.black.opacity(0.22))
    }
}

private struct WebcamPreviewPlaceholder: View {
    var icon: String
    var title: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.26))
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct CameraSessionPreviewView: NSViewRepresentable {
    var sessionBox: CameraPreviewSessionBox

    func makeNSView(context: Context) -> WebcamPreviewLayerView {
        WebcamPreviewLayerView(session: sessionBox.session)
    }

    func updateNSView(_ view: WebcamPreviewLayerView, context: Context) {
        view.setSession(sessionBox.session)
    }
}

private final class WebcamPreviewLayerView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    func setSession(_ session: AVCaptureSession) {
        guard previewLayer.session !== session else { return }
        previewLayer.session = session
    }
}

private final class WebcamPreviewSessionController: ObservableObject, @unchecked Sendable {
    let sessionBox: CameraPreviewSessionBox

    private let session: AVCaptureSession
    private let queue = DispatchQueue(label: "io.digitalmeld.lessonmeld.webcam-preview", qos: .userInitiated)
    private let lock = NSLock()
    private var configurationKey: String?

    init() {
        let session = AVCaptureSession()
        self.session = session
        sessionBox = CameraPreviewSessionBox(session: session)
    }

    deinit {
        stop()
    }

    func configure(deviceID: String?, resolution: CameraResolution, fps: Int) {
        let nextKey = "\(deviceID ?? "default")|\(resolution.rawValue)|\(fps)"
        lock.lock()
        let shouldConfigure = configurationKey != nextKey
        configurationKey = nextKey
        lock.unlock()
        guard shouldConfigure else {
            startIfNeeded()
            return
        }

        nonisolated(unsafe) let unsafeSession = session
        queue.async { [deviceID, resolution, fps] in
            guard CameraPermission.isGranted,
                  let device = Self.selectDevice(id: deviceID),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                return
            }

            unsafeSession.beginConfiguration()
            let preset = Self.sessionPreset(for: resolution)
            if unsafeSession.canSetSessionPreset(preset) {
                unsafeSession.sessionPreset = preset
            }
            unsafeSession.inputs.forEach { unsafeSession.removeInput($0) }
            if unsafeSession.canAddInput(input) {
                unsafeSession.addInput(input)
                try? Self.configureFrameRate(fps, on: device)
            }
            unsafeSession.commitConfiguration()

            if !unsafeSession.isRunning {
                unsafeSession.startRunning()
            }
        }
    }

    func stop() {
        nonisolated(unsafe) let unsafeSession = session
        queue.async {
            if unsafeSession.isRunning {
                unsafeSession.stopRunning()
            }
        }
    }

    private func startIfNeeded() {
        nonisolated(unsafe) let unsafeSession = session
        queue.async {
            if !unsafeSession.isRunning {
                unsafeSession.startRunning()
            }
        }
    }

    private static func selectDevice(id: String?) -> AVCaptureDevice? {
        if let id {
            return discoverySession.devices.first { $0.uniqueID == id }
        }
        return AVCaptureDevice.default(for: .video)
    }

    private static func configureFrameRate(_ fps: Int, on device: AVCaptureDevice) throws {
        let requestedFPS = Double(fps)
        guard device.activeFormat.videoSupportedFrameRateRanges.contains(where: { range in
            range.minFrameRate <= requestedFPS && requestedFPS <= range.maxFrameRate
        }) else {
            return
        }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
        device.unlockForConfiguration()
    }

    private static func sessionPreset(for resolution: CameraResolution) -> AVCaptureSession.Preset {
        switch resolution {
        case .p720:
            .hd1280x720
        case .p4K:
            .hd4K3840x2160
        case .p1080:
            .hd1920x1080
        }
    }

    private static var discoverySession: AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
    }
}

private struct WebcamPreviewClipShape: InsettableShape {
    var frameShape: WebcamFrameShape
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        switch frameShape {
        case .circle:
            return Path(ellipseIn: insetRect)
        case .square:
            var path = Path()
            path.addRect(insetRect)
            return path
        case .roundedRectangle:
            return Path(roundedRect: insetRect, cornerRadius: cornerRadius)
        }
    }

    func inset(by amount: CGFloat) -> WebcamPreviewClipShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private extension WebcamAspectRatio {
    var previewWidthToHeightRatio: CGFloat {
        switch self {
        case .original:
            4.0 / 3.0
        case .square1x1:
            1.0
        case .portrait2x3:
            2.0 / 3.0
        case .landscape3x2:
            3.0 / 2.0
        case .widescreen16x9:
            16.0 / 9.0
        }
    }
}

private struct RegionPopover: View {
    @ObservedObject var model: QuickRecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Region")
                .font(.headline)
            Button {
                model.selectRegionInteractively()
            } label: {
                Label("Select Area...", systemImage: "rectangle.dashed")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("X")
                    TextField("0", text: $model.recordRegionX)
                    Text("Y")
                    TextField("0", text: $model.recordRegionY)
                }
                GridRow {
                    Text("W")
                    TextField("1280", text: $model.recordRegionWidth)
                    Text("H")
                    TextField("720", text: $model.recordRegionHeight)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            Text("Coordinates are stored as ScreenCaptureKit display-local values.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WindowPopover: View {
    @ObservedObject var model: QuickRecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Window Capture")
                .font(.headline)
            if model.windowChoices.isEmpty {
                Text("No recordable windows were found. Refresh or enter a ScreenCaptureKit window ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.windowChoices) { window in
                            Button {
                                model.recordWindowID = "\(window.id)"
                                model.recordTarget = .window
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(window.title)
                                        .lineLimit(1)
                                    Text(window.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            Button {
                model.refreshCaptureChoices()
            } label: {
                Label("Refresh Windows", systemImage: "arrow.clockwise")
            }
            TextField("Window ID", text: $model.recordWindowID)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Text("Window capture uses the selected ScreenCaptureKit window ID.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class QuickRecorderModel: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var isStopping = false
    @Published var screenGranted = ScreenCapturePermission.isGranted
    @Published var microphoneGranted = MicrophonePermission.isGranted
    @Published var cameraGranted = CameraPermission.isGranted
    @Published var message = readyMessage
    @Published var lastProjectPath: String?

    @Published var recordTarget: QuickRecordTarget = .screen
    @Published var autoStopEnabled = false
    @Published var recordDurationSeconds = 300
    @Published var captureMicrophone = true
    @Published var captureWebcam = true
    @Published var captureSystemAudio = false
    @Published var captureInteractionMetadata = true
    @Published var cameraResolution: CameraResolution = .p1080
    @Published var webcamFPS = 30
    @Published var webcamAspectRatio: WebcamAspectRatio = .widescreen16x9
    @Published var webcamFrameShape: WebcamFrameShape = .roundedRectangle
    @Published var webcamCornerRadius: Double = 18
    @Published var webcamRelativeSize: Double = 0.24
    @Published var webcamMirror = false
    @Published var webcamBorderEnabled = false
    @Published var webcamShadowEnabled = true
    @Published var showFloatingWebcamPreview = true
    @Published var hideRecorderControlsFromCapture = false
    @Published var showRecorderControlTooltips = true
    @Published var displayChoices: [QuickDisplayChoice] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var microphoneChoices: [QuickMicrophoneChoice] = []
    @Published var selectedMicrophoneID: String?
    @Published var cameraChoices: [QuickCameraChoice] = []
    @Published var selectedCameraID: String?
    @Published var windowChoices: [QuickWindowChoice] = []
    @Published var recordRegionX = "0"
    @Published var recordRegionY = "0"
    @Published var recordRegionWidth = "1280"
    @Published var recordRegionHeight = "720"
    @Published var recordWindowID = ""
    @Published var elapsedSeconds: TimeInterval = 0
    @Published private(set) var recordingMarkerCount = 0
    @Published var completion: QuickRecordingCompletion?
    @Published var isPackagingCompletion = false
    @Published var isRenderingCompletion = false
    @Published var completionRenderProgress = 0.0
    @Published var cameraPreviewSession: CameraPreviewSessionBox?

    private let recordingRuntime = QuickRecordingRuntime()
    private var controlBarWindow: QuickRecordingControlBarWindow?
    private var regionSelectionWindow: RegionSelectionWindow?
    private var elapsedTimer: Timer?
    private var lifecycle = RecordingLifecycleStateMachine()
    private var floatingWebcamPreviewWindow: FloatingWebcamPreviewWindow?
    private var recordingMarkers: [ProjectTimelineMarker] = []
    private var deleteAfterStop = false
    private var restartAfterStop = false
    private var lastStartPreferences: LessonMeldPreferences?
    private var lastPublishedStatusSecond = -1
    var openProjectHandler: ((URL) -> Void)?
    var annotationOverlayHandler: ((LessonMeldPreferences) -> Void)?

    var formattedElapsed: String {
        Self.formatClock(elapsedSeconds)
    }

    var formattedMaxDuration: String {
        Self.formatDuration(recordDurationSeconds)
    }

    var formattedCompletionRenderProgress: String {
        "\(Int((completionRenderProgress * 100).rounded()))% rendered"
    }

    var webcamPreviewAspectRatio: CGFloat {
        webcamFrameShape == .circle ? 1 : webcamAspectRatio.previewWidthToHeightRatio
    }

    var previewCornerRadius: CGFloat {
        switch webcamFrameShape {
        case .circle, .square:
            0
        case .roundedRectangle:
            CGFloat(webcamCornerRadius)
        }
    }

    var recordingPreviewCornerRadius: CGFloat {
        switch webcamFrameShape {
        case .circle, .square:
            0
        case .roundedRectangle:
            min(CGFloat(webcamCornerRadius), ControlBarPalette.itemHeight / 2)
        }
    }

    var floatingWebcamPreviewSize: CGSize {
        let width: CGFloat = 240
        return CGSize(width: width, height: round(width / max(webcamPreviewAspectRatio, 0.1)))
    }

    var effectiveRecordDurationSeconds: Int {
        autoStopEnabled ? recordDurationSeconds : Self.manualStopDurationSeconds
    }

    var selectedDisplayName: String {
        displayChoices.first { $0.id == selectedDisplayID }?.displayName ?? "Main Display"
    }

    var selectedMicrophoneName: String {
        guard captureMicrophone else { return "Microphone capture is off." }
        if let selectedMicrophoneID,
           let microphone = microphoneChoices.first(where: { $0.id == selectedMicrophoneID }) {
            return "Input: \(microphone.name)"
        }
        return MicrophoneCaptureDevices.defaultDevice.map { "Input: System Default (\($0.name))" } ?? "Input: System Default"
    }

    var canStart: Bool {
        !isRecording && !isStopping
    }

    var controlBarLayoutSignature: String {
        [
            isRecording ? "recording" : "idle",
            isPaused ? "paused" : "active",
            isStopping ? "stopping" : "running",
            completion == nil ? "setup" : "completion",
            captureWebcam ? "webcam" : "no-webcam",
            captureMicrophone ? "microphone" : "no-microphone",
            captureSystemAudio ? "system-audio" : "no-system-audio",
            recordTarget.rawValue,
            "\(recordingMarkerCount)",
            isRenderingCompletion ? "rendering" : "not-rendering",
            isPackagingCompletion ? "packaging" : "not-packaging"
        ].joined(separator: "|")
    }

    var startHelpText: String {
        if !screenGranted {
            return "Grant Screen Recording permission first."
        }
        if captureMicrophone, !microphoneGranted {
            return "Grant Microphone permission first."
        }
        if captureWebcam, !cameraGranted {
            return "Grant Camera permission first."
        }
        return "Start recording with the selected capture inputs."
    }

    func applyPreferences(_ preferences: LessonMeldPreferences) {
        setHideRecorderControlsFromCapture(preferences.capture.hideRecorderControlsFromCapture)
        setShowRecorderControlTooltips(preferences.capture.showRecorderControlTooltips)
        cameraResolution = preferences.capture.cameraResolution
        webcamFPS = preferences.capture.webcamFPS
        webcamAspectRatio = preferences.capture.webcamAspectRatio
        webcamFrameShape = preferences.capture.webcamFrameShape
        webcamCornerRadius = preferences.capture.webcamCornerRadius
        webcamRelativeSize = preferences.capture.webcamRelativeSize
        webcamMirror = preferences.capture.webcamMirror
        webcamBorderEnabled = preferences.capture.webcamBorderEnabled
        webcamShadowEnabled = preferences.capture.webcamShadowEnabled
        showFloatingWebcamPreview = preferences.capture.showFloatingWebcamPreview
        updateFloatingWebcamPreviewStyle()
        if isRecording {
            syncFloatingWebcamPreviewWindow()
        }

        guard !isRecording else { return }
        recordDurationSeconds = preferences.capture.quickRecordDurationSeconds
        captureMicrophone = preferences.capture.captureMicrophone
        selectedMicrophoneID = preferences.capture.microphoneDeviceID
        captureWebcam = preferences.capture.captureWebcam
        captureSystemAudio = preferences.capture.captureSystemAudio
        captureInteractionMetadata = preferences.capture.captureInteractionMetadata
    }

    func presentControlBar(preferences: AppPreferencesController) {
        applyPreferences(preferences.snapshot)
        refreshPermissions(updateMessage: true)
        refreshCaptureChoices()

        if let controlBarWindow {
            controlBarWindow.orderFrontRegardless()
            refitControlBar()
            return
        }

        let window = QuickRecordingControlBarWindow(
            rootView: QuickRecordingControlBar(model: self, preferences: preferences)
        ) { [weak self] in
            self?.controlBarWindow = nil
        }
        controlBarWindow = window
        window.setHiddenFromCapture(hideRecorderControlsFromCapture)
        window.orderFrontRegardless()
        message = "Choose capture target and inputs, then start recording from the control bar."
        publishStatus()
    }

    func refitControlBar() {
        Task { @MainActor in
            controlBarWindow?.refitToContent()
        }
    }

    func setHideRecorderControlsFromCapture(_ hide: Bool) {
        hideRecorderControlsFromCapture = hide
        controlBarWindow?.setHiddenFromCapture(hide)
        floatingWebcamPreviewWindow?.setHiddenFromCapture(hide)
    }

    func setShowRecorderControlTooltips(_ show: Bool) {
        showRecorderControlTooltips = show
    }

    func setShowFloatingWebcamPreview(_ show: Bool) {
        showFloatingWebcamPreview = show
        syncFloatingWebcamPreviewWindow()
    }

    func updateFloatingWebcamPreviewStyle() {
        floatingWebcamPreviewWindow?.updateSize(floatingWebcamPreviewSize)
    }

    func closeControlBar() {
        guard !isRecording, !isStopping else { return }
        completion = nil
        controlBarWindow?.close()
        controlBarWindow = nil
    }

    func dismissCompletion() {
        completion = nil
    }

    func hideControlBar() {
        controlBarWindow?.orderOut(nil)
        message = "Recording controls are hidden. Use the menu bar or Option-Command-R to show them."
    }

    func toggleAnnotationOverlay(_ preferences: LessonMeldPreferences) {
        guard let annotationOverlayHandler else {
            message = "Open the main window to use the annotation overlay."
            return
        }
        annotationOverlayHandler(preferences)
        message = "Toggled annotation overlay."
    }

    func refreshCaptureChoices() {
        displayChoices = NSScreen.screens.enumerated().map { index, screen in
            QuickDisplayChoice(id: screen.displayID, displayName: "Display \(index + 1)")
        }
        if selectedDisplayID == nil {
            selectedDisplayID = displayChoices.first?.id
        }
        microphoneChoices = MicrophoneCaptureDevices.available.map {
            QuickMicrophoneChoice(id: $0.id, name: $0.name)
        }
        if let selectedMicrophoneID,
           !microphoneChoices.contains(where: { $0.id == selectedMicrophoneID }) {
            self.selectedMicrophoneID = nil
        }
        cameraChoices = CameraCaptureDevices.available.map {
            QuickCameraChoice(id: $0.id, name: $0.name)
        }
        if selectedCameraID == nil {
            selectedCameraID = cameraChoices.first?.id
        }
        windowChoices = Self.availableWindowChoices()
        if recordWindowID.isEmpty {
            recordWindowID = windowChoices.first.map { "\($0.id)" } ?? ""
        }
    }

    func selectRegionInteractively() {
        guard let screen = Self.screen(for: selectedDisplayID) else {
            message = "No display is available for region selection."
            return
        }
        let window = RegionSelectionWindow(screen: screen) { [weak self] appKitRect in
            guard let self else { return }
            let displayID = screen.displayID
            let selection = SelectionRect(
                rect: appKitRect,
                displayID: displayID,
                displayFrame: screen.frame,
                backingScaleFactor: screen.backingScaleFactor
            )
            let rect = selection.screenCaptureKitRect
            self.selectedDisplayID = displayID
            self.recordTarget = .region
            self.recordRegionX = Self.formatRegionValue(rect.minX)
            self.recordRegionY = Self.formatRegionValue(rect.minY)
            self.recordRegionWidth = Self.formatRegionValue(rect.width)
            self.recordRegionHeight = Self.formatRegionValue(rect.height)
            self.regionSelectionWindow = nil
            self.message = "Selected \(Int(rect.width))x\(Int(rect.height)) recording area."
            self.controlBarWindow?.orderFrontRegardless()
        } onCancel: { [weak self] in
            self?.regionSelectionWindow = nil
            self?.controlBarWindow?.orderFrontRegardless()
        }
        regionSelectionWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func refreshPermissions(updateMessage: Bool = false) {
        let wasScreenGranted = screenGranted
        let wasMicrophoneGranted = microphoneGranted
        let wasCameraGranted = cameraGranted

        screenGranted = ScreenCapturePermission.isGranted
        microphoneGranted = MicrophonePermission.isGranted
        cameraGranted = CameraPermission.isGranted

        guard updateMessage, !isRecording, !isStopping else { return }
        if !wasScreenGranted, screenGranted {
            message = Self.readyMessage
        } else if !wasMicrophoneGranted, microphoneGranted {
            message = "Microphone permission is granted."
        } else if !wasCameraGranted, cameraGranted {
            message = "Camera permission is granted."
        }
    }

    func requestPermission() {
        _ = ScreenCapturePermission.requestAccess()
        refreshPermissions()
        message = screenGranted
            ? "Screen Recording permission is granted."
            : "macOS may require reopening the app after granting Screen Recording permission."
    }

    func requestMicrophonePermission() {
        Task {
            _ = await MicrophonePermission.requestAccess()
            await MainActor.run {
                self.refreshPermissions()
                self.message = self.microphoneGranted
                    ? "Microphone permission is granted."
                    : "Microphone permission is still missing."
            }
        }
    }

    func requestCameraPermission() {
        Task {
            _ = await CameraPermission.requestAccess()
            await MainActor.run {
                self.refreshPermissions()
                self.message = self.cameraGranted
                    ? "Camera permission is granted."
                    : "Camera permission is still missing."
            }
        }
    }

    func startRecording(_ preferences: LessonMeldPreferences) {
        guard !isRecording, !isStopping else { return }
        refreshPermissions()
        guard screenGranted else {
            requestPermission()
            return
        }
        if captureMicrophone, !microphoneGranted {
            requestMicrophonePermission()
            return
        }
        if captureWebcam, !cameraGranted {
            requestCameraPermission()
            return
        }

        do {
            let sourceRect = try makeSourceRect()
            let windowID = try makeWindowID()
            let recordTarget = recordTarget
            let metadataCaptureRect = Self.interactionMetadataCaptureRect(
                target: recordTarget,
                displayID: selectedDisplayID,
                sourceRect: sourceRect,
                windowID: windowID
            )
            let displayRecorder = DisplayScreenRecorder()
            let microphoneRecorder = captureMicrophone ? MicrophoneRecorder() : nil
            let cameraRecorder = captureWebcam ? CameraRecorder() : nil
            cameraPreviewSession = nil
            cameraRecorder?.previewSessionHandler = { [weak self] sessionBox in
                Task { @MainActor in
                    self?.cameraPreviewSession = sessionBox
                    self?.syncFloatingWebcamPreviewWindow()
                }
            }
            recordingRuntime.configure(
                displayRecorder: displayRecorder,
                microphoneRecorder: microphoneRecorder,
                cameraRecorder: cameraRecorder
            )
            lastStartPreferences = preferences
            deleteAfterStop = false
            restartAfterStop = false
            recordingMarkers = []
            recordingMarkerCount = 0
            completion = nil

            let startedAt = Date()
            applyLifecycleSnapshot(lifecycle.start(at: startedAt))
            syncFloatingWebcamPreviewWindow()
            startElapsedTimer()
            message = autoStopEnabled
                ? "Recording \(enabledTrackLabels) from \(recordTarget.displayName.lowercased()) for up to \(formattedMaxDuration)..."
                : "Recording \(enabledTrackLabels) from \(recordTarget.displayName.lowercased()). Press Stop to finish."
            publishStatus()

            let duration = TimeInterval(effectiveRecordDurationSeconds)
            let displayID = selectedDisplayID
            let microphoneDeviceID = selectedMicrophoneID
            let cameraDeviceID = selectedCameraID
            let captureMicrophone = captureMicrophone
            let captureWebcam = captureWebcam
            let captureSystemAudio = captureSystemAudio
            let captureInteractionMetadata = captureInteractionMetadata
            let taskRegistry = recordingRuntime.taskRegistry

            let task = Task {
                var metadataCapture: InteractionMetadataCaptureSession?
                do {
                    if preferences.capture.countdownSeconds > 0 {
                        try await Self.runCountdown(seconds: preferences.capture.countdownSeconds) { remaining in
                            await MainActor.run {
                                self.message = "Recording starts in \(remaining)..."
                            }
                        }
                        await MainActor.run {
                            self.applyLifecycleSnapshot(self.lifecycle.start(at: Date()))
                            self.startElapsedTimer()
                            self.message = self.autoStopEnabled
                                ? "Recording \(self.enabledTrackLabels) from \(self.recordTarget.displayName.lowercased()) for up to \(self.formattedMaxDuration)..."
                                : "Recording \(self.enabledTrackLabels) from \(self.recordTarget.displayName.lowercased()). Press Stop to finish."
                        }
                    }
                    metadataCapture = await MainActor.run {
                        guard captureInteractionMetadata else { return nil }
                        let session = InteractionMetadataCaptureSession(
                            captureRect: metadataCaptureRect,
                            rendersCursorPointer: !preferences.capture.includeCursor
                        )
                        session.start()
                        self.recordingRuntime.interactionMetadataCapture = session
                        return session
                    }

                    var result = try await Self.recordProject(
                        preferences: preferences,
                        duration: duration,
                        displayID: displayID,
                        sourceRect: sourceRect,
                        windowID: windowID,
                        recordTarget: recordTarget,
                        captureMicrophone: captureMicrophone,
                        captureWebcam: captureWebcam,
                        captureSystemAudio: captureSystemAudio,
                        microphoneDeviceID: microphoneDeviceID,
                        cameraDeviceID: cameraDeviceID,
                        displayRecorder: displayRecorder,
                        microphoneRecorder: microphoneRecorder,
                        cameraRecorder: cameraRecorder,
                        taskRegistry: taskRegistry
                    )
                    if let metadataCapture {
                        let document = await MainActor.run {
                            self.recordingRuntime.interactionMetadataCapture = nil
                            return metadataCapture.stop()
                        }
                        try Self.persistInteractionMetadata(document, to: result.projectURL, manifest: &result.manifest)
                    }
                    await MainActor.run {
                        self.finishRecording(
                            projectURL: result.projectURL,
                            screenSize: result.screen.screenSize,
                            recordTarget: recordTarget,
                            warnings: result.warnings
                        )
                    }
                } catch {
                    if let metadataCapture {
                        await MainActor.run {
                            self.recordingRuntime.interactionMetadataCapture = nil
                            _ = metadataCapture.stop()
                        }
                    }
                    await MainActor.run {
                        self.failRecording(error)
                    }
                }
            }
            recordingRuntime.setRecordingTask(task)
        } catch {
            message = error.localizedDescription
        }
    }

    func togglePause() {
        guard isRecording, !isStopping else { return }
        if isPaused {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        applyLifecycleSnapshot(lifecycle.pause())
        recordingRuntime.pause()
        message = "Recording paused."
        publishStatus()
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        applyLifecycleSnapshot(lifecycle.resume())
        recordingRuntime.resume()
        message = "Recording resumed."
        publishStatus()
    }

    func stopRecording() {
        guard isRecording, !isStopping else { return }
        applyLifecycleSnapshot(lifecycle.requestStop())
        message = "Stopping recording and writing the project bundle..."
        publishStatus()
        recordingRuntime.requestStop()
    }

    func markRecording() {
        guard isRecording, !isStopping else { return }
        updateElapsed()
        let number = recordingMarkers.count + 1
        recordingMarkers.append(ProjectTimelineMarker(
            id: "flag-\(number)",
            kind: .presenterNote,
            timeSeconds: elapsedSeconds,
            title: "Flag \(number)",
            notes: "Marked during recording."
        ))
        recordingMarkerCount = recordingMarkers.count
        message = "Flag \(number) added at \(formattedElapsed)."
        publishStatus()
    }

    func confirmRestartRecording() {
        guard isRecording, !isStopping else { return }
        let alert = NSAlert()
        alert.messageText = "Restart this recording?"
        alert.informativeText = "The current recording will stop and be deleted, then a new recording will start with the same controls."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        restartAfterStop = true
        deleteAfterStop = true
        stopRecording()
    }

    func confirmDiscardRecording() {
        guard isRecording, !isStopping else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this recording?"
        alert.informativeText = "The current recording will stop and the project bundle created for it will be deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        deleteAfterStop = true
        stopRecording()
    }

    func openCompletionInEditor() {
        guard let completion else { return }
        openProjectInEditor(completion.projectURL, projectName: completion.projectName)
    }

    func openLastProjectInEditor() {
        guard let lastProjectPath else { return }
        let projectURL = URL(fileURLWithPath: lastProjectPath)
        openProjectInEditor(projectURL, projectName: projectURL.lastPathComponent)
    }

    private func openProjectInEditor(_ projectURL: URL, projectName: String, updateMessage: Bool = true) {
        if let openProjectHandler {
            openProjectHandler(projectURL)
        } else {
            ProjectOpenRouter.shared.publish(projectURL)
        }
        NSApplication.shared.activate()
        if updateMessage {
            message = "Opened \(projectName) in the editor."
        }
    }

    func revealCompletion() {
        guard let completion else { return }
        NSWorkspace.shared.activateFileViewerSelecting([completion.projectURL])
        message = "Revealed \(completion.projectName)."
    }

    func copyCompletionPath() {
        guard let completion else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(completion.projectURL.path, forType: .string)
        message = "Copied recording path."
    }

    func packageCompletionForLearnHouse(_ preferences: LessonMeldPreferences) {
        guard let completion, !isPackagingCompletion else { return }
        isPackagingCompletion = true
        message = "Packaging \(completion.projectName) for LearnHouse..."
        let projectURL = completion.projectURL
        let shouldArchive = preferences.export.createArchiveByDefault

        Task.detached(priority: .userInitiated) {
            do {
                let outputDirectory = projectURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("LearnHouse Exports", isDirectory: true)
                let result = try LearnHousePackageBuilder().buildPackage(
                    projectURL: projectURL,
                    outputDirectory: outputDirectory,
                    archive: shouldArchive
                )
                await MainActor.run {
                    self.isPackagingCompletion = false
                    let revealPath = result.archivePath ?? result.packagePath
                    self.message = "Packaged LearnHouse export."
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: revealPath)])
                }
            } catch {
                await MainActor.run {
                    self.isPackagingCompletion = false
                    self.message = error.localizedDescription
                }
            }
        }
    }

    func saveCompletionVideo(_ preferences: LessonMeldPreferences) {
        guard let completion, !isRenderingCompletion else { return }
        isRenderingCompletion = true
        completionRenderProgress = 0
        message = "Rendering \(completion.projectName) to video..."
        let projectURL = completion.projectURL

        Task {
            do {
                let outputURL = try await Self.renderCompletionVideo(
                    projectURL: projectURL,
                    preferences: preferences
                ) { [weak self] progress in
                    self?.completionRenderProgress = min(max(progress, 0), 1)
                }
                await MainActor.run {
                    self.isRenderingCompletion = false
                    self.completionRenderProgress = 1
                    self.message = "Saved video \(outputURL.lastPathComponent)."
                    if preferences.export.revealExportAfterCompletion {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    }
                }
            } catch {
                await MainActor.run {
                    self.isRenderingCompletion = false
                    self.message = error.localizedDescription
                }
            }
        }
    }

    private func finishRecording(
        projectURL: URL,
        screenSize: CGSize,
        recordTarget: QuickRecordTarget,
        warnings: [String]
    ) {
        applyLifecycleSnapshot(lifecycle.finish())
        let shouldDelete = deleteAfterStop
        let shouldRestart = restartAfterStop
        let markers = recordingMarkers
        let restartPreferences = lastStartPreferences
        cleanupRecordingState()

        if shouldDelete {
            try? FileManager.default.removeItem(at: projectURL)
            lastProjectPath = nil
            message = shouldRestart ? "Restarting recording..." : "Recording deleted."
        } else {
            persistMarkers(markers, to: projectURL)
            lastProjectPath = projectURL.path
            let savedCompletion = QuickRecordingCompletion(projectURL: projectURL)
            completion = savedCompletion
            openProjectInEditor(savedCompletion.projectURL, projectName: savedCompletion.projectName, updateMessage: false)
            if warnings.isEmpty {
                message = "Ready to review \(savedCompletion.projectName) in the editor."
            } else {
                message = "Ready to review \(savedCompletion.projectName). \(warnings.joined(separator: " "))"
            }
        }

        if shouldRestart, let restartPreferences {
            Task { @MainActor in
                self.startRecording(restartPreferences)
            }
        }
        publishStatus()
    }

    private func failRecording(_ error: Error) {
        applyLifecycleSnapshot(lifecycle.fail())
        cleanupRecordingState()
        if let quickRecorderError = error as? QuickRecorderError,
           let preservedPath = quickRecorderError.preservedProjectPath {
            lastProjectPath = preservedPath
            completion = QuickRecordingCompletion(projectURL: URL(fileURLWithPath: preservedPath))
        }
        message = error.localizedDescription
        publishStatus()
    }

    private func cleanupRecordingState() {
        applyLifecycleSnapshot(lifecycle.reset())
        recordingRuntime.clear()
        cameraPreviewSession = nil
        closeFloatingWebcamPreviewWindow()
        recordingMarkers = []
        recordingMarkerCount = 0
        deleteAfterStop = false
        restartAfterStop = false
        stopElapsedTimer()
        publishStatus()
    }

    private func persistMarkers(_ markers: [ProjectTimelineMarker], to projectURL: URL) {
        guard !markers.isEmpty else { return }
        _ = try? ProjectBundle.updateManifest(at: projectURL) { manifest in
            manifest.markers.append(contentsOf: markers)
        }
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
        updateElapsed()
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateElapsed() {
        elapsedSeconds = lifecycle.elapsed()
        let wholeSecond = Int(elapsedSeconds.rounded(.down))
        if wholeSecond != lastPublishedStatusSecond {
            lastPublishedStatusSecond = wholeSecond
            publishStatus()
        }
    }

    private func applyLifecycleSnapshot(_ snapshot: RecordingLifecycleSnapshot) {
        isRecording = snapshot.isRecording
        isPaused = snapshot.isPaused
        isStopping = snapshot.isStopping
        elapsedSeconds = snapshot.elapsedSeconds
    }

    func publishStatus() {
        let status = LocalAppControlStatus(
            isRecording: isRecording,
            isPaused: isPaused,
            isStopping: isStopping,
            elapsedSeconds: elapsedSeconds,
            lastProjectPath: lastProjectPath,
            message: message
        )
        try? LocalAppControl.writeStatus(status)
    }

    private func syncFloatingWebcamPreviewWindow() {
        guard isRecording, captureWebcam, showFloatingWebcamPreview else {
            closeFloatingWebcamPreviewWindow()
            return
        }

        if let floatingWebcamPreviewWindow {
            floatingWebcamPreviewWindow.updateSize(floatingWebcamPreviewSize)
            floatingWebcamPreviewWindow.setHiddenFromCapture(hideRecorderControlsFromCapture)
            floatingWebcamPreviewWindow.orderFrontRegardless()
            return
        }

        let window = FloatingWebcamPreviewWindow(model: self) { [weak self] in
            self?.floatingWebcamPreviewWindow = nil
        }
        floatingWebcamPreviewWindow = window
        window.setHiddenFromCapture(hideRecorderControlsFromCapture)
        window.orderFrontRegardless()
    }

    private func closeFloatingWebcamPreviewWindow() {
        floatingWebcamPreviewWindow?.closeForRelease()
        floatingWebcamPreviewWindow = nil
    }

    private var enabledTrackLabels: String {
        var labels = [recordTarget.displayName.lowercased()]
        if captureMicrophone {
            labels.append("microphone")
        }
        if captureWebcam {
            labels.append("webcam")
        }
        if captureSystemAudio {
            labels.append("system audio")
        }
        return labels.joined(separator: ", ")
    }

    private func makeSourceRect() throws -> CGRect? {
        switch recordTarget {
        case .screen, .window:
            return nil
        case .region:
            return CGRect(
                x: try parseRegionValue(recordRegionX, label: "Region X"),
                y: try parseRegionValue(recordRegionY, label: "Region Y"),
                width: try parseRegionValue(recordRegionWidth, label: "Region width"),
                height: try parseRegionValue(recordRegionHeight, label: "Region height")
            )
        }
    }

    private func makeWindowID() throws -> UInt32? {
        switch recordTarget {
        case .screen, .region:
            return nil
        case .window:
            guard let id = UInt32(recordWindowID.trimmingCharacters(in: .whitespacesAndNewlines)), id > 0 else {
                throw QuickRecorderError.invalidNumber("Window ID must be a positive integer.")
            }
            return id
        }
    }

    private func parseRegionValue(_ value: String, label: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), number >= 0 else {
            throw QuickRecorderError.invalidNumber("\(label) must be a non-negative number.")
        }
        return number
    }

    private static func recordProject(
        preferences: LessonMeldPreferences,
        duration: TimeInterval,
        displayID: CGDirectDisplayID?,
        sourceRect: CGRect?,
        windowID: UInt32?,
        recordTarget: QuickRecordTarget,
        captureMicrophone: Bool,
        captureWebcam: Bool,
        captureSystemAudio: Bool,
        microphoneDeviceID: String?,
        cameraDeviceID: String?,
        displayRecorder: DisplayScreenRecorder,
        microphoneRecorder: MicrophoneRecorder?,
        cameraRecorder: CameraRecorder?,
        taskRegistry: QuickRecordingTaskRegistry
    ) async throws -> ProjectRecordingResult {
        let projectURL = try makeProjectURL(preferences: preferences)
        let microphoneURL = projectURL.appendingPathComponent("microphone.m4a")
        let webcamURL = projectURL.appendingPathComponent("webcam.mov")
        let screenURL = projectURL.appendingPathComponent("screen.mp4")
        var warnings: [String] = []
        var screenTask: Task<RecordingResult, Error>?
        var microphoneTask: Task<AudioRecordingResult, Error>?
        var webcamTask: Task<CameraRecordingResult, Error>?

        do {
            try ProjectBundle.writeManifest(
                ProjectManifest(
                    metadata: LessonMetadata(lessonTitle: projectURL.deletingPathExtension().lastPathComponent),
                    capture: projectCaptureSettings(
                        preferences: preferences,
                        displayID: displayID,
                        sourceRect: sourceRect,
                        windowID: windowID,
                        recordTarget: recordTarget,
                        captureMicrophone: captureMicrophone,
                        captureWebcam: captureWebcam,
                        captureSystemAudio: captureSystemAudio,
                        microphoneDeviceID: microphoneDeviceID,
                        cameraDeviceID: cameraDeviceID
                    ),
                    exportPresets: ["learnhouse-1080p"]
                ),
                to: projectURL
            )

            let screenStartSignal = ScreenStartSignal()
            let captureRequestedAt = Date()
            displayRecorder.setFirstFrameHandler {
                screenStartSignal.signal()
            }

            screenTask = Task {
                defer {
                    displayRecorder.setFirstFrameHandler(nil)
                }
                return try await displayRecorder.record(
                    DisplayRecordingRequest(
                        displayID: displayID,
                        outputURL: screenURL,
                        durationSeconds: duration,
                        options: RecordingOptions(
                            fps: preferences.capture.fps,
                            timerDelaySeconds: preferences.capture.countdownSeconds,
                            captureSystemAudio: captureSystemAudio,
                            includeCursor: preferences.capture.includeCursor
                        ),
                        sourceRect: sourceRect,
                        windowID: windowID
                    )
                )
            }

            await screenStartSignal.wait(timeout: min(5, max(1, duration / 2)))
            try Task.checkCancellation()
            let remainingDuration = max(0.5, duration - Date().timeIntervalSince(captureRequestedAt))

            microphoneTask = if captureMicrophone, let microphoneRecorder {
                Task {
                    try await recordMicrophoneFile(
                        recorder: microphoneRecorder,
                        outputURL: microphoneURL,
                        duration: remainingDuration,
                        deviceID: microphoneDeviceID
                    )
                }
            } else {
                nil
            }

            webcamTask = if captureWebcam, let cameraRecorder {
                Task {
                    try await cameraRecorder.record(
                        CameraRecordingRequest(
                            outputURL: webcamURL,
                            durationSeconds: remainingDuration,
                            deviceID: cameraDeviceID,
                            resolution: preferences.capture.cameraResolution.rawValue,
                            fps: preferences.capture.webcamFPS
                        )
                    )
                }
            } else {
                nil
            }
            taskRegistry.setTrackTasks(
                screenTask: screenTask,
                microphoneTask: microphoneTask,
                webcamTask: webcamTask
            )

            let screenResult = try await screenTask!.value
            if Task.isCancelled {
                microphoneTask?.cancel()
                webcamTask?.cancel()
            }
            let microphoneResult: AudioRecordingResult?
            do {
                microphoneResult = try await microphoneTask?.value
            } catch {
                warnings.append("Microphone capture failed: \(error.localizedDescription)")
                microphoneResult = nil
            }

            let webcamResult: CameraRecordingResult?
            do {
                webcamResult = try await webcamTask?.value
            } catch {
                warnings.append("Webcam capture failed: \(error.localizedDescription)")
                webcamResult = nil
            }

            let manifest = ProjectManifest(
                metadata: LessonMetadata(lessonTitle: projectURL.deletingPathExtension().lastPathComponent),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                    webcam: webcamResult.map { _ in
                        ProjectFile(relativePath: "webcam.mov", role: .webcamVideo, mimeType: "video/quicktime")
                    },
                    microphoneAudio: microphoneResult.map { _ in
                        ProjectFile(relativePath: "microphone.m4a", role: .microphoneAudio, mimeType: "audio/mp4")
                    }
                ),
                capture: projectCaptureSettings(
                    preferences: preferences,
                    displayID: displayID,
                    sourceRect: sourceRect,
                    windowID: windowID,
                    recordTarget: recordTarget,
                    captureMicrophone: captureMicrophone,
                    captureWebcam: captureWebcam,
                    captureSystemAudio: captureSystemAudio,
                    microphoneDeviceID: microphoneDeviceID,
                    cameraDeviceID: cameraDeviceID
                ),
                tracks: projectTracks(
                    hasWebcam: webcamResult != nil,
                    hasMicrophone: microphoneResult != nil,
                    hasSystemAudio: screenResult.systemAudioURL != nil
                ),
                exportPresets: ["learnhouse-1080p"]
            )
            try ProjectBundle.writeManifest(manifest, to: projectURL)
            return ProjectRecordingResult(
                projectURL: projectURL,
                manifest: manifest,
                screen: screenResult,
                microphone: microphoneResult,
                webcam: webcamResult,
                warnings: warnings
            )
        } catch {
            screenTask?.cancel()
            microphoneTask?.cancel()
            webcamTask?.cancel()
            if hasRecoverableRecordingFiles(in: projectURL) {
                _ = try? ProjectBundle.repair(
                    at: projectURL,
                    lessonTitle: projectURL.deletingPathExtension().lastPathComponent
                )
                throw QuickRecorderError.recordingFailedButProjectPreserved(
                    message: error.localizedDescription,
                    projectPath: projectURL.path
                )
            }
            try? FileManager.default.removeItem(at: projectURL)
            throw error
        }
    }

    private static func projectCaptureSettings(
        preferences: LessonMeldPreferences,
        displayID: CGDirectDisplayID?,
        sourceRect: CGRect?,
        windowID: UInt32?,
        recordTarget: QuickRecordTarget,
        captureMicrophone: Bool,
        captureWebcam: Bool,
        captureSystemAudio: Bool,
        microphoneDeviceID: String?,
        cameraDeviceID: String?
    ) -> ProjectCaptureSettings {
        ProjectCaptureSettings(
            target: ProjectCaptureTarget(quickRecordTarget: recordTarget),
            displayID: displayID,
            windowID: windowID,
            region: sourceRect.map(ProjectCaptureRegion.init),
            screenFPS: preferences.capture.fps,
            includeCursor: preferences.capture.includeCursor,
            captureInteractionMetadata: preferences.capture.captureInteractionMetadata,
            captureMicrophone: captureMicrophone,
            microphoneDeviceID: microphoneDeviceID,
            captureWebcam: captureWebcam,
            captureSystemAudio: captureSystemAudio,
            webcam: ProjectWebcamCaptureSettings(
                cameraID: cameraDeviceID,
                resolution: preferences.capture.cameraResolution,
                fps: preferences.capture.webcamFPS,
                aspectRatio: preferences.capture.webcamAspectRatio,
                frameShape: preferences.capture.webcamFrameShape,
                cornerRadius: preferences.capture.webcamCornerRadius,
                relativeSize: preferences.capture.webcamRelativeSize,
                isMirrored: preferences.capture.webcamMirror,
                borderEnabled: preferences.capture.webcamBorderEnabled,
                shadowEnabled: preferences.capture.webcamShadowEnabled
            )
        )
    }

    private static func hasRecoverableRecordingFiles(in projectURL: URL) -> Bool {
        ["screen.mp4", "webcam.mov", "microphone.m4a", "cursor-metadata.json"].contains { relativePath in
            FileManager.default.fileExists(atPath: projectURL.appendingPathComponent(relativePath).path)
        }
    }

    private static func makeProjectURL(preferences: LessonMeldPreferences) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        let root = expandedPath(preferences.general.defaultProjectDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let baseName = "lesson-\(formatter.string(from: Date()))"
        for attempt in 0..<20 {
            let suffix = attempt == 0 ? "" : "-\(String(UUID().uuidString.prefix(8)).lowercased())"
            let projectURL = root.appendingPathComponent("\(baseName)\(suffix).dmlm", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: false)
                return projectURL
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }

        let fallback = root.appendingPathComponent("\(baseName)-\(UUID().uuidString.lowercased()).dmlm", isDirectory: true)
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: false)
        return fallback
    }

    private static func runCountdown(
        seconds: Int,
        update: @escaping @Sendable (Int) async -> Void
    ) async throws {
        guard seconds > 0 else { return }
        for remaining in stride(from: seconds, through: 1, by: -1) {
            try Task.checkCancellation()
            await update(remaining)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private static func persistInteractionMetadata(
        _ document: InteractionMetadataDocument,
        to projectURL: URL,
        manifest: inout ProjectManifest
    ) throws {
        guard !document.cursorSamples.isEmpty || !document.clicks.isEmpty || !document.keystrokes.isEmpty else {
            return
        }

        let relativePath = "cursor-metadata.json"
        let fileURL = projectURL.appendingPathComponent(relativePath)
        let data = try DMLessonJSON.encoder().encode(document)
        try data.write(to: fileURL, options: .atomic)

        manifest.media.cursorMetadata = ProjectFile(
            relativePath: relativePath,
            role: .cursorMetadata,
            mimeType: "application/json",
            byteCount: Int64(data.count)
        )
        if !manifest.tracks.contains(where: { $0.kind == .cursor }) {
            manifest.tracks.append(TimelineTrack(id: "cursor", kind: .cursor, displayName: "Cursor and Input"))
        }
        try ProjectBundle.writeManifest(manifest, to: projectURL)
    }

    private static func interactionMetadataCaptureRect(
        target: QuickRecordTarget,
        displayID: CGDirectDisplayID?,
        sourceRect: CGRect?,
        windowID: UInt32?
    ) -> CGRect {
        switch target {
        case .screen:
            return displayFrame(for: displayID)
        case .region:
            let displayFrame = displayFrame(for: displayID)
            guard let sourceRect else { return displayFrame }
            return CGRect(
                x: displayFrame.minX + sourceRect.minX,
                y: displayFrame.minY + sourceRect.minY,
                width: sourceRect.width,
                height: sourceRect.height
            ).standardized
        case .window:
            return windowFrame(for: windowID) ?? displayFrame(for: displayID)
        }
    }

    private static func displayFrame(for displayID: CGDirectDisplayID?) -> CGRect {
        screen(for: displayID)?.frame.standardized
            ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private static func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        if let displayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private static func windowFrame(for windowID: UInt32?) -> CGRect? {
        guard let windowID else { return nil }
        let options = CGWindowListOption(arrayLiteral: .optionIncludingWindow)
        guard let windows = CGWindowListCopyWindowInfo(options, CGWindowID(windowID)) as? [[String: Any]],
              let info = windows.first,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Double,
              let y = bounds["Y"] as? Double,
              let width = bounds["Width"] as? Double,
              let height = bounds["Height"] as? Double,
              width > 0,
              height > 0 else {
            return nil
        }

        let topLeftRect = CGRect(x: x, y: y, width: width, height: height)
        let desktopFrame = NSScreen.screens.reduce(CGRect.null) { partial, screen in
            partial.union(screen.frame)
        }
        guard !desktopFrame.isNull else {
            return topLeftRect.standardized
        }
        return CGRect(
            x: topLeftRect.minX,
            y: desktopFrame.maxY - topLeftRect.maxY,
            width: topLeftRect.width,
            height: topLeftRect.height
        ).standardized
    }

    private static func recordMicrophoneFile(
        recorder: MicrophoneRecorder,
        outputURL: URL,
        duration: TimeInterval,
        deviceID: String?
    ) async throws -> AudioRecordingResult {
        let options = AudioRecordingOptions(fileFormat: .m4a, sampleFormat: .aac)
        try recorder.startRecording(AudioRecordingRequest(
            source: .microphone(deviceID: deviceID),
            outputURL: outputURL,
            options: options
        ))

        do {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            return try recorder.stopRecording()
        } catch is CancellationError {
            return try recorder.stopRecording()
        } catch {
            _ = try? recorder.stopRecording()
            throw error
        }
    }

    private static func projectTracks(hasWebcam: Bool, hasMicrophone: Bool, hasSystemAudio: Bool) -> [TimelineTrack] {
        var tracks = [
            TimelineTrack(id: "screen", kind: .screen, displayName: "Screen")
        ]
        if hasWebcam {
            tracks.append(TimelineTrack(id: "webcam", kind: .webcam, displayName: "Webcam"))
        }
        if hasMicrophone {
            tracks.append(TimelineTrack(id: "microphone", kind: .microphone, displayName: "Microphone"))
        }
        if hasSystemAudio {
            tracks.append(TimelineTrack(id: "system-audio", kind: .systemAudio, displayName: "System Audio"))
        }
        return tracks
    }

    private static func formatClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 {
            return "\(seconds)s"
        }
        if remainder == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(remainder)s"
    }

    private static func expandedPath(_ path: String) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private static func renderCompletionVideo(
        projectURL: URL,
        preferences: LessonMeldPreferences,
        progress: RenderProgressHandler?
    ) async throws -> URL {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let editDecisionList = EditDecisionListFile.exists(in: projectURL)
            ? try EditDecisionListFile.load(fromProject: projectURL)
            : nil
        let destinationURL = try uniqueRenderDestination(
            projectURL: projectURL,
            lessonTitle: manifest.metadata.lessonTitle,
            fileType: preferences.export.defaultFileType
        )
        var plan = try RenderPlan.make(
            manifest: manifest,
            projectURL: projectURL,
            destinationURL: destinationURL,
            preset: renderPreset(from: preferences.export),
            editDecisionList: editDecisionList
        )
        if plan.webcamOverlay != nil {
            let manifest = try ProjectBundle.loadManifest(at: projectURL)
            if manifest.capture == nil {
                plan.webcamOverlay?.placement = webcamPlacement(from: preferences.capture)
            }
        }
        return try await AVFoundationRenderService().export(plan: plan, progress: progress)
    }

    private static func renderPreset(from preferences: ExportPreferences) -> RenderPreset {
        RenderPreset(
            fileType: RenderFileType(rawValue: preferences.defaultFileType.rawValue) ?? .mp4,
            quality: RenderQuality(rawValue: preferences.defaultRenderQuality.rawValue) ?? .highest
        )
    }

    private static func webcamPlacement(from capture: CapturePreferences) -> PictureInPicturePlacement {
        PictureInPicturePlacement(
            corner: .bottomTrailing,
            widthRatio: capture.webcamRelativeSize,
            marginRatio: 0.04,
            aspectRatio: PictureInPictureAspectRatio(rawValue: capture.webcamAspectRatio.rawValue) ?? .widescreen16x9,
            frameShape: PictureInPictureFrameShape(rawValue: capture.webcamFrameShape.rawValue) ?? .roundedRectangle,
            cornerRadius: capture.webcamCornerRadius,
            isMirrored: capture.webcamMirror,
            borderEnabled: capture.webcamBorderEnabled,
            shadowEnabled: capture.webcamShadowEnabled
        )
    }

    private static func uniqueRenderDestination(
        projectURL: URL,
        lessonTitle: String,
        fileType: RenderFileTypeID
    ) throws -> URL {
        let exportDirectory = projectURL.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let baseName = slug(lessonTitle.isEmpty ? projectURL.deletingPathExtension().lastPathComponent : lessonTitle)
        let fileExtension = fileType.rawValue
        var candidate = exportDirectory.appendingPathComponent("\(baseName).\(fileExtension)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = exportDirectory.appendingPathComponent("\(baseName)-\(index).\(fileExtension)")
            index += 1
        }
        return candidate
    }

    private static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "lesson" : collapsed
    }

    private static func formatRegionValue(_ value: CGFloat) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.001 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", Double(value))
    }

    private static func availableWindowChoices() -> [QuickWindowChoice] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windows.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? UInt32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                return nil
            }

            let owner = (info[kCGWindowOwnerName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown App"
            let name = (info[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !owner.isEmpty else { return nil }

            let title = name.isEmpty ? owner : name
            let bounds = info[kCGWindowBounds as String] as? [String: Any]
            let width = (bounds?["Width"] as? Double).map(Int.init) ?? 0
            let height = (bounds?["Height"] as? Double).map(Int.init) ?? 0
            let sizeLabel = width > 0 && height > 0 ? " - \(width)x\(height)" : ""
            return QuickWindowChoice(
                id: id,
                title: title,
                detail: "\(owner)\(sizeLabel)"
            )
        }
    }

    private static let readyMessage = "Open the recording controls to choose screen, window, region, microphone, webcam, and system audio before recording."
    private static let manualStopDurationSeconds = 12 * 60 * 60
}

@MainActor
private final class QuickRecordingRuntime {
    let taskRegistry = QuickRecordingTaskRegistry()
    var interactionMetadataCapture: InteractionMetadataCaptureSession?

    private var displayRecorder: DisplayScreenRecorder?
    private var microphoneRecorder: MicrophoneRecorder?
    private var cameraRecorder: CameraRecorder?

    func configure(
        displayRecorder: DisplayScreenRecorder,
        microphoneRecorder: MicrophoneRecorder?,
        cameraRecorder: CameraRecorder?
    ) {
        self.displayRecorder = displayRecorder
        self.microphoneRecorder = microphoneRecorder
        self.cameraRecorder = cameraRecorder
        taskRegistry.configure(cameraRecorder: cameraRecorder)
    }

    func setRecordingTask(_ task: Task<Void, Never>) {
        taskRegistry.setRecordingTask(task)
    }

    func pause() {
        displayRecorder?.pauseRecording()
        microphoneRecorder?.pauseRecording()
        cameraRecorder?.pauseRecording()
        interactionMetadataCapture?.pause()
    }

    func resume() {
        displayRecorder?.resumeRecording()
        microphoneRecorder?.resumeRecording()
        cameraRecorder?.resumeRecording()
        interactionMetadataCapture?.resume()
    }

    func requestStop() {
        taskRegistry.requestStop()
    }

    func clear() {
        taskRegistry.clear()
        displayRecorder = nil
        microphoneRecorder = nil
        cameraRecorder = nil
        interactionMetadataCapture = nil
    }
}

private final class QuickRecordingTaskRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var recordingTask: Task<Void, Never>?
    private var screenTask: Task<RecordingResult, Error>?
    private var microphoneTask: Task<AudioRecordingResult, Error>?
    private var webcamTask: Task<CameraRecordingResult, Error>?
    private var cameraRecorder: CameraRecorder?

    func configure(cameraRecorder: CameraRecorder?) {
        lock.lock()
        screenTask = nil
        microphoneTask = nil
        webcamTask = nil
        self.cameraRecorder = cameraRecorder
        lock.unlock()
    }

    func setRecordingTask(_ task: Task<Void, Never>) {
        lock.lock()
        recordingTask = task
        lock.unlock()
    }

    func setTrackTasks(
        screenTask: Task<RecordingResult, Error>?,
        microphoneTask: Task<AudioRecordingResult, Error>?,
        webcamTask: Task<CameraRecordingResult, Error>?
    ) {
        lock.lock()
        self.screenTask = screenTask
        self.microphoneTask = microphoneTask
        self.webcamTask = webcamTask
        lock.unlock()
    }

    func requestStop() {
        let snapshot = snapshot()
        if snapshot.hasTrackTasks {
            snapshot.screenTask?.cancel()
            snapshot.microphoneTask?.cancel()
            snapshot.webcamTask?.cancel()
            snapshot.cameraRecorder?.stopRecording()
        } else {
            snapshot.recordingTask?.cancel()
            snapshot.cameraRecorder?.stopRecording()
        }
    }

    func clear() {
        lock.lock()
        recordingTask = nil
        screenTask = nil
        microphoneTask = nil
        webcamTask = nil
        cameraRecorder = nil
        lock.unlock()
    }

    private func snapshot() -> TaskSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return TaskSnapshot(
            recordingTask: recordingTask,
            screenTask: screenTask,
            microphoneTask: microphoneTask,
            webcamTask: webcamTask,
            cameraRecorder: cameraRecorder
        )
    }

    private struct TaskSnapshot {
        var recordingTask: Task<Void, Never>?
        var screenTask: Task<RecordingResult, Error>?
        var microphoneTask: Task<AudioRecordingResult, Error>?
        var webcamTask: Task<CameraRecordingResult, Error>?
        var cameraRecorder: CameraRecorder?

        var hasTrackTasks: Bool {
            screenTask != nil || microphoneTask != nil || webcamTask != nil
        }
    }
}

struct QuickRecordingCompletion: Equatable {
    var projectURL: URL

    var projectName: String {
        projectURL.lastPathComponent
    }
}

private struct ProjectRecordingResult {
    var projectURL: URL
    var manifest: ProjectManifest
    var screen: RecordingResult
    var microphone: AudioRecordingResult?
    var webcam: CameraRecordingResult?
    var warnings: [String] = []
}

private final class ScreenStartSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var didStart = false

    func signal() {
        lock.lock()
        didStart = true
        lock.unlock()
    }

    func wait(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !Task.isCancelled, !isStarted, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private var isStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didStart
    }
}

private final class QuickRecordingControlBarWindow: NSPanel, NSWindowDelegate {
    private var onClose: () -> Void

    init<Content: View>(rootView: Content, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        animationBehavior = .none
        isReleasedWhenClosed = false
        level = .screenSaver
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        sharingType = .none
        delegate = self

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        contentView = hostingView

        let size = Self.clampedSize(hostingView.fittingSize)
        setFrame(Self.clampedFrame(origin: Self.defaultOrigin(for: size), size: size), display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func refitToContent() {
        guard let contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        refit(size: contentView.fittingSize)
    }

    func setHiddenFromCapture(_ isHidden: Bool) {
        sharingType = isHidden ? .none : .readOnly
    }

    func windowWillClose(_ notification: Notification) {
        contentView = nil
        onClose()
    }

    private static func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.visibleFrame
        return NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 112
        )
    }

    private static func clampedSize(_ size: NSSize) -> NSSize {
        guard let screen = NSScreen.main else { return size }
        let frame = screen.visibleFrame
        return NSSize(
            width: min(max(size.width, 240), max(frame.width - 48, 240)),
            height: min(max(size.height, ControlBarPalette.itemHeight + ControlBarPalette.outerPadding * 2), max(frame.height - 48, 80))
        )
    }

    private static func clampedFrame(origin: NSPoint, size: NSSize) -> NSRect {
        guard let screen = NSScreen.main else { return NSRect(origin: origin, size: size) }
        let visible = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        let y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func refit(size: NSSize) {
        let nextSize = Self.clampedSize(size)
        guard nextSize.width > 0, nextSize.height > 0 else { return }
        let currentFrame = frame
        let origin = currentFrame.width > 1 && currentFrame.height > 1
            ? NSPoint(x: currentFrame.midX - nextSize.width / 2, y: currentFrame.minY)
            : Self.defaultOrigin(for: nextSize)
        setFrame(Self.clampedFrame(origin: origin, size: nextSize), display: true, animate: false)
        contentView?.frame = NSRect(origin: .zero, size: nextSize)
    }
}

private final class FloatingWebcamPreviewWindow: NSPanel, NSWindowDelegate {
    private var onClose: () -> Void

    init(model: QuickRecorderModel, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let size = model.floatingWebcamPreviewSize
        super.init(
            contentRect: NSRect(origin: Self.defaultOrigin(for: size), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        animationBehavior = .none
        isReleasedWhenClosed = false
        level = .screenSaver
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        sharingType = .none
        delegate = self

        let hostingView = NSHostingView(rootView: FloatingWebcamPreviewPanel(model: model))
        hostingView.sizingOptions = [.intrinsicContentSize]
        contentView = hostingView
        updateSize(size)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateSize(_ size: CGSize) {
        let nextSize = NSSize(width: size.width, height: size.height)
        let currentFrame = frame
        let origin = currentFrame.width > 1 && currentFrame.height > 1
            ? NSPoint(x: currentFrame.maxX - nextSize.width, y: currentFrame.origin.y)
            : Self.defaultOrigin(for: nextSize)
        setFrame(Self.clampedFrame(origin: origin, size: nextSize), display: true)
        contentView?.frame = NSRect(origin: .zero, size: nextSize)
    }

    func setHiddenFromCapture(_ isHidden: Bool) {
        sharingType = isHidden ? .none : .readOnly
    }

    func closeForRelease() {
        delegate = nil
        contentView = nil
        orderOut(nil)
        DispatchQueue.main.async { [weak self] in
            self?.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        contentView = nil
        onClose()
    }

    private static func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.visibleFrame
        return NSPoint(
            x: frame.maxX - size.width - 36,
            y: frame.minY + 120
        )
    }

    private static func clampedFrame(origin: NSPoint, size: NSSize) -> NSRect {
        guard let screen = NSScreen.main else { return NSRect(origin: origin, size: size) }
        let visible = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        let y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

enum QuickRecordTarget: String, CaseIterable, Identifiable {
    case screen
    case window
    case region

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .screen: "Screen"
        case .window: "Window"
        case .region: "Region"
        }
    }

    var iconName: String {
        switch self {
        case .screen: "display"
        case .window: "macwindow"
        case .region: "rectangle.dashed"
        }
    }
}

private extension ProjectCaptureTarget {
    init(quickRecordTarget: QuickRecordTarget) {
        switch quickRecordTarget {
        case .screen:
            self = .screen
        case .window:
            self = .window
        case .region:
            self = .region
        }
    }
}

struct QuickDisplayChoice: Identifiable, Equatable {
    var id: CGDirectDisplayID
    var displayName: String
}

struct QuickMicrophoneChoice: Identifiable, Equatable {
    var id: String
    var name: String
}

struct QuickCameraChoice: Identifiable, Equatable {
    var id: String
    var name: String
}

struct QuickWindowChoice: Identifiable, Equatable {
    var id: UInt32
    var title: String
    var detail: String
}

private enum QuickRecorderError: Error, LocalizedError {
    case invalidNumber(String)
    case recordingFailedButProjectPreserved(message: String, projectPath: String)

    var errorDescription: String? {
        switch self {
        case .invalidNumber(let message):
            message
        case .recordingFailedButProjectPreserved(let message, let projectPath):
            "Recording stopped before completion, but recoverable files were preserved at \(projectPath). \(message)"
        }
    }

    var preservedProjectPath: String? {
        switch self {
        case .recordingFailedButProjectPreserved(_, let projectPath):
            projectPath
        case .invalidNumber:
            nil
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
