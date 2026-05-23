@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import DMLessonMeldCore
import SwiftUI

struct DisplayPopover: View {
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

struct CameraPopover: View {
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

struct MicrophonePopover: View {
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

struct WebcamPreviewCard: View {
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

struct WebcamSetupPreview: View {
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

struct RecordingWebcamPreviewButton: View {
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

struct FloatingWebcamPreviewPanel: View {
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

struct StyledWebcamPreview<Content: View>: View {
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

struct WebcamPreviewPlaceholder: View {
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

struct CameraSessionPreviewView: NSViewRepresentable {
    var sessionBox: CameraPreviewSessionBox

    func makeNSView(context: Context) -> WebcamPreviewLayerView {
        WebcamPreviewLayerView(session: sessionBox.session)
    }

    func updateNSView(_ view: WebcamPreviewLayerView, context: Context) {
        view.setSession(sessionBox.session)
    }
}

final class WebcamPreviewLayerView: NSView {
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

final class WebcamPreviewSessionController: ObservableObject, @unchecked Sendable {
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
        let fps = try NumericInputValidation.captureFPS(fps, label: "Camera FPS")
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

struct WebcamPreviewClipShape: InsettableShape {
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

extension WebcamAspectRatio {
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

struct RegionPopover: View {
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

struct WindowPopover: View {
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
