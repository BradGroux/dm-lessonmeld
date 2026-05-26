import AppKit
import DMLessonMeldCore
import SwiftUI
import UniformTypeIdentifiers

struct LessonMeldSettingsView: View {
    @ObservedObject var appRouter: LessonMeldAppRouter
    @ObservedObject var preferences: AppPreferencesController
    @Environment(\.openWindow) private var openWindow
    @State private var selectedSection: LessonMeldSettingsSection = .capture
    @State private var settingsSearchText = ""
    @State private var draft: LessonMeldPreferences
    @State private var saveMessage = "Saved"
    @State private var presetMessage = ""

    init(appRouter: LessonMeldAppRouter, preferences: AppPreferencesController) {
        self.appRouter = appRouter
        self.preferences = preferences
        _draft = State(initialValue: preferences.snapshot.normalized())
    }

    var body: some View {
        NavigationSplitView {
            settingsSidebar
                .navigationTitle("Settings")
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            contentPane
        }
        .frame(
            minWidth: AppUILayoutSurface.settings.minimumSize.width,
            idealWidth: 920,
            minHeight: AppUILayoutSurface.settings.minimumSize.height,
            idealHeight: 640
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            settingsToolbarItems
        }
        .onAppear {
            refreshDraft()
            applySettingsRequest(appRouter.settingsRequest)
        }
        .onReceive(appRouter.$settingsRequest.compactMap(\.self)) { request in
            applySettingsRequest(request)
        }
    }

    private var hasUnsavedChanges: Bool {
        draft.normalized() != preferences.snapshot.normalized()
    }

    private var activeSection: LessonMeldSettingsSection {
        if visibleSections.contains(selectedSection) {
            return selectedSection
        }
        return visibleSections.first ?? selectedSection
    }

    private var visibleSections: [LessonMeldSettingsSection] {
        LessonMeldSettingsSection.allCases.filter(sectionMatchesSearch)
    }

    private var visibleGroups: [(title: String, sections: [LessonMeldSettingsSection])] {
        ["App", "Recording", "Lesson Defaults", "Community"].compactMap { title in
            let sections = visibleSections.filter { $0.groupTitle == title }
            return sections.isEmpty ? nil : (title, sections)
        }
    }

    private var searchQuery: String {
        settingsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var selectedSectionBinding: Binding<LessonMeldSettingsSection?> {
        Binding(
            get: { activeSection },
            set: { newValue in
                if let newValue {
                    selectedSection = newValue
                }
            }
        )
    }

    @ToolbarContentBuilder
    private var settingsToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Text(hasUnsavedChanges ? "Unsaved changes" : saveMessage)
                .font(.caption)
                .foregroundStyle(hasUnsavedChanges ? .orange : .secondary)

            Button("Revert Section") {
                revertSection(activeSection)
            }
            .disabled(!sectionHasUnsavedChanges(activeSection))

            Button("Revert All") {
                refreshDraft()
            }
            .disabled(!hasUnsavedChanges)

            Button("Reset Defaults...") {
                confirmResetDefaults()
            }

            Button("Save All") {
                preferences.replace(with: draft)
                refreshDraft()
                saveMessage = "Saved"
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!hasUnsavedChanges)
        }
    }

    private var contentPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if visibleSections.isEmpty {
                    ContentUnavailableView("No Settings Found", systemImage: "magnifyingglass", description: Text("Try a different search."))
                } else {
                    sectionView
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingsSidebar: some View {
        List(selection: selectedSectionBinding) {
            if visibleGroups.isEmpty {
                Text("No settings match.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.sections) { section in
                            HStack(spacing: 8) {
                                Label(section.title, systemImage: section.symbolName)
                                Spacer(minLength: 8)
                                if sectionHasUnsavedChanges(section) {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 6, height: 6)
                                        .accessibilityLabel("Unsaved changes")
                                }
                            }
                            .tag(section)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $settingsSearchText, prompt: "Search settings")
        .accessibilityLabel("Settings sections")
    }

    @ViewBuilder private var sectionView: some View {
        switch activeSection {
        case .general:
            generalSection
        case .capture:
            captureSection
        case .camera:
            cameraSection
        case .audio:
            audioSection
        case .transcription:
            transcriptionSection
        case .editor:
            editorSection
        case .annotations:
            annotationsSection
        case .export:
            exportSection
        case .presets:
            presetsSection
        case .community:
            communitySection
        case .privacy:
            privacySection
        case .shortcuts:
            shortcutsSection
        case .diagnostics:
            diagnosticsSection
        }
    }

    private var generalSection: some View {
        SettingsSectionView(title: "General", subtitle: "Default project and template behavior.") {
            Picker("Appearance", selection: binding(\.general.appearance)) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.rawValue.capitalized).tag(appearance)
                }
            }
            TextField("Project folder", text: binding(\.general.defaultProjectDirectory))
            TextField("Default template", text: binding(\.general.defaultTemplateID))
            Toggle("Open main window at launch", isOn: binding(\.general.showMainWindowAtLaunch))
            Toggle("Open annotation overlay at launch", isOn: binding(\.general.showAnnotationOverlayAtLaunch))
            Toggle("Show hover tooltips throughout the app", isOn: binding(\.capture.showRecorderControlTooltips))
        }
    }

    private var captureSection: some View {
        SettingsSectionView(title: "Capture", subtitle: "Screen recording defaults for teaching and workshop sessions.", scope: .futureRecordings) {
            Stepper("Quick record duration: \(formatDuration(draft.capture.quickRecordDurationSeconds))", value: intBinding(\.capture.quickRecordDurationSeconds), in: 1...3_600, step: 30)
            Picker("Screen frame rate", selection: intBinding(\.capture.fps)) {
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
            Toggle("Include cursor", isOn: binding(\.capture.includeCursor))
            Toggle("Capture click and shortcut metadata", isOn: binding(\.capture.captureInteractionMetadata))
            Stepper("Countdown: \(draft.capture.countdownSeconds)s", value: intBinding(\.capture.countdownSeconds), in: 0...10)
            Toggle("Remember last region", isOn: binding(\.capture.rememberLastRegion))
            Toggle("Hide recorder controls from screenshots and recordings", isOn: binding(\.capture.hideRecorderControlsFromCapture))
        }
    }

    private var audioSection: some View {
        SettingsSectionView(title: "Audio", subtitle: "Voice and system-audio defaults for future recordings.", scope: .futureRecordings) {
            Toggle("Capture microphone by default", isOn: binding(\.capture.captureMicrophone))
            Picker("Microphone input", selection: optionalStringBinding(\.capture.microphoneDeviceID)) {
                Text("System Default").tag(String?.none)
                ForEach(MicrophoneCaptureDevices.available, id: \.id) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(!draft.capture.captureMicrophone)
            Toggle("Capture system audio by default", isOn: binding(\.capture.captureSystemAudio))
        }
    }

    private var transcriptionSection: some View {
        let status = TranscriptionModelInspector.status(for: draft.transcription)
        return SettingsSectionView(title: "Transcription", subtitle: "Local model readiness for future transcript generation.", scope: .futureRecordings) {
            Toggle("Enable local transcription workflow", isOn: binding(\.transcription.enabled))
            Picker("Runtime", selection: binding(\.transcription.runtime)) {
                ForEach(TranscriptionRuntime.allCases) { runtime in
                    Text(runtime.displayName).tag(runtime)
                }
            }
            TextField("Model file", text: binding(\.transcription.modelPath))
                .font(.system(.body, design: .monospaced))
            HStack {
                Button("Choose Model...") {
                    chooseTranscriptionModelFile()
                }
                Button("Use Default Path") {
                    draft.transcription.modelPath = TranscriptionPreferences.defaultModelFilePath
                    saveMessage = "Unsaved"
                }
            }
            TextField("Language", text: binding(\.transcription.language))
                .frame(width: 140)
            Toggle("Transcribe after recording", isOn: binding(\.transcription.autoTranscribeAfterRecording))
                .disabled(!draft.transcription.enabled)
            Toggle("Write caption sidecars after transcription", isOn: binding(\.transcription.writeCaptionSidecars))
                .disabled(!draft.transcription.enabled)
            Label(status.message, systemImage: status.isReady ? "checkmark.circle" : (draft.transcription.enabled ? "exclamationmark.triangle" : "pause.circle"))
                .foregroundStyle(status.isReady ? .green : (draft.transcription.enabled ? .orange : .secondary))
            diagnosticsRow("Expanded model path", status.expandedModelPath)
            diagnosticsRow("Recommended model folder", status.recommendedDirectory)
        }
    }

    private var cameraSection: some View {
        SettingsSectionView(title: "Camera", subtitle: "Webcam picture-in-picture defaults for future recordings.", scope: .futureRecordings) {
            Toggle("Capture webcam by default", isOn: binding(\.capture.captureWebcam))
            Picker("Webcam resolution", selection: binding(\.capture.cameraResolution)) {
                ForEach(CameraResolution.allCases) { resolution in
                    Text(resolution.rawValue).tag(resolution)
                }
            }
            Picker("Webcam frame rate", selection: intBinding(\.capture.webcamFPS)) {
                ForEach(CapturePreferences.supportedWebcamFPS, id: \.self) { fps in
                    Text("\(fps) fps").tag(fps)
                }
            }
            Picker("Webcam format", selection: binding(\.capture.webcamAspectRatio)) {
                ForEach(WebcamAspectRatio.allCases) { aspectRatio in
                    Text(aspectRatio.displayName).tag(aspectRatio)
                }
            }
            .disabled(draft.capture.webcamFrameShape == .circle)
            .opacity(draft.capture.webcamFrameShape == .circle ? 0.48 : 1)
            .help(draft.capture.webcamFrameShape == .circle ? "Circle webcam frames always use a 1:1 crop." : "Choose the webcam frame format.")
            Picker("Webcam shape", selection: binding(\.capture.webcamFrameShape)) {
                ForEach(WebcamFrameShape.allCases) { shape in
                    Text(shape.displayName).tag(shape)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Webcam size")
                    Spacer()
                    Text("\(Int((draft.capture.webcamRelativeSize * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: doubleBinding(\.capture.webcamRelativeSize), in: 0.10...0.40)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Corner radius")
                    Spacer()
                    Text("\(Int(draft.capture.webcamCornerRadius.rounded())) px")
                        .foregroundStyle(.secondary)
                }
                Slider(value: doubleBinding(\.capture.webcamCornerRadius), in: 0...64)
                    .disabled(draft.capture.webcamFrameShape == .circle)
            }
            Toggle("Mirror webcam", isOn: binding(\.capture.webcamMirror))
            Toggle("Show webcam border", isOn: binding(\.capture.webcamBorderEnabled))
            Toggle("Show webcam shadow", isOn: binding(\.capture.webcamShadowEnabled))
            Toggle("Show floating webcam preview while recording", isOn: binding(\.capture.showFloatingWebcamPreview))
        }
    }

    private var editorSection: some View {
        SettingsSectionView(title: "Editor", subtitle: "Project editor defaults and active-project boundaries.", scope: .projectLevel) {
            diagnosticsRow("Video edits", "Saved inside each .dmlm project")
            diagnosticsRow("Canvas, cursor, captions, overlays", "Project-level editor settings")
            diagnosticsRow("Reusable looks", "Use Presets from an open project")
            Text("App Settings controls future defaults. Open a lesson project to change edits, canvas styling, overlays, captions, zoom regions, and export decisions for that project.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var annotationsSection: some View {
        SettingsSectionView(title: "Annotations", subtitle: "Shared defaults for the embedded overlay and lesson annotation tools.", scope: .futureDefaults) {
            Picker("Default tool", selection: binding(\.annotation.defaultTool)) {
                ForEach(AnnotationToolID.allCases) { tool in
                    Text(tool.rawValue.capitalized).tag(tool)
                }
            }

            Divider()

            Text("Default Stroke")
                .font(.headline)
            AnnotationColorRow(
                title: "Default color",
                hex: binding(\.annotation.defaultColorHex),
                canMakeDefault: false,
                canRemove: false,
                onMakeDefault: {},
                onRemove: {}
            )
            Stepper("Line width: \(Int(draft.annotation.lineWidth))", value: doubleBinding(\.annotation.lineWidth), in: 1...24)
            Toggle("Show toolbar when overlay opens", isOn: binding(\.annotation.toolbarVisibleOnOverlayOpen))

            Divider()

            HStack {
                Text("Palette")
                    .font(.headline)
                Spacer()
                Button {
                    draft.annotation.paletteHexColors.append("#FFFFFF")
                    saveMessage = "Unsaved"
                } label: {
                    Label("Add Color", systemImage: "plus")
                }
                Button("Reset Palette") {
                    draft.annotation.paletteHexColors = AnnotationPreferences().paletteHexColors
                    saveMessage = "Unsaved"
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(draft.annotation.paletteHexColors.indices), id: \.self) { index in
                    AnnotationColorRow(
                        title: "Color \(index + 1)",
                        hex: paletteColorBinding(index),
                        canMakeDefault: draft.annotation.paletteHexColors[index].normalizedHexString != draft.annotation.defaultColorHex.normalizedHexString,
                        canRemove: draft.annotation.paletteHexColors.count > 1,
                        onMakeDefault: {
                            if let normalized = draft.annotation.paletteHexColors[index].normalizedHexString {
                                draft.annotation.defaultColorHex = normalized
                                saveMessage = "Unsaved"
                            }
                        },
                        onRemove: {
                            if draft.annotation.paletteHexColors.indices.contains(index), draft.annotation.paletteHexColors.count > 1 {
                                draft.annotation.paletteHexColors.remove(at: index)
                                saveMessage = "Unsaved"
                            }
                        }
                    )
                }
            }
        }
    }

    private var exportSection: some View {
        SettingsSectionView(title: "Export", subtitle: "Renderer and LearnHouse package defaults.", scope: .futureDefaults) {
            Picker("Render quality", selection: binding(\.export.defaultRenderQuality)) {
                ForEach(RenderQualityID.allCases) { quality in
                    Text(quality.rawValue.capitalized).tag(quality)
                }
            }
            Picker("File type", selection: binding(\.export.defaultFileType)) {
                ForEach(RenderFileTypeID.allCases) { fileType in
                    Text(fileType.rawValue.uppercased()).tag(fileType)
                }
            }
            Toggle("Build LearnHouse package by default", isOn: binding(\.export.defaultLearnHousePackage))
            Toggle("Create LearnHouse zip archive", isOn: binding(\.export.createArchiveByDefault))
            Toggle("Reveal export after completion", isOn: binding(\.export.revealExportAfterCompletion))
            Toggle("Enable LearnHouse out of the box", isOn: binding(\.integrations.learnHouseEnabled))
            Toggle("Enable agent manifests", isOn: binding(\.integrations.agentManifestsEnabled))
        }
    }

    private var presetsSection: some View {
        SettingsSectionView(title: "Presets", subtitle: "Share reusable capture, annotation, and export defaults as local preset files.", scope: .futureDefaults) {
            HStack {
                Button {
                    exportSettingsPreset()
                } label: {
                    Label("Export Settings Preset...", systemImage: "square.and.arrow.up")
                }
                Button {
                    importSettingsPreset()
                } label: {
                    Label("Import Settings Preset...", systemImage: "square.and.arrow.down")
                }
            }
            if !presetMessage.isEmpty {
                Text(presetMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("Included")
                .font(.headline)
            diagnosticsRow("Capture", "Screen, mic, webcam, cursor, countdown defaults")
            diagnosticsRow("Annotations", "Default tool, colors, line width, palette")
            diagnosticsRow("Export", "Render quality, file type, LearnHouse packaging defaults")

            Divider()

            Text("Project styles")
                .font(.headline)
            Text("Open a lesson project and use the editor Presets tab to include canvas, cursor, camera, audio, caption, overlay, and export preset IDs.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var communitySection: some View {
        SettingsSectionView(title: "Community", subtitle: "Start Small, Think Big links for courses, episodes, and live discussion.") {
            CommunityLinkButton(
                title: "SSTB.ai",
                subtitle: "Community and learning platform for practical AI education.",
                systemImage: "globe",
                url: CommunityLinks.sstb
            )

            CommunityLinkButton(
                title: "SSTB Podcast Playlist",
                subtitle: "Start Small, Think Big episodes on YouTube.",
                systemImage: "play.rectangle",
                url: CommunityLinks.podcastPlaylist
            )

            CommunityLinkButton(
                title: "SSTB Discord",
                subtitle: "Join the community for agents, automation, and shipping useful things.",
                systemImage: "bubble.left.and.bubble.right",
                url: CommunityLinks.discord
            )
        }
    }

    private var privacySection: some View {
        SettingsSectionView(title: "Privacy", subtitle: "Local-only defaults and Git-safe backup posture.") {
            Toggle("Local-only mode", isOn: binding(\.privacy.localOnlyMode))
            Toggle("Allow Git backups for non-sensitive settings/templates", isOn: binding(\.privacy.allowGitBackupsForSettings))
            TextField("Config backup root", text: binding(\.privacy.configBackupRootPath))
            Toggle("Exclude media from backups", isOn: binding(\.privacy.excludeMediaFromBackups))
            Toggle("Include media paths in agent manifests", isOn: binding(\.privacy.includeMediaPathsInAgentManifests))
            Toggle("Include transcript references in agent manifests", isOn: binding(\.privacy.includeTranscriptReferencesInAgentManifests))
            ConfigBackupSettingsPanel(preferences: preferences)
        }
    }

    private var shortcutsSection: some View {
        SettingsSectionView(title: "Shortcuts", subtitle: "Stored shortcut preferences for menu commands, command palette actions, and future global handlers.") {
            ForEach(LessonMeldShortcutAction.allCases) { action in
                HStack {
                    Text(action.displayName)
                        .frame(width: 190, alignment: .leading)
                    TextField("Shortcut", text: shortcutBinding(action))
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("Current handlers use native menu shortcuts where available; persisted values give the global shortcut controller a stable source of truth.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var diagnosticsSection: some View {
        let diagnostics = AppDiagnostics.current
        let preflight = PermissionPreflight.onboarding(preferences: draft)
        return SettingsSectionView(title: "Diagnostics", subtitle: "Current launch state and macOS permission health.") {
            diagnosticsRow("Onboarding", preferences.snapshot.onboardingCompleted ? "Completed" : "Pending")
            diagnosticsRow("Previous exit", preferences.previousExitWasClean ? "Clean" : "Recovered after abnormal exit")
            diagnosticsRow("Safe mode", preferences.launchDiagnostics.safeMode ? "Enabled" : "Disabled")
            diagnosticsRow("Launch count", "\(preferences.launchDiagnostics.launchCount)")
            ForEach(preflight.items) { item in
                diagnosticsRow(item.id.title, item.statusTitle)
            }
            diagnosticsRow("Settings backup", draft.privacy.allowGitBackupsForSettings ? "Allowed for config only" : "Disabled")

            Divider()

            Text("App Readiness")
                .font(.headline)
            Text(diagnostics.summary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(diagnostics.modules) { module in
                    DiagnosticModuleRow(module: module)
                }
            }

            Divider()

            Text("CLI")
                .font(.headline)
            Text(diagnostics.cliSummary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(diagnostics.cliCommands.joined(separator: "\n"))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Screen Recording Settings") {
                NSWorkspace.shared.open(ScreenCapturePermission.privacySettingsURL)
            }
            Button("Open Microphone Settings") {
                NSWorkspace.shared.open(MicrophonePermission.privacySettingsURL)
            }
            Button("Open Camera Settings") {
                NSWorkspace.shared.open(CameraPermission.privacySettingsURL)
            }
            Button("Open Input Monitoring Settings") {
                NSWorkspace.shared.open(InputMonitoringPermission.privacySettingsURL)
            }
            Button("Open Accessibility Settings") {
                NSWorkspace.shared.open(AccessibilityPermission.privacySettingsURL)
            }
            Button("Review Onboarding") {
                openWindow(id: "onboarding")
                NSApplication.shared.activate()
            }
        }
    }

    private func diagnosticsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func exportSettingsPreset() {
        let panel = NSSavePanel()
        panel.title = "Export Settings Preset"
        panel.nameFieldStringValue = "lessonmeld-settings.\(LessonPresetFile.fileExtension)"
        if let contentType = Self.lessonPresetContentType {
            panel.allowedContentTypes = [contentType]
        }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let preset = LessonPreset(
                name: "LessonMeld Settings",
                summary: "Capture, annotation, and export defaults.",
                capturePreferences: draft.capture,
                annotationPreferences: draft.annotation,
                exportPreferences: draft.export
            )
            try LessonPresetFile.save(preset, to: Self.presetURLWithExtension(url))
            presetMessage = "Exported \(preset.name)."
        } catch {
            presetMessage = error.localizedDescription
        }
    }

    private func importSettingsPreset() {
        let panel = NSOpenPanel()
        panel.title = "Import Settings Preset"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let contentType = Self.lessonPresetContentType {
            panel.allowedContentTypes = [contentType]
        }
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let preset = try LessonPresetFile.load(from: url)
            draft = LessonPresetApplier.applyPreferences(preset, to: draft)
            presetMessage = "Imported \(preset.name). Save to keep these settings."
            saveMessage = "Unsaved"
        } catch {
            presetMessage = error.localizedDescription
        }
    }

    private static var lessonPresetContentType: UTType? {
        UTType(filenameExtension: LessonPresetFile.fileExtension) ?? .json
    }

    private static func presetURLWithExtension(_ url: URL) -> URL {
        url.pathExtension.lowercased() == LessonPresetFile.fileExtension
            ? url
            : url.appendingPathExtension(LessonPresetFile.fileExtension)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<LessonMeldPreferences, Value>) -> Binding<Value> {
        Binding {
            draft[keyPath: keyPath]
        } set: { value in
            draft[keyPath: keyPath] = value
            saveMessage = "Unsaved"
        }
    }

    private func intBinding(_ keyPath: WritableKeyPath<LessonMeldPreferences, Int>) -> Binding<Int> {
        binding(keyPath)
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<LessonMeldPreferences, Double>) -> Binding<Double> {
        binding(keyPath)
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<LessonMeldPreferences, String?>) -> Binding<String?> {
        Binding {
            draft[keyPath: keyPath]
        } set: { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            draft[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
            saveMessage = "Unsaved"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
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

    private func shortcutBinding(_ action: LessonMeldShortcutAction) -> Binding<String> {
        Binding {
            draft.shortcuts[action] ?? ""
        } set: { value in
            draft.shortcuts[action] = value
            saveMessage = "Unsaved"
        }
    }

    private func paletteColorBinding(_ index: Int) -> Binding<String> {
        Binding {
            guard draft.annotation.paletteHexColors.indices.contains(index) else {
                return "#FFFFFF"
            }
            return draft.annotation.paletteHexColors[index]
        } set: { value in
            guard draft.annotation.paletteHexColors.indices.contains(index) else { return }
            draft.annotation.paletteHexColors[index] = value
            saveMessage = "Unsaved"
        }
    }

    private func refreshDraft() {
        draft = preferences.snapshot.normalized()
        saveMessage = "Saved"
    }

    private func applySettingsRequest(_ request: LessonMeldSettingsWindowRequest?) {
        guard let section = request?.section else { return }
        selectedSection = section
    }

    private func sectionMatchesSearch(_ section: LessonMeldSettingsSection) -> Bool {
        let query = searchQuery
        guard !query.isEmpty else { return true }
        return section.title.lowercased().contains(query)
            || section.groupTitle.lowercased().contains(query)
            || section.searchKeywords.lowercased().contains(query)
    }

    private func sectionHasUnsavedChanges(_ section: LessonMeldSettingsSection) -> Bool {
        let saved = preferences.snapshot.normalized()
        switch section {
        case .general:
            return draft.general != saved.general
                || draft.capture.showRecorderControlTooltips != saved.capture.showRecorderControlTooltips
        case .capture:
            return draft.capture.quickRecordDurationSeconds != saved.capture.quickRecordDurationSeconds
                || draft.capture.fps != saved.capture.fps
                || draft.capture.includeCursor != saved.capture.includeCursor
                || draft.capture.captureInteractionMetadata != saved.capture.captureInteractionMetadata
                || draft.capture.countdownSeconds != saved.capture.countdownSeconds
                || draft.capture.rememberLastRegion != saved.capture.rememberLastRegion
                || draft.capture.hideRecorderControlsFromCapture != saved.capture.hideRecorderControlsFromCapture
        case .camera:
            return draft.capture.captureWebcam != saved.capture.captureWebcam
                || draft.capture.cameraResolution != saved.capture.cameraResolution
                || draft.capture.webcamFPS != saved.capture.webcamFPS
                || draft.capture.webcamAspectRatio != saved.capture.webcamAspectRatio
                || draft.capture.webcamFrameShape != saved.capture.webcamFrameShape
                || draft.capture.webcamCornerRadius != saved.capture.webcamCornerRadius
                || draft.capture.webcamRelativeSize != saved.capture.webcamRelativeSize
                || draft.capture.webcamMirror != saved.capture.webcamMirror
                || draft.capture.webcamBorderEnabled != saved.capture.webcamBorderEnabled
                || draft.capture.webcamShadowEnabled != saved.capture.webcamShadowEnabled
                || draft.capture.showFloatingWebcamPreview != saved.capture.showFloatingWebcamPreview
        case .audio:
            return draft.capture.captureMicrophone != saved.capture.captureMicrophone
                || draft.capture.microphoneDeviceID != saved.capture.microphoneDeviceID
                || draft.capture.captureSystemAudio != saved.capture.captureSystemAudio
        case .transcription:
            return draft.transcription != saved.transcription
        case .editor:
            return false
        case .annotations:
            return draft.annotation != saved.annotation
        case .export:
            return draft.export != saved.export
                || draft.integrations.learnHouseEnabled != saved.integrations.learnHouseEnabled
                || draft.integrations.agentManifestsEnabled != saved.integrations.agentManifestsEnabled
        case .privacy:
            return draft.privacy != saved.privacy
        case .shortcuts:
            return draft.shortcuts != saved.shortcuts
        case .diagnostics, .presets, .community:
            return false
        }
    }

    private func revertSection(_ section: LessonMeldSettingsSection) {
        let saved = preferences.snapshot.normalized()
        switch section {
        case .general:
            draft.general = saved.general
            draft.capture.showRecorderControlTooltips = saved.capture.showRecorderControlTooltips
        case .capture:
            draft.capture.quickRecordDurationSeconds = saved.capture.quickRecordDurationSeconds
            draft.capture.fps = saved.capture.fps
            draft.capture.includeCursor = saved.capture.includeCursor
            draft.capture.captureInteractionMetadata = saved.capture.captureInteractionMetadata
            draft.capture.countdownSeconds = saved.capture.countdownSeconds
            draft.capture.rememberLastRegion = saved.capture.rememberLastRegion
            draft.capture.hideRecorderControlsFromCapture = saved.capture.hideRecorderControlsFromCapture
        case .camera:
            draft.capture.captureWebcam = saved.capture.captureWebcam
            draft.capture.cameraResolution = saved.capture.cameraResolution
            draft.capture.webcamFPS = saved.capture.webcamFPS
            draft.capture.webcamAspectRatio = saved.capture.webcamAspectRatio
            draft.capture.webcamFrameShape = saved.capture.webcamFrameShape
            draft.capture.webcamCornerRadius = saved.capture.webcamCornerRadius
            draft.capture.webcamRelativeSize = saved.capture.webcamRelativeSize
            draft.capture.webcamMirror = saved.capture.webcamMirror
            draft.capture.webcamBorderEnabled = saved.capture.webcamBorderEnabled
            draft.capture.webcamShadowEnabled = saved.capture.webcamShadowEnabled
            draft.capture.showFloatingWebcamPreview = saved.capture.showFloatingWebcamPreview
        case .audio:
            draft.capture.captureMicrophone = saved.capture.captureMicrophone
            draft.capture.microphoneDeviceID = saved.capture.microphoneDeviceID
            draft.capture.captureSystemAudio = saved.capture.captureSystemAudio
        case .transcription:
            draft.transcription = saved.transcription
        case .editor:
            break
        case .annotations:
            draft.annotation = saved.annotation
        case .export:
            draft.export = saved.export
            draft.integrations.learnHouseEnabled = saved.integrations.learnHouseEnabled
            draft.integrations.agentManifestsEnabled = saved.integrations.agentManifestsEnabled
        case .privacy:
            draft.privacy = saved.privacy
        case .shortcuts:
            draft.shortcuts = saved.shortcuts
        case .diagnostics, .presets, .community:
            break
        }
        saveMessage = "Section reverted"
    }

    private func confirmResetDefaults() {
        let alert = NSAlert()
        alert.messageText = "Reset all settings to defaults?"
        alert.informativeText = "This stages default app settings. Nothing is saved until you choose Save All."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset Defaults")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        draft = LessonMeldPreferences()
        saveMessage = "Defaults staged"
    }

    private func chooseTranscriptionModelFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Transcription Model"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.transcription.modelPath = url.path
        saveMessage = "Unsaved"
    }
}

private struct AnnotationColorRow: View {
    var title: String
    @Binding var hex: String
    var canMakeDefault: Bool
    var canRemove: Bool
    var onMakeDefault: () -> Void
    var onRemove: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                rowContent
            }

            VStack(alignment: .leading, spacing: 8) {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        Group {
            Text(title)
                .frame(width: 120, alignment: .leading)
            ColorSwatch(hex: hex)
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44)
            TextField("Hex", text: $hex)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

            if canMakeDefault {
                Button("Default") {
                    onMakeDefault()
                }
            }

            if canRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove \(title)")
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding {
            Color(hex: hex) ?? Color(nsColor: .textColor)
        } set: { color in
            if let nextHex = color.hexString {
                hex = nextHex
            }
        }
    }
}

private struct ColorSwatch: View {
    var hex: String

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(hex: hex) ?? .clear)
            .frame(width: 30, height: 24)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.secondary.opacity(0.55), lineWidth: 1)
            }
            .accessibilityLabel(hex.normalizedHexString ?? "Invalid color")
    }
}

private extension String {
    var normalizedHexString: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6, raw.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return "#\(raw.uppercased())"
    }
}

private extension Color {
    init?(hex: String) {
        guard let normalized = hex.normalizedHexString else {
            return nil
        }
        let raw = String(normalized.dropFirst())
        guard let value = UInt32(raw, radix: 16) else {
            return nil
        }

        self.init(nsColor: NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        ))
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return nil
        }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private struct ConfigBackupSettingsPanel: View {
    @ObservedObject var preferences: AppPreferencesController
    @State private var message = "Writes current settings to JSON before committing safe config files."
    @State private var isWorking = false
    @State private var messageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("Config Backup")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(messageIsError ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack {
                    backupButtons
                }

                VStack(alignment: .leading, spacing: 8) {
                    backupButtons
                }
            }
            .disabled(isWorking || !preferences.snapshot.privacy.allowGitBackupsForSettings)
        }
    }

    private var backupButtons: some View {
        Group {
            Button("Plan") {
                run { try planBackup() }
            }
            Button("Init Repo") {
                run { try initRepository() }
            }
            Button("Write Settings JSON") {
                run { try writeSettingsSnapshot() }
            }
            Button("Commit Backup") {
                run { try commitBackup() }
            }
            .keyboardShortcut("b", modifiers: [.option, .command])
        }
    }

    private func run(_ action: () throws -> String) {
        isWorking = true
        messageIsError = false
        message = "Working..."

        do {
            message = try action()
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
        isWorking = false
    }

    private func planBackup() throws -> String {
        let plan = try ConfigBackupPlanner().plan(rootURL: rootURL())
        return "Plan includes \(plan.includePaths.count) files and excludes \(plan.excludedPaths.count) files."
    }

    private func initRepository() throws -> String {
        let status = try ConfigGitBackupManager().ensureRepository(rootURL: rootURL())
        return status.repositoryInitialized
            ? "Local Git backup repo is initialized with \(status.changedPaths.count) pending files."
            : "Local Git backup repo is not initialized."
    }

    private func writeSettingsSnapshot() throws -> String {
        let url = try writeSettingsFile()
        return "Wrote \(url.path)."
    }

    private func commitBackup() throws -> String {
        _ = try writeSettingsFile()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let result = try ConfigGitBackupManager().commit(
            rootURL: rootURL(),
            message: "Backup Digital Meld LessonMeld config \(formatter.string(from: Date()))"
        )
        if result.didCommit {
            return "Committed \(result.committedPaths.count) files as \(result.commitHash ?? "unknown")."
        }
        return result.message
    }

    private func writeSettingsFile() throws -> URL {
        let fileURL = rootURL().appendingPathComponent("settings/preferences.json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try DMLessonJSON.encoder().encode(preferences.snapshot.normalized())
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private func rootURL() -> URL {
        let expanded = NSString(string: preferences.snapshot.privacy.configBackupRootPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}

private struct DiagnosticModuleRow: View {
    let module: DiagnosticModule

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: module.symbolName)
                .font(.title3)
                .foregroundStyle(module.state.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(module.name)
                        .font(.headline)
                    Text(module.state.label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(module.state.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(module.state.tint)
                }

                Text(module.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CommunityLinkButton: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LessonMeldDesign.rowFill, in: RoundedRectangle(cornerRadius: LessonMeldDesign.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title)")
        .help(url.absoluteString)
    }
}

private enum CommunityLinks {
    static let sstb = URL(string: "https://www.sstb.ai")!
    static let podcastPlaylist = URL(string: "https://www.youtube.com/playlist?list=PLw2ImU79nlNNgAbYOkdMpSPaqYgK2CDLR")!
    static let discord = URL(string: "https://discord.gg/Gmfkm7QVSF")!
}

private struct SettingsSectionView<Content: View>: View {
    var title: String
    var subtitle: String
    var scope: SettingsScope = .app
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                Label(scope.title, systemImage: scope.systemImage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Form {
                content
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}

private enum SettingsScope {
    case app
    case futureRecordings
    case futureDefaults
    case projectLevel

    var title: String {
        switch self {
        case .app:
            "App setting"
        case .futureRecordings:
            "Future recordings"
        case .futureDefaults:
            "Future lesson defaults"
        case .projectLevel:
            "Project-level settings"
        }
    }

    var systemImage: String {
        switch self {
        case .app:
            "app"
        case .futureRecordings:
            "record.circle"
        case .futureDefaults:
            "slider.horizontal.3"
        case .projectLevel:
            "doc.badge.gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .app:
            .secondary
        case .futureRecordings:
            .orange
        case .futureDefaults:
            .blue
        case .projectLevel:
            .purple
        }
    }
}


private extension LessonMeldShortcutAction {
    var displayName: String {
        switch self {
        case .showSettings: "Show Settings"
        case .showOnboarding: "Show Onboarding"
        case .openAnnotationOverlay: "Open Annotation Overlay"
        case .quickRecord: "Quick Record"
        case .stopRecording: "Stop Recording"
        case .quickColor1: "Quick Color 1"
        case .quickColor2: "Quick Color 2"
        case .quickColor3: "Quick Color 3"
        case .quickColor4: "Quick Color 4"
        }
    }
}
