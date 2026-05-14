import AppKit
import AVFoundation
import AVKit
import DMLessonMeldCore
import SwiftUI
import UniformTypeIdentifiers

struct ProjectEditorView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appRouter: LessonMeldAppRouter
    @ObservedObject var preferences: AppPreferencesController
    @ObservedObject var annotationOverlay: AnnotationOverlayCoordinator
    @ObservedObject var quickRecorder: QuickRecorderModel
    let fallbackAnnotationOverlayHandler: (LessonMeldPreferences) -> Void
    @StateObject private var model = ProjectEditorModel()
    @State private var showRecoveryNotice = false
    @State private var didShowRecoveryNoticeThisLaunch = false
    @State private var showTechnicalDetails = false
    @State private var showLessonMarkers = true
    @State private var editorInspectorTab: EditorInspectorTab = .edits
    @State private var timelineZoom = 1.0
    @State private var activeTimelineDrag: TimelineDragState?
    @State private var activeOverlayDrag: OverlayPreviewDragState?
    @State private var activeOverlayResizeDrag: OverlayPreviewResizeDragState?
    @State private var selectedTimelineItem: TimelineSelection?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 250)
            Divider()
            contentPane
                .frame(minWidth: 700)
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
            model.apply(preferences.snapshot)
            quickRecorder.refreshPermissions(updateMessage: false)
            quickRecorder.openProjectHandler = { [weak model] projectURL in
                model?.loadProject(projectURL)
            }
            quickRecorder.annotationOverlayHandler = { [annotationOverlay, weak model] preferences in
                let storeURL = model?.projectURL == nil ? nil : model?.prepareAnnotationSidecarForOverlay()
                annotationOverlay.open(preferences: preferences, annotationStoreURL: storeURL, forceToolbarVisible: true)
            }
            LocalAppControlBridge.shared.configure(quickRecorder: quickRecorder, preferences: preferences)
            ProjectOpenRouter.shared.registerConsumer { [weak model] projectURL in
                model?.loadProject(projectURL)
            }
            if preferences.shouldUseRecoveryLaunch, !didShowRecoveryNoticeThisLaunch {
                showRecoveryNotice = true
                didShowRecoveryNoticeThisLaunch = true
            }
            applyLaunchPreferences()
        }
        .onDisappear {
            quickRecorder.openProjectHandler = nil
            quickRecorder.annotationOverlayHandler = fallbackAnnotationOverlayHandler
            ProjectOpenRouter.shared.unregisterConsumer()
            model.teardown()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            quickRecorder.refreshPermissions(updateMessage: false)
        }
        .onReceive(appRouter.$importVideoRequest.compactMap(\.self)) { _ in
            model.importVideoForEditing(preferences.snapshot)
        }
    }

    private func applyLaunchPreferences() {
        guard !preferences.didApplyLaunchPreferences else { return }
        preferences.didApplyLaunchPreferences = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)

            guard !preferences.shouldUseRecoveryLaunch else {
                NSApplication.shared.activate()
                return
            }

            if preferences.snapshot.general.showAnnotationOverlayAtLaunch {
                annotationOverlay.open(preferences: preferences.snapshot)
            }
            if preferences.shouldShowOnboardingAtLaunch {
                preferences.didPresentOnboardingThisLaunch = true
                openWindow(id: "onboarding")
            }
        }
    }

    @ViewBuilder private var contentPane: some View {
        if model.projectURL != nil, let manifest = model.manifest, let summary = model.summary {
            if manifest.media.screen != nil {
                mediaEditorWorkspace(summary: summary, manifest: manifest)
                    .padding(.top, 44)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    projectDashboard(summary: summary, manifest: manifest)
                        .contentPadding(top: 44)
                }
            }
        } else {
            firstRunDashboard
                .contentPadding(top: 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LessonMeld")
                    .font(.title2.weight(.semibold))
                Text("Record, review, render, and package your lessons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            sidebarSection("Workflow")

            Button {
                quickRecorder.presentControlBar(preferences: preferences)
            } label: {
                Label(quickRecorder.isRecording ? "Recording Controls" : "Record", systemImage: "record.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                model.importVideoForEditing(preferences.snapshot)
            } label: {
                Label("Edit Video", systemImage: "film")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                if annotationOverlay.isPresented {
                    annotationOverlay.close()
                } else {
                    openAnnotationOverlayFromEditor()
                }
            } label: {
                Label(annotationOverlay.isPresented ? "Close Tools" : "Annotate", systemImage: "paintpalette")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            sidebarSection("Project")

            Button {
                model.newProject(preferences.snapshot)
            } label: {
                Label("New Project", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                model.openProject()
            } label: {
                Label("Open Project", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                model.revealProject()
            } label: {
                Label("Reveal Project", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.projectURL == nil)

            Divider()

            sidebarSection("App")

            Button {
                appRouter.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                openWindow(id: "onboarding")
                NSApplication.shared.activate()
            } label: {
                Label("Onboarding", systemImage: "checklist")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                openWindow(id: "command-palette")
                NSApplication.shared.activate()
            } label: {
                Label("Command Palette", systemImage: "command")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            if let projectURL = model.projectURL {
                Text(projectURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(8)
            } else {
                Text("Record a new lesson, import an existing video, or open a lesson bundle to review media, render cuts, and package a teaching-ready lesson.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !model.message.isEmpty {
                Text(model.message)
                    .font(.caption)
                    .foregroundStyle(model.messageIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 64)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarSection(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private func projectDashboard(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            projectHeader(summary: summary, manifest: manifest)
            lessonOverviewPanel(summary: summary, manifest: manifest)

            if manifest.media.screen == nil {
                recordPanel
            } else {
                previewPanel(manifest: manifest)
                HStack(alignment: .top, spacing: 16) {
                    cutListPanel(manifest: manifest)
                    zoomRegionPanel(manifest: manifest)
                }
                renderPanel(manifest: manifest)
                trimPanel(manifest: manifest)
            }

            lessonMarkersPanel(manifest: manifest)
            metadataPanel
            annotationProjectPanel(manifest: manifest)
            technicalDetailsPanel(summary: summary, manifest: manifest)
        }
    }

    private func mediaEditorWorkspace(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        VStack(spacing: 0) {
            mediaEditorTopBar(summary: summary, manifest: manifest)
                .padding(.bottom, 12)

            Divider()

            HStack(spacing: 0) {
                mediaEditorStage(manifest: manifest)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                Divider()

                mediaEditorInspector(summary: summary, manifest: manifest)
                    .frame(width: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            mediaTimelineEditor(manifest: manifest)
                .frame(height: 236)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mediaEditorTopBar(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label("Edit Video", systemImage: "film")
                        .font(.headline)
                    statusPill(reviewStatus(manifest), systemImage: "timeline.selection", tint: hasBlockingIssues(summary) ? .red : .blue)
                }
                Text(manifest.metadata.lessonTitle)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let projectURL = model.projectURL {
                    Label(projectURL.path, systemImage: "folder")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Button {
                model.importVideoForEditing(preferences.snapshot)
            } label: {
                Label("Import", systemImage: "film.badge.plus")
            }

            Button {
                model.saveEditDecisions()
            } label: {
                Label("Save Edits", systemImage: "checkmark.circle")
            }
            .disabled(model.projectURL == nil)

            Button {
                model.exportRender(preferences.snapshot)
            } label: {
                Label(model.isRendering ? "Rendering..." : "Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRendering || model.projectURL == nil)
        }
    }

    private func mediaEditorStage(manifest: ProjectManifest) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.togglePlayback()
                } label: {
                    Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])

                Text("\(model.formattedCurrentTime) / \(model.formattedDuration)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 148, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { model.currentTimeSeconds },
                        set: { model.seek(to: $0) }
                    ),
                    in: 0...max(model.previewDurationSeconds, 1)
                )

                Button {
                    model.setTrimStartToPlayhead()
                } label: {
                    Label("Trim In", systemImage: "timeline.selection")
                }

                Button {
                    model.setTrimEndToPlayhead()
                } label: {
                    Label("Trim Out", systemImage: "timeline.selection")
                }

                Button {
                    model.addCutAtPlayhead()
                    editorInspectorTab = .cuts
                } label: {
                    Label("Cut", systemImage: "scissors")
                }

                Button {
                    model.addZoomAtPlayhead()
                    editorInspectorTab = .zooms
                } label: {
                    Label("Zoom", systemImage: "plus.magnifyingglass")
                }
            }

            ZStack {
                canvasPreviewBackground

                if let player = model.player {
                    ProjectVideoPlayer(player: player, controlsStyle: .none)
                        .aspectRatio(model.canvasPreviewAspectRatio, contentMode: .fit)
                        .padding(model.canvasPreviewPadding)
                        .clipShape(RoundedRectangle(cornerRadius: model.canvasPreviewCornerRadius))
                        .shadow(
                            color: model.canvasShadowEnabled ? .black.opacity(model.canvasShadowOpacity) : .clear,
                            radius: model.canvasShadowEnabled ? 18 : 0,
                            y: model.canvasShadowEnabled ? 8 : 0
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Preview will load after the project screen video is available.")
                        .foregroundStyle(.secondary)
                }
                zoomFocusOverlay
                overlayPreviewOverlay
                captionPreviewOverlay
                cursorPreviewOverlay
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                Button {
                    model.copyCurrentFrame()
                } label: {
                    Label("Copy Frame", systemImage: "doc.on.doc")
                }
                Button {
                    model.exportCurrentFrame()
                } label: {
                    Label("Export Frame...", systemImage: "photo")
                }
                Button {
                    openAnnotationOverlayFromEditor()
                } label: {
                    Label("Annotate", systemImage: "paintpalette")
                }
                Spacer()
                if model.isRendering {
                    ProgressView(value: model.renderProgress)
                        .frame(width: 160)
                    Text("\(Int((model.renderProgress * 100).rounded()))%")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.trailing, 16)
        .padding(.vertical, 14)
    }

    private func mediaEditorInspector(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Inspector", selection: $editorInspectorTab) {
                ForEach(EditorInspectorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch editorInspectorTab {
                    case .edits:
                        editorEditsInspector(manifest: manifest)
                    case .canvas:
                        editorCanvasInspector(manifest: manifest)
                    case .cuts:
                        editorCutsInspector(manifest: manifest)
                    case .zooms:
                        editorZoomsInspector(manifest: manifest)
                    case .overlays:
                        editorOverlaysInspector(manifest: manifest)
                    case .camera:
                        editorCameraInspector(manifest: manifest)
                    case .audio:
                        editorAudioInspector(manifest: manifest)
                    case .captions:
                        editorCaptionsInspector(manifest: manifest)
                    case .cursor:
                        editorCursorInspector(manifest: manifest)
                    case .export:
                        editorExportInspector(summary: summary, manifest: manifest)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
        }
        .padding(.leading, 16)
        .padding(.vertical, 14)
    }

    private func editorEditsInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            inspectorSectionTitle("Trim")
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Start").foregroundStyle(.secondary)
                    TextField("0", text: $model.trimStartSeconds)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("End").foregroundStyle(.secondary)
                    TextField("End", text: $model.trimEndSeconds)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Duration").foregroundStyle(.secondary)
                    TextField("Duration", text: $model.sourceDurationSeconds)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }

            HStack {
                Button("Set In") { model.setTrimStartToPlayhead() }
                Button("Set Out") { model.setTrimEndToPlayhead() }
                Button(model.isTrimming ? "Exporting..." : "Export Trim") { model.exportTrim() }
                    .disabled(model.isTrimming || model.projectURL == nil)
            }

            Divider()

            inspectorSectionTitle("Quick Actions")
            HStack {
                Button("Add Cut") {
                    model.addCutAtPlayhead()
                    editorInspectorTab = .cuts
                }
                Button("Add Zoom") {
                    model.addZoomAtPlayhead()
                    editorInspectorTab = .zooms
                }
                Button("Add Overlay") {
                    model.addOverlayAtPlayhead(kind: .text)
                    editorInspectorTab = .overlays
                }
            }
            HStack {
                Button("Add Marker") {
                    model.addMarkerAtPlayhead()
                }
                Button("Save Markers") {
                    model.saveMarkers()
                }
            }

            Divider()

            inspectorSectionTitle("Counts")
            valueLine("Cuts", "\(model.cutRows.filter(\.isEnabled).count) enabled / \(model.cutRows.count)")
            valueLine("Zooms", "\(model.zoomRows.filter(\.isEnabled).count) enabled / \(model.zoomRows.count)")
            valueLine("Overlays", "\(model.overlayRows.filter(\.isEnabled).count) enabled / \(model.overlayRows.count)")
            valueLine("Speed", "\(model.speedRows.count)")
            valueLine("Audio", "\(model.audioVolumeRows.count) regions")
            valueLine("Captions", "\(model.captionRows.count)")
            valueLine("Markers", "\(model.markerRows.count)")
            valueLine("Annotations", "\(model.annotationItemCount)")
        }
    }

    private func editorCanvasInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            inspectorSectionTitle("Canvas")

            Picker("Aspect", selection: $model.canvasAspectRatio) {
                ForEach(EditorCanvasAspectRatio.allCases) { aspectRatio in
                    Text(aspectRatio.title).tag(aspectRatio)
                }
            }

            if model.canvasAspectRatio == .custom {
                HStack {
                    compactNumberField("Width", text: $model.canvasCustomWidth)
                    compactNumberField("Height", text: $model.canvasCustomHeight)
                }
            }

            Picker("Background", selection: $model.canvasBackgroundStyle) {
                ForEach(EditorCanvasBackgroundStyle.allCases) { style in
                    Text(style.rawValue.capitalized).tag(style)
                }
            }

            if model.canvasBackgroundStyle == .image {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.canvasBackgroundImagePath.isEmpty ? "No background image selected." : model.canvasBackgroundImagePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button {
                        model.chooseCanvasBackgroundImage()
                    } label: {
                        Label("Choose Image...", systemImage: "photo")
                    }
                }
            } else if model.canvasBackgroundStyle != .none {
                colorPickerRow("Primary", selection: $model.canvasPrimaryColor)
                if model.canvasBackgroundStyle == .gradient {
                    colorPickerRow("Secondary", selection: $model.canvasSecondaryColor)
                }
            }

            labeledSlider("Padding", value: $model.canvasPaddingRatio, range: 0...0.35, format: "%.2f")
            labeledSlider("Inset", value: $model.canvasInsetRatio, range: 0...0.35, format: "%.2f")
            labeledSlider("Corners", value: $model.canvasCornerRadiusRatio, range: 0...0.18, format: "%.2f")

            Toggle("Shadow", isOn: $model.canvasShadowEnabled)
                .toggleStyle(.checkbox)
            if model.canvasShadowEnabled {
                labeledSlider("Shadow opacity", value: $model.canvasShadowOpacity, range: 0...1, format: "%.2f")
            }

            Divider()

            inspectorSectionTitle("Crop")
            Toggle("Enable crop", isOn: $model.canvasCropEnabled)
                .toggleStyle(.checkbox)
            if model.canvasCropEnabled {
                HStack {
                    compactNumberField("X", text: $model.canvasCropX)
                    compactNumberField("Y", text: $model.canvasCropY)
                }
                HStack {
                    compactNumberField("Width", text: $model.canvasCropWidth)
                    compactNumberField("Height", text: $model.canvasCropHeight)
                }
            }

            HStack {
                Button("Save Canvas") {
                    model.saveEditorSettings()
                }
                Button("Reset") {
                    model.resetCanvasSettings()
                }
            }

            Text("Canvas settings are saved in \(EditorSettingsFile.defaultFileName) and applied during render/export.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func editorCutsInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                inspectorSectionTitle("Cuts")
                Spacer()
                Button {
                    model.addCutAtPlayhead()
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            if model.cutRows.isEmpty {
                Text("No cuts yet. Seek on the timeline, then add a cut for retakes or dead air.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach($model.cutRows) { $cut in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Enabled", isOn: $cut.isEnabled)
                                .toggleStyle(.checkbox)
                            Spacer()
                            Button {
                                model.seek(to: secondsValue(cut.startSeconds) ?? 0)
                            } label: {
                                Image(systemName: "playhead.left")
                            }
                            .buttonStyle(.borderless)
                            Button {
                                model.removeCut(id: cut.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        HStack {
                            compactNumberField("Start", text: $cut.startSeconds)
                            compactNumberField("End", text: $cut.endSeconds)
                        }
                        TextField("Reason", text: $cut.reason)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }
            }

            HStack {
                Button("Save") { model.saveEditDecisions() }
                Button(model.isTrimming ? "Exporting..." : "Export Cut List") { model.exportEditDecisions() }
                    .disabled(model.isTrimming || model.projectURL == nil)
                Button("Reload") { model.reloadEditDecisions() }
            }

            validationIssuesList
        }
    }

    private func editorZoomsInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                inspectorSectionTitle("Zooms")
                Spacer()
                Button {
                    model.addZoomAtPlayhead()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    model.addInstantZoomAtPlayhead()
                } label: {
                    Label("Instant", systemImage: "bolt")
                }
                Button {
                    model.generateAutoZoomsFromClicks()
                } label: {
                    Label("Auto", systemImage: "cursorarrow.click")
                }
            }

            Toggle("Generate automatic zooms from click metadata", isOn: $model.zoomAutoGenerationEnabled)
                .toggleStyle(.checkbox)

            if model.zoomRows.isEmpty {
                Text("No zooms yet. Seek to an important moment and add a zoom region.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach($model.zoomRows) { $zoom in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Enabled", isOn: $zoom.isEnabled)
                                .toggleStyle(.checkbox)
                            Spacer()
                            Button {
                                model.seek(to: secondsValue(zoom.startSeconds) ?? 0)
                            } label: {
                                Image(systemName: "playhead.left")
                            }
                            .buttonStyle(.borderless)
                            Button {
                                model.removeZoom(id: zoom.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        HStack {
                            compactNumberField("Start", text: $zoom.startSeconds)
                            compactNumberField("End", text: $zoom.endSeconds)
                        }
                        HStack {
                            Picker("Focus", selection: $zoom.focusMode) {
                                ForEach(ZoomFocusMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            Picker("Easing", selection: $zoom.easing) {
                                ForEach(ZoomEasing.allCases) { easing in
                                    Text(easing.title).tag(easing)
                                }
                            }
                        }
                        numericStringSlider("Scale", text: $zoom.scale, range: 1.1...6, format: "%.1f")
                        numericStringSlider("Focus size", text: $zoom.size, range: 0.08...1, format: "%.2f")
                        HStack {
                            numericStringSlider("X", text: $zoom.centerX, range: 0...1, format: "%.2f")
                            numericStringSlider("Y", text: $zoom.centerY, range: 0...1, format: "%.2f")
                        }
                        Text("Select the zoom block, then drag the focus box on the preview to place it visually.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }
            }

            HStack {
                Button("Save") { model.saveEditDecisions() }
                Button("Reload") { model.reloadEditDecisions() }
                Button("Save Zoom Defaults") { model.saveEditorSettings() }
            }

            validationIssuesList
        }
    }

    private func editorOverlaysInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                inspectorSectionTitle("Overlays")
                Spacer()
                Button {
                    model.addOverlayAtPlayhead(kind: .text)
                } label: {
                    Label("Text", systemImage: "textformat")
                }
                Button {
                    model.addOverlayAtPlayhead(kind: .callout)
                } label: {
                    Label("Callout", systemImage: "text.bubble")
                }
            }
            HStack {
                Button {
                    model.addOverlayAtPlayhead(kind: .rectangle)
                } label: {
                    Label("Shape", systemImage: "rectangle")
                }
                Button {
                    model.chooseOverlayImageAtPlayhead()
                } label: {
                    Label("Image", systemImage: "photo")
                }
                Button {
                    model.addOverlayAtPlayhead(kind: .highlight)
                } label: {
                    Label("Highlight", systemImage: "viewfinder")
                }
            }

            if model.overlayRows.isEmpty {
                Text("No overlays yet. Add text, shapes, callouts, or images, then drag them on the preview and timeline.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach($model.overlayRows) { $overlay in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Enabled", isOn: $overlay.isEnabled)
                                .toggleStyle(.checkbox)
                            Picker("Kind", selection: $overlay.kind) {
                                ForEach(OverlayKind.allCases) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }
                            Spacer()
                            Button {
                                model.seek(to: secondsValue(overlay.startSeconds) ?? 0)
                            } label: {
                                Image(systemName: "playhead.left")
                            }
                            .buttonStyle(.borderless)
                            Button {
                                model.removeOverlay(id: overlay.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        HStack {
                            compactNumberField("Start", text: $overlay.startSeconds)
                            compactNumberField("End", text: $overlay.endSeconds)
                        }
                        TextField("Text", text: $overlay.text)
                            .textFieldStyle(.roundedBorder)
                            .disabled(overlay.kind == .image || overlay.kind == .rectangle || overlay.kind == .ellipse || overlay.kind == .line || overlay.kind == .arrow || overlay.kind == .highlight)
                        if overlay.kind == .image {
                            Text(overlay.imagePath.isEmpty ? "No image selected." : overlay.imagePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Button {
                                model.chooseImage(forOverlayID: overlay.id)
                            } label: {
                                Label("Choose Image...", systemImage: "photo")
                            }
                        }
                        if overlay.kind == .highlight {
                            Picker("Mode", selection: $overlay.highlightMode) {
                                ForEach(OverlayHighlightMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            Picker("Shape", selection: $overlay.highlightShape) {
                                ForEach(OverlayHighlightShape.allCases) { shape in
                                    Text(shape.title).tag(shape)
                                }
                            }
                        }
                        HStack {
                            numericStringSlider("X", text: $overlay.x, range: 0...1, format: "%.2f")
                            numericStringSlider("Y", text: $overlay.y, range: 0...1, format: "%.2f")
                        }
                        HStack {
                            numericStringSlider("Width", text: $overlay.width, range: 0.04...1, format: "%.2f")
                            numericStringSlider("Height", text: $overlay.height, range: 0.04...1, format: "%.2f")
                        }
                        HStack {
                            numericStringSlider("Opacity", text: $overlay.opacity, range: 0...1, format: "%.2f")
                            numericStringSlider("Text size", text: $overlay.fontSize, range: 10...120, format: "%.0f")
                        }
                        HStack {
                            numericStringSlider("Fade in", text: $overlay.fadeInSeconds, range: 0...2, format: "%.2f")
                            numericStringSlider("Fade out", text: $overlay.fadeOutSeconds, range: 0...2, format: "%.2f")
                        }
                        HStack {
                            numericStringSlider("Corners", text: $overlay.cornerRadius, range: 0...96, format: "%.0f")
                            if overlay.kind == .highlight {
                                numericStringSlider("Feather", text: $overlay.featherRadius, range: 0...80, format: "%.0f")
                            }
                        }
                        if overlay.kind == .highlight {
                            numericStringSlider("Blur", text: $overlay.blurRadius, range: 0...80, format: "%.0f")
                        }
                        Picker("Animation", selection: $overlay.animationPreset) {
                            ForEach(OverlayAnimationPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        Stepper("Layer \(overlay.zIndex)", value: $overlay.zIndex, in: 0...99)
                        colorPickerRow("Text", selection: $overlay.textColor)
                        colorPickerRow("Fill", selection: $overlay.fillColor)
                        colorPickerRow("Stroke", selection: $overlay.strokeColor)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }
            }

            HStack {
                Button("Save Overlays") { model.saveOverlays() }
                Button("Reload") { model.reloadOverlays() }
            }
        }
    }

    private func editorCameraInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorSectionTitle("Camera")
            if manifest.media.webcam == nil {
                Text("Camera controls require a webcam track. Imported videos can still be edited, but camera layouts and reactions need a captured or added camera source.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Corner", selection: $model.cameraCorner) {
                    ForEach(PictureInPictureCorner.allCases, id: \.self) { corner in
                        Text(corner.title).tag(corner)
                    }
                }
                Picker("Aspect", selection: $model.cameraAspectRatio) {
                    ForEach(PictureInPictureAspectRatio.allCases, id: \.self) { aspect in
                        Text(aspect.title).tag(aspect)
                    }
                }
                Picker("Shape", selection: $model.cameraFrameShape) {
                    ForEach(PictureInPictureFrameShape.allCases, id: \.self) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                numericStringSlider("Size", text: $model.cameraWidthRatio, range: 0.1...1, format: "%.2f")
                numericStringSlider("Margin", text: $model.cameraMarginRatio, range: 0...0.2, format: "%.2f")
                numericStringSlider("Corners", text: $model.cameraCornerRadius, range: 0...96, format: "%.0f")
                HStack {
                    Toggle("Mirror", isOn: $model.cameraMirrored)
                        .toggleStyle(.checkbox)
                    Toggle("Border", isOn: $model.cameraBorderEnabled)
                        .toggleStyle(.checkbox)
                    Toggle("Shadow", isOn: $model.cameraShadowEnabled)
                        .toggleStyle(.checkbox)
                }

                Divider()
                HStack {
                    inspectorSectionTitle("Timed Layouts")
                    Spacer()
                    Button("PiP") { model.addCameraRegionAtPlayhead(preset: .cornerPip) }
                    Button("Side") { model.addCameraRegionAtPlayhead(preset: .sideBySide) }
                    Button("Full") { model.addCameraRegionAtPlayhead(preset: .fullCamera) }
                    Button("Hide") { model.addCameraRegionAtPlayhead(preset: .hidden) }
                }

                if model.cameraRegionRows.isEmpty {
                    Text("No timed camera layouts yet. Add a region, then drag it on the Camera timeline lane.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach($model.cameraRegionRows) { $region in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle("Enabled", isOn: $region.isEnabled)
                                    .toggleStyle(.checkbox)
                                Picker("Preset", selection: $region.preset) {
                                    ForEach(CameraLayoutPreset.allCases) { preset in
                                        Text(preset.title).tag(preset)
                                    }
                                }
                                Spacer()
                                Button {
                                    model.removeCameraRegion(id: region.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            HStack {
                                compactNumberField("Start", text: $region.startSeconds)
                                compactNumberField("End", text: $region.endSeconds)
                            }
                            HStack {
                                Picker("Animation", selection: $region.layoutAnimation) {
                                    ForEach(CameraLayoutAnimation.allCases) { animation in
                                        Text(animation.title).tag(animation)
                                    }
                                }
                                numericStringSlider("Transition", text: $region.transitionSeconds, range: 0...2, format: "%.2f")
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                    }
                }

                Divider()
                HStack {
                    inspectorSectionTitle("Reactions")
                    Spacer()
                    Button("Add Reaction") { model.addCameraReactionAtPlayhead() }
                }
                ForEach($model.cameraReactionRows) { $reaction in
                    HStack {
                        Toggle("", isOn: $reaction.isEnabled)
                            .toggleStyle(.checkbox)
                        TextField("Reaction", text: $reaction.text)
                            .frame(width: 76)
                        compactNumberField("Start", text: $reaction.startSeconds)
                        compactNumberField("End", text: $reaction.endSeconds)
                        Button {
                            model.removeCameraReaction(id: reaction.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    Button("Save Camera") { model.saveEditorSettings() }
                }
            }
        }
    }

    private func editorAudioInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorSectionTitle("Tracks")
            audioTrackControls(
                title: "Screen",
                detail: "Audio embedded in the screen recording when present.",
                gain: $model.screenAudioGain,
                muted: $model.screenAudioMuted,
                soloed: $model.screenAudioSoloed,
                isAvailable: manifest.media.screen != nil
            )
            audioTrackControls(
                title: "Microphone",
                detail: manifest.media.microphoneAudio?.relativePath ?? "No microphone sidecar in this project.",
                gain: $model.microphoneAudioGain,
                muted: $model.microphoneAudioMuted,
                soloed: $model.microphoneAudioSoloed,
                isAvailable: manifest.media.microphoneAudio != nil
            )
            audioTrackControls(
                title: "System",
                detail: manifest.media.systemAudio?.relativePath ?? "No system audio sidecar in this project.",
                gain: $model.systemAudioGain,
                muted: $model.systemAudioMuted,
                soloed: $model.systemAudioSoloed,
                isAvailable: manifest.media.systemAudio != nil
            )

            Divider()
            HStack {
                inspectorSectionTitle("Background Music")
                Spacer()
                Button {
                    model.chooseBackgroundMusic()
                } label: {
                    Label("Choose", systemImage: "music.note")
                }
                Button {
                    model.clearBackgroundMusic()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(model.backgroundMusicPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(model.backgroundMusicPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No background music selected." : model.backgroundMusicPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                compactNumberField("Start", text: $model.backgroundMusicStart)
                compactNumberField("Source", text: $model.backgroundMusicSourceStart)
                compactNumberField("Duration", text: $model.backgroundMusicDuration)
            }
            HStack {
                Toggle("Loop", isOn: $model.backgroundMusicLoop)
                    .toggleStyle(.checkbox)
                Toggle("Duck voice", isOn: $model.backgroundMusicDuckUnderVoice)
                    .toggleStyle(.checkbox)
            }
            numericStringSlider("Music gain", text: $model.backgroundMusicGain, range: 0...1.5, format: "%.2f")
            numericStringSlider("Ducked gain", text: $model.backgroundMusicDuckedGain, range: 0...1, format: "%.2f")
            HStack {
                numericStringSlider("Fade in", text: $model.backgroundMusicFadeIn, range: 0...10, format: "%.2f")
                numericStringSlider("Fade out", text: $model.backgroundMusicFadeOut, range: 0...10, format: "%.2f")
            }

            Divider()
            HStack {
                inspectorSectionTitle("Volume Regions")
                Spacer()
                Button {
                    model.addAudioVolumeRegionAtPlayhead()
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            if model.audioVolumeRows.isEmpty {
                Text("No volume regions yet. Add one to lower, boost, fade, or duck a selected timeline range.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach($model.audioVolumeRows) { $region in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Enabled", isOn: $region.isEnabled)
                                .toggleStyle(.checkbox)
                            Picker("Track", selection: $region.track) {
                                ForEach(EditorAudioTrackRole.allCases) { role in
                                    Text(role.title).tag(role)
                                }
                            }
                            Spacer()
                            Button {
                                model.removeAudioVolumeRegion(id: region.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        HStack {
                            compactNumberField("Start", text: $region.startSeconds)
                            compactNumberField("End", text: $region.endSeconds)
                        }
                        numericStringSlider("Gain", text: $region.gain, range: 0...2, format: "%.2f")
                        HStack {
                            numericStringSlider("Fade in", text: $region.fadeInSeconds, range: 0...10, format: "%.2f")
                            numericStringSlider("Fade out", text: $region.fadeOutSeconds, range: 0...10, format: "%.2f")
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }
            }

            Divider()
            HStack {
                inspectorSectionTitle("Speed Regions")
                Spacer()
                Button("0.5x") { model.addSpeedRegionAtPlayhead(rate: 0.5) }
                Button("1.5x") { model.addSpeedRegionAtPlayhead(rate: 1.5) }
                Button("2x") { model.addSpeedRegionAtPlayhead(rate: 2) }
            }
            if model.speedRows.isEmpty {
                Text("No speed regions yet. Speed regions are saved and shown on the timeline. Full render retiming is blocked until the exporter supports AV retiming.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach($model.speedRows) { $speed in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            compactNumberField("Start", text: $speed.startSeconds)
                            compactNumberField("End", text: $speed.endSeconds)
                            Button {
                                model.removeSpeedRegion(id: speed.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        numericStringSlider("Rate", text: $speed.playbackRate, range: 0.25...8, format: "%.2f")
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }
            }

            HStack {
                Button("Save Audio") { model.saveEditorSettings() }
                Button("Save Speed") { model.saveEditDecisions() }
            }
            validationIssuesList
        }
    }

    private func audioTrackControls(
        title: String,
        detail: String,
        gain: Binding<String>,
        muted: Binding<Bool>,
        soloed: Binding<Bool>,
        isAvailable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Mute", isOn: muted)
                    .toggleStyle(.checkbox)
                Toggle("Solo", isOn: soloed)
                    .toggleStyle(.checkbox)
            }
            numericStringSlider("Gain", text: gain, range: 0...2, format: "%.2f")
            Text(detail)
                .font(.caption)
                .foregroundStyle(isAvailable ? Color.secondary : Color.orange)
                .lineLimit(2)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
    }

    private func editorCaptionsInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                inspectorSectionTitle("Captions")
                Spacer()
                Button {
                    model.addCaptionAtPlayhead()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    model.importCaptions()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }

            if model.captionRows.isEmpty {
                Text("No captions yet. Import VTT, SRT, JSON, or text, or add a caption manually at the playhead.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach($model.captionRows) { $caption in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            compactNumberField("Start", text: $caption.startSeconds)
                            compactNumberField("End", text: $caption.endSeconds)
                            Button {
                                model.seek(to: secondsValue(caption.startSeconds) ?? 0)
                            } label: {
                                Image(systemName: "playhead.left")
                            }
                            .buttonStyle(.borderless)
                            Button {
                                model.removeCaption(id: caption.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        TextField("Caption text", text: $caption.text, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }
            }

            Divider()
            inspectorSectionTitle("Burn-in Style")
            Toggle("Burn captions into rendered video", isOn: $model.captionBurnInEnabled)
                .toggleStyle(.checkbox)
            Picker("Placement", selection: $model.captionPlacement) {
                ForEach(EditorCaptionPlacement.allCases) { placement in
                    Text(placement.title).tag(placement)
                }
            }
            TextField("Font", text: $model.captionFontName)
                .textFieldStyle(.roundedBorder)
            numericStringSlider("Font size", text: $model.captionFontSize, range: 12...96, format: "%.0f")
            numericStringSlider("Safe margin", text: $model.captionSafeMargin, range: 0...0.25, format: "%.2f")
            Stepper("Max lines \(model.captionMaxLineCount)", value: $model.captionMaxLineCount, in: 1...5)
            colorPickerRow("Text", selection: $model.captionTextColor)
            colorPickerRow("Background", selection: $model.captionBackgroundColor)

            HStack {
                Button("Save Captions") { model.saveCaptions() }
                Button("Export Sidecars") { model.exportCaptionSidecars() }
                Button("Save Style") { model.saveEditorSettings() }
            }
            Text("Captions are stored as project-local JSON and exported as VTT, SRT, and text sidecars for packages.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func editorCursorInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorSectionTitle("Cursor Effects")

            if manifest.media.cursorMetadata == nil {
                Text("This project has no cursor metadata. Import-only videos can still be edited, but cursor, click, and keyboard overlays need a recorded metadata sidecar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Pointer style", selection: $model.cursorPointerStyle) {
                ForEach(EditorCursorPointerStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .disabled(manifest.media.cursorMetadata == nil)
            Toggle("Show pointer", isOn: $model.cursorPointerVisible)
                .toggleStyle(.checkbox)
                .disabled(manifest.media.cursorMetadata == nil)
            Toggle("Smooth movement", isOn: $model.cursorSmoothMovement)
                .toggleStyle(.checkbox)
                .disabled(manifest.media.cursorMetadata == nil)
            labeledSlider("Pointer size", value: $model.cursorPointerScale, range: 0.5...2.5, format: "%.2f")
                .disabled(manifest.media.cursorMetadata == nil)
            colorPickerRow("Pointer fill", selection: $model.cursorPointerFillColor)
                .disabled(manifest.media.cursorMetadata == nil)
            colorPickerRow("Pointer outline", selection: $model.cursorPointerStrokeColor)
                .disabled(manifest.media.cursorMetadata == nil)

            Divider()
            inspectorSectionTitle("Clicks")
            Toggle("Show click ripple", isOn: $model.cursorClickEffectsVisible)
                .toggleStyle(.checkbox)
                .disabled(manifest.media.cursorMetadata == nil)
            colorPickerRow("Click color", selection: $model.cursorClickColor)
                .disabled(manifest.media.cursorMetadata == nil)
            labeledSlider("Click scale", value: $model.cursorClickScale, range: 0.5...3, format: "%.2f")
                .disabled(manifest.media.cursorMetadata == nil)
            labeledSlider("Click opacity", value: $model.cursorClickOpacity, range: 0...1, format: "%.2f")
                .disabled(manifest.media.cursorMetadata == nil)
            labeledSlider("Click duration", value: $model.cursorClickDuration, range: 0.08...1.5, format: "%.2f")
                .disabled(manifest.media.cursorMetadata == nil)
            Toggle("Click sound", isOn: $model.cursorClickSoundEnabled)
                .toggleStyle(.checkbox)
                .disabled(manifest.media.cursorMetadata == nil)
            labeledSlider("Click volume", value: $model.cursorClickSoundVolume, range: 0...1, format: "%.2f")
                .disabled(manifest.media.cursorMetadata == nil || !model.cursorClickSoundEnabled)

            Divider()
            inspectorSectionTitle("Keyboard")
            Toggle("Show shortcuts", isOn: $model.cursorKeyboardVisible)
                .toggleStyle(.checkbox)
                .disabled(manifest.media.cursorMetadata == nil)
            labeledSlider("Shortcut opacity", value: $model.cursorKeyboardOpacity, range: 0...1, format: "%.2f")
                .disabled(manifest.media.cursorMetadata == nil)

            Divider()
            HStack {
                inspectorSectionTitle("Hidden Ranges")
                Spacer()
                Button {
                    model.addCursorHiddenRangeAtPlayhead()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(manifest.media.cursorMetadata == nil)
            }
            if model.cursorHiddenRangeRows.isEmpty {
                Text("No cursor hide ranges.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($model.cursorHiddenRangeRows) { $range in
                    HStack {
                        compactNumberField("Start", text: $range.startSeconds)
                        compactNumberField("End", text: $range.endSeconds)
                        Button {
                            model.removeCursorHiddenRange(id: range.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Button("Save Cursor Settings") {
                model.saveEditorSettings()
            }
            .disabled(manifest.media.cursorMetadata == nil)
        }
    }

    private func editorExportInspector(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            inspectorSectionTitle("Export")
            Picker("Quality", selection: $model.renderQuality) {
                ForEach(RenderQuality.allCases, id: \.self) { quality in
                    Text(quality.rawValue.capitalized).tag(quality)
                }
            }
            Picker("File", selection: $model.renderFileType) {
                ForEach(RenderFileType.allCases, id: \.self) { fileType in
                    Text(fileType.rawValue.uppercased()).tag(fileType)
                }
            }

            TextField("Destination", text: $model.renderDestinationPath)
                .font(.system(.caption, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Choose...") { model.chooseRenderDestination() }
                Button("Check") { model.inspectRender(preferences.snapshot) }
                Button(model.isRendering ? "Rendering..." : "Export") { model.exportRender(preferences.snapshot) }
                    .disabled(model.isRendering || model.projectURL == nil)
            }

            Button(model.isPackagingLearnHouse ? "Packaging..." : "Package LearnHouse") {
                model.packageLearnHouse(preferences.snapshot)
            }
            .disabled(model.isPackagingLearnHouse || manifest.media.screen == nil)

            Divider()

            inspectorSectionTitle("Readiness")
            valueLine("Screen video", manifest.media.screen?.relativePath ?? "Missing")
            valueLine("Voice", audioStatus(manifest))
            valueLine("Webcam", manifest.media.webcam == nil ? "Optional" : "Captured")
            valueLine("Warnings", summary.issues.isEmpty ? "None" : "\(summary.issues.count)")

            if let inspection = model.renderInspection {
                Divider()
                inspectorSectionTitle("Render Plan")
                valueLine("Webcam PiP", inspection.hasWebcamOverlay ? "Yes" : "No")
                valueLine("Cursor Effects", inspection.hasCursorEffects ? "Yes" : "No")
                valueLine("Overlays", inspection.hasOverlays ? "Yes" : "No")
                valueLine("Annotations", inspection.hasAnnotations ? "Yes" : "No")
                valueLine("Captions", inspection.hasCaptions ? "Yes" : "No")
                valueLine("Zoom Regions", inspection.hasZoomRegions ? "Yes" : "No")
                valueLine("Audio Sources", "\(inspection.audioSourceCount)")
            }
        }
    }

    private var validationIssuesList: some View {
        Group {
            if !model.editValidationIssues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    inspectorSectionTitle("Validation")
                    ForEach(model.editValidationIssues.indices, id: \.self) { index in
                        let issue = model.editValidationIssues[index]
                        issueRow(issue.severity.rawValue, issue.message, path: issue.path)
                    }
                }
            }
        }
    }

    private func mediaTimelineEditor(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Timeline", systemImage: "timeline.selection")
                    .font(.headline)
                Text(model.formattedCurrentTime)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.stepPlayhead(by: -1)
                } label: {
                    Label("Back 1s", systemImage: "backward.frame")
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                Button {
                    model.stepPlayhead(by: 1)
                } label: {
                    Label("Forward 1s", systemImage: "forward.frame")
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                Button {
                    model.addCutAtPlayhead()
                    persistTimelineEditChanges(for: .moveCut)
                    editorInspectorTab = .cuts
                } label: {
                    Label("Cut", systemImage: "scissors")
                }
                .keyboardShortcut("b", modifiers: [])
                Button {
                    model.addZoomAtPlayhead()
                    persistTimelineEditChanges(for: .moveZoom)
                    editorInspectorTab = .zooms
                } label: {
                    Label("Zoom", systemImage: "plus.magnifyingglass")
                }
                .keyboardShortcut("z", modifiers: [])
                Button {
                    model.addAudioVolumeRegionAtPlayhead()
                    persistTimelineEditChanges(for: .moveAudioVolume)
                    editorInspectorTab = .audio
                } label: {
                    Label("Volume", systemImage: "speaker.wave.2")
                }
                Button {
                    model.addSpeedRegionAtPlayhead(rate: 2)
                    persistTimelineEditChanges(for: .moveSpeed)
                    editorInspectorTab = .audio
                } label: {
                    Label("Speed", systemImage: "speedometer")
                }
                Button {
                    model.addOverlayAtPlayhead(kind: .text)
                    persistTimelineEditChanges(for: .moveOverlay)
                    editorInspectorTab = .overlays
                } label: {
                    Label("Overlay", systemImage: "textformat")
                }
                Button {
                    model.addCaptionAtPlayhead()
                    persistTimelineEditChanges(for: .moveCaption)
                    editorInspectorTab = .captions
                } label: {
                    Label("Caption", systemImage: "captions.bubble")
                }
                Button {
                    model.addCursorHiddenRangeAtPlayhead()
                    persistTimelineEditChanges(for: .moveCursorHide)
                    editorInspectorTab = .cursor
                } label: {
                    Label("Hide Cursor", systemImage: "cursorarrow.slash")
                }
                Button {
                    deleteSelectedTimelineItem()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selectedTimelineItem == nil)
                Button {
                    model.saveEditDecisions()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
                Label("Scale", systemImage: "arrow.left.and.right")
                    .foregroundStyle(.secondary)
                Slider(value: $timelineZoom, in: 1...6)
                    .frame(width: 120)
            }
            if !model.editValidationIssues.isEmpty {
                Text(model.editValidationIssues.map(\.message).joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            GeometryReader { proxy in
                let duration = editorTimelineDuration
                let timelineWidth = max(proxy.size.width, proxy.size.width * CGFloat(timelineZoom))
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 8) {
                        timelineRuler(width: timelineWidth, duration: duration)
                        timelineLane(
                            title: "Clip",
                            tint: .yellow,
                            width: timelineWidth,
                            duration: duration,
                            height: 38
                        ) {
                            clipTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Audio",
                            tint: .teal,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            audioTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Speed",
                            tint: .indigo,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            speedTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Cuts",
                            tint: .red,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            cutTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Zooms",
                            tint: .purple,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            zoomTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Overlays",
                            tint: .green,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            overlayTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Captions",
                            tint: .mint,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            captionTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Camera",
                            tint: .orange,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            cameraTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Cursor",
                            tint: .cyan,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            cursorTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Markers",
                            tint: .blue,
                            width: timelineWidth,
                            duration: duration,
                            height: 26
                        ) {
                            markerTimelineContent(width: timelineWidth, duration: duration)
                        }
                    }
                    .frame(width: timelineWidth, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        playheadLine(width: timelineWidth, duration: duration)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard activeTimelineDrag == nil else { return }
                                model.seek(to: timelineSeconds(value.location.x, width: timelineWidth, duration: duration))
                            }
                    )
                }
            }
        }
        .padding(.top, 12)
    }

    private var editorTimelineDuration: Double {
        max(model.previewDurationSeconds, secondsValue(model.sourceDurationSeconds) ?? 0, 1)
    }

    private func timelineRuler(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...6, id: \.self) { tick in
                let ratio = CGFloat(tick) / 6
                let seconds = duration * Double(ratio)
                let x = timelineTrackInset + max(0, width - timelineTrackInset) * ratio
                VStack(alignment: .leading, spacing: 2) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 1, height: 8)
                    Text(formatSeconds(seconds))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .offset(x: max(0, min(width - 48, x)))
            }
        }
        .frame(width: width, height: 24, alignment: .topLeading)
    }

    private func timelineLane<Content: View>(
        title: String,
        tint: Color,
        width: CGFloat,
        duration: Double,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(tint.opacity(0.28), lineWidth: 1)
                )
            content()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
        }
        .frame(width: width, height: height)
    }

    private func clipTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            let trimStart = secondsValue(model.trimStartSeconds) ?? 0
            let trimEnd = secondsValue(model.trimEndSeconds) ?? duration
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.yellow.opacity(0.36))
                .frame(width: max(0, width - timelineTrackInset))
                .offset(x: timelineTrackInset)
            if let trimStart = secondsValue(model.trimStartSeconds), trimStart > 0 {
                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: max(0, timelineX(trimStart, width: width, duration: duration) - timelineTrackInset))
                    .offset(x: timelineTrackInset)
            }
            if let trimEnd = secondsValue(model.trimEndSeconds), trimEnd < duration {
                let x = timelineX(trimEnd, width: width, duration: duration)
                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: max(0, width - x))
                    .offset(x: x)
            }
            Text("Clip  \(formatSeconds(duration))")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.leading, max(timelineTrackInset + 10, width * 0.46))
            trimHandle("In")
                .offset(x: timelineX(trimStart, width: width, duration: duration) - 5)
                .gesture(timelineDragGesture(action: .trimStart, id: "trim-start", start: trimStart, end: trimEnd, width: width, duration: duration))
                .help("Drag to set trim start")
            trimHandle("Out")
                .offset(x: timelineX(trimEnd, width: width, duration: duration) - 5)
                .gesture(timelineDragGesture(action: .trimEnd, id: "trim-end", start: trimStart, end: trimEnd, width: width, duration: duration))
                .help("Drag to set trim end")
        }
        .contextMenu {
            Button("Set Trim In to Playhead") {
                model.setTrimStartToPlayhead()
                persistTimelineEditChanges(for: .trimStart)
            }
            Button("Set Trim Out to Playhead") {
                model.setTrimEndToPlayhead()
                persistTimelineEditChanges(for: .trimEnd)
            }
            Button("Clear Trim") {
                model.clearTrim(duration: duration)
                persistTimelineEditChanges(for: .trimStart)
            }
        }
    }

    private func cutTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.cutRows) { cut in
                if let start = secondsValue(cut.startSeconds), let end = secondsValue(cut.endSeconds), end > start {
                    timelineBlock(
                        title: cut.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Cut" : cut.reason,
                        tint: .red,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: cut.isEnabled,
                        isSelected: selectedTimelineItem == .cut(cut.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .cut(cut.id)
                        editorInspectorTab = .cuts
                    }
                    .gesture(timelineDragGesture(action: .moveCut, id: cut.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCutStart, id: cut.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCutEnd, id: cut.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Cut") {
                            model.seek(to: start)
                        }
                        Button(cut.isEnabled ? "Disable Cut" : "Enable Cut") {
                            model.toggleCutEnabled(id: cut.id)
                            persistTimelineEditChanges(for: .moveCut)
                        }
                        Button("Duplicate Cut") {
                            model.duplicateCut(id: cut.id, duration: duration)
                            persistTimelineEditChanges(for: .moveCut)
                        }
                        Button("Remove Cut", role: .destructive) {
                            model.removeCut(id: cut.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveCut)
                        }
                    }
                }
            }
        }
    }

    private func audioTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            if let start = secondsValue(model.backgroundMusicStart) {
                let musicDuration = secondsValue(model.backgroundMusicDuration) ?? max(0, duration - start)
                let end = min(duration, start + max(0.1, musicDuration))
                if !model.backgroundMusicPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, end > start {
                    timelineBlock(
                        title: "Music",
                        tint: .teal,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: true,
                        isSelected: false
                    )
                    .opacity(0.72)
                }
            }
            ForEach(model.audioVolumeRows) { region in
                if let start = secondsValue(region.startSeconds), let end = secondsValue(region.endSeconds), end > start {
                    timelineBlock(
                        title: "\(region.track.title) \(region.gain)x",
                        tint: .teal,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: region.isEnabled,
                        isSelected: selectedTimelineItem == .audioVolume(region.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .audioVolume(region.id)
                        editorInspectorTab = .audio
                    }
                    .gesture(timelineDragGesture(action: .moveAudioVolume, id: region.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeAudioVolumeStart, id: region.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeAudioVolumeEnd, id: region.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Volume Region") {
                            model.seek(to: start)
                        }
                        Button(region.isEnabled ? "Disable Region" : "Enable Region") {
                            model.toggleAudioVolumeRegionEnabled(id: region.id)
                            persistTimelineEditChanges(for: .moveAudioVolume)
                        }
                        Button("Remove Region", role: .destructive) {
                            model.removeAudioVolumeRegion(id: region.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveAudioVolume)
                        }
                    }
                }
            }
        }
    }

    private func speedTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.speedRows) { speed in
                if let start = secondsValue(speed.startSeconds), let end = secondsValue(speed.endSeconds), end > start {
                    timelineBlock(
                        title: "\(speed.playbackRate)x",
                        tint: .indigo,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: true,
                        isSelected: selectedTimelineItem == .speed(speed.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .speed(speed.id)
                        editorInspectorTab = .audio
                    }
                    .gesture(timelineDragGesture(action: .moveSpeed, id: speed.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeSpeedStart, id: speed.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeSpeedEnd, id: speed.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Speed Region") {
                            model.seek(to: start)
                        }
                        Button("Remove Region", role: .destructive) {
                            model.removeSpeedRegion(id: speed.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveSpeed)
                        }
                    }
                }
            }
        }
    }

    private func zoomTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.zoomRows) { zoom in
                if let start = secondsValue(zoom.startSeconds), let end = secondsValue(zoom.endSeconds), end > start {
                    timelineBlock(
                        title: "Zoom \(zoom.scale)x",
                        tint: .purple,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: zoom.isEnabled,
                        isSelected: selectedTimelineItem == .zoom(zoom.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .zoom(zoom.id)
                        editorInspectorTab = .zooms
                    }
                    .gesture(timelineDragGesture(action: .moveZoom, id: zoom.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeZoomStart, id: zoom.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeZoomEnd, id: zoom.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Zoom") {
                            model.seek(to: start)
                        }
                        Button(zoom.isEnabled ? "Disable Zoom" : "Enable Zoom") {
                            model.toggleZoomEnabled(id: zoom.id)
                            persistTimelineEditChanges(for: .moveZoom)
                        }
                        Button("Duplicate Zoom") {
                            model.duplicateZoom(id: zoom.id, duration: duration)
                            persistTimelineEditChanges(for: .moveZoom)
                        }
                        Button("Remove Zoom", role: .destructive) {
                            model.removeZoom(id: zoom.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveZoom)
                        }
                    }
                }
            }
        }
    }

    private func overlayTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.overlayRows) { overlay in
                if let start = secondsValue(overlay.startSeconds), let end = secondsValue(overlay.endSeconds), end > start {
                    timelineBlock(
                        title: overlay.kind.title,
                        tint: .green,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: overlay.isEnabled,
                        isSelected: selectedTimelineItem == .overlay(overlay.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .overlay(overlay.id)
                        editorInspectorTab = .overlays
                    }
                    .gesture(timelineDragGesture(action: .moveOverlay, id: overlay.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeOverlayStart, id: overlay.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeOverlayEnd, id: overlay.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Overlay") {
                            model.seek(to: start)
                        }
                        Button(overlay.isEnabled ? "Disable Overlay" : "Enable Overlay") {
                            model.toggleOverlayEnabled(id: overlay.id)
                            persistTimelineEditChanges(for: .moveOverlay)
                        }
                        Button("Remove Overlay", role: .destructive) {
                            model.removeOverlay(id: overlay.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveOverlay)
                        }
                    }
                }
            }
        }
    }

    private func captionTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.captionRows) { caption in
                if let start = secondsValue(caption.startSeconds), let end = secondsValue(caption.endSeconds), end > start {
                    timelineBlock(
                        title: caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Caption" : caption.text,
                        tint: .mint,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: true,
                        isSelected: selectedTimelineItem == .caption(caption.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .caption(caption.id)
                        editorInspectorTab = .captions
                    }
                    .gesture(timelineDragGesture(action: .moveCaption, id: caption.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCaptionStart, id: caption.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCaptionEnd, id: caption.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Caption") {
                            model.seek(to: start)
                        }
                        Button("Remove Caption", role: .destructive) {
                            model.removeCaption(id: caption.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveCaption)
                        }
                    }
                }
            }
        }
    }

    private func cameraTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.cameraRegionRows) { region in
                if let start = secondsValue(region.startSeconds), let end = secondsValue(region.endSeconds), end > start {
                    timelineBlock(
                        title: region.preset.title,
                        tint: .orange,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: region.isEnabled,
                        isSelected: selectedTimelineItem == .cameraRegion(region.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .cameraRegion(region.id)
                        editorInspectorTab = .camera
                    }
                    .gesture(timelineDragGesture(action: .moveCameraRegion, id: region.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCameraRegionStart, id: region.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCameraRegionEnd, id: region.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Camera Region") {
                            model.seek(to: start)
                        }
                        Button(region.isEnabled ? "Disable Region" : "Enable Region") {
                            model.toggleCameraRegionEnabled(id: region.id)
                            persistTimelineEditChanges(for: .moveCameraRegion)
                        }
                        Button("Remove Region", role: .destructive) {
                            model.removeCameraRegion(id: region.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveCameraRegion)
                        }
                    }
                }
            }
        }
    }

    private func cursorTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.cursorHiddenRangeRows) { range in
                if let start = secondsValue(range.startSeconds), let end = secondsValue(range.endSeconds), end > start {
                    timelineBlock(
                        title: "Hide pointer",
                        tint: .cyan,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: true,
                        isSelected: selectedTimelineItem == .cursorHide(range.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .cursorHide(range.id)
                        editorInspectorTab = .cursor
                    }
                    .gesture(timelineDragGesture(action: .moveCursorHide, id: range.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCursorHideStart, id: range.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCursorHideEnd, id: range.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Range") {
                            model.seek(to: start)
                        }
                        Button("Remove Range", role: .destructive) {
                            model.removeCursorHiddenRange(id: range.id)
                            selectedTimelineItem = nil
                            model.saveEditorSettings()
                        }
                    }
                }
            }
        }
    }

    private func markerTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.markerRows) { marker in
                if let seconds = secondsValue(marker.timeSeconds) {
                    let x = timelineX(seconds, width: width, duration: duration)
                    VStack(spacing: 2) {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                        Text(marker.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.blue)
                    .frame(width: 86, alignment: .leading)
                    .offset(x: max(76, min(width - 86, x)))
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill((selectedTimelineItem == .marker(marker.id) ? Color.blue.opacity(0.22) : Color.clear))
                    )
                    .onTapGesture {
                        selectedTimelineItem = .marker(marker.id)
                    }
                    .gesture(timelineDragGesture(action: .moveMarker, id: marker.id, start: seconds, end: seconds, width: width, duration: duration))
                    .contextMenu {
                        Button("Jump to Marker") {
                            model.seek(to: seconds)
                        }
                        Button("Duplicate Marker") {
                            model.duplicateMarker(id: marker.id, duration: duration)
                            persistTimelineEditChanges(for: .moveMarker)
                        }
                        Button("Remove Marker", role: .destructive) {
                            model.removeMarker(id: marker.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveMarker)
                        }
                    }
                }
            }
        }
    }

    private func timelineBlock(
        title: String,
        tint: Color,
        start: Double,
        end: Double,
        width: CGFloat,
        duration: Double,
        height: CGFloat,
        isEnabled: Bool,
        isSelected: Bool
    ) -> some View {
        let x = timelineX(start, width: width, duration: duration)
        let blockWidth = max(18, timelineX(end, width: width, duration: duration) - x)
        return Text(title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: blockWidth, height: height, alignment: .leading)
            .background(tint.opacity(isEnabled ? 0.78 : 0.28), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : tint.opacity(isEnabled ? 0.9 : 0.4), lineWidth: isSelected ? 2 : 1)
            )
            .foregroundStyle(.white)
            .offset(x: x)
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Rectangle())
    }

    private func playheadLine(width: CGFloat, duration: Double) -> some View {
        let x = timelineX(model.currentTimeSeconds, width: width, duration: duration)
        return VStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 292)
        }
        .offset(x: x)
    }

    private func trimHandle(_ title: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.94))
                .frame(width: 10, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.black.opacity(0.25), lineWidth: 1)
                )
        }
        .foregroundStyle(.black.opacity(0.75))
        .frame(width: 28, height: 38)
        .contentShape(Rectangle())
    }

    private func timelineResizeHandle() -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.88))
            .frame(width: 9)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.black.opacity(0.22), lineWidth: 1)
            )
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .help("Drag to resize")
    }

    private func timelineDragGesture(
        action: TimelineDragAction,
        id: String,
        start: Double,
        end: Double,
        width: CGFloat,
        duration: Double
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeTimelineDrag == nil {
                    activeTimelineDrag = TimelineDragState(
                        action: action,
                        id: id,
                        startSeconds: start,
                        endSeconds: end
                    )
                }
                guard let drag = activeTimelineDrag,
                      drag.action == action,
                      drag.id == id else {
                    return
                }
                applyTimelineDrag(drag, delta: timelineDeltaSeconds(value.translation.width, width: width, duration: duration), duration: duration)
            }
            .onEnded { _ in
                activeTimelineDrag = nil
                persistTimelineEditChanges(for: action)
            }
    }

    private func applyTimelineDrag(_ drag: TimelineDragState, delta: Double, duration: Double) {
        switch drag.action {
        case .trimStart:
            model.updateTrimStart(drag.startSeconds + delta, duration: duration)
        case .trimEnd:
            model.updateTrimEnd(drag.endSeconds + delta, duration: duration)
        case .moveCut:
            model.moveCut(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeCutStart:
            model.resizeCut(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeCutEnd:
            model.resizeCut(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveSpeed:
            model.moveSpeedRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeSpeedStart:
            model.resizeSpeedRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeSpeedEnd:
            model.resizeSpeedRegion(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveAudioVolume:
            model.moveAudioVolumeRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeAudioVolumeStart:
            model.resizeAudioVolumeRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeAudioVolumeEnd:
            model.resizeAudioVolumeRegion(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveZoom:
            model.moveZoom(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeZoomStart:
            model.resizeZoom(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeZoomEnd:
            model.resizeZoom(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveOverlay:
            model.moveOverlay(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeOverlayStart:
            model.resizeOverlay(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeOverlayEnd:
            model.resizeOverlay(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveCaption:
            model.moveCaption(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeCaptionStart:
            model.resizeCaption(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeCaptionEnd:
            model.resizeCaption(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveCameraRegion:
            model.moveCameraRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeCameraRegionStart:
            model.resizeCameraRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeCameraRegionEnd:
            model.resizeCameraRegion(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveCursorHide:
            model.moveCursorHiddenRange(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeCursorHideStart:
            model.resizeCursorHiddenRange(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeCursorHideEnd:
            model.resizeCursorHiddenRange(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveMarker:
            model.moveMarker(id: drag.id, to: drag.startSeconds + delta, duration: duration)
        }
    }

    private func persistTimelineEditChanges(for action: TimelineDragAction) {
        switch action {
        case .moveMarker:
            model.saveMarkers()
        case .moveOverlay, .resizeOverlayStart, .resizeOverlayEnd:
            model.saveOverlays()
        case .moveCaption, .resizeCaptionStart, .resizeCaptionEnd:
            model.saveCaptions()
        case .moveAudioVolume, .resizeAudioVolumeStart, .resizeAudioVolumeEnd:
            model.saveEditorSettings()
        case .moveCameraRegion, .resizeCameraRegionStart, .resizeCameraRegionEnd:
            model.saveEditorSettings()
        case .moveCursorHide, .resizeCursorHideStart, .resizeCursorHideEnd:
            model.saveEditorSettings()
        case .moveSpeed, .resizeSpeedStart, .resizeSpeedEnd:
            model.saveEditDecisions()
        default:
            model.saveEditDecisions()
        }
    }

    private func deleteSelectedTimelineItem() {
        guard let selectedTimelineItem else { return }
        switch selectedTimelineItem {
        case .cut(let id):
            model.removeCut(id: id)
            persistTimelineEditChanges(for: .moveCut)
        case .speed(let id):
            model.removeSpeedRegion(id: id)
            persistTimelineEditChanges(for: .moveSpeed)
        case .audioVolume(let id):
            model.removeAudioVolumeRegion(id: id)
            persistTimelineEditChanges(for: .moveAudioVolume)
        case .zoom(let id):
            model.removeZoom(id: id)
            persistTimelineEditChanges(for: .moveZoom)
        case .overlay(let id):
            model.removeOverlay(id: id)
            persistTimelineEditChanges(for: .moveOverlay)
        case .caption(let id):
            model.removeCaption(id: id)
            persistTimelineEditChanges(for: .moveCaption)
        case .cameraRegion(let id):
            model.removeCameraRegion(id: id)
            persistTimelineEditChanges(for: .moveCameraRegion)
        case .cursorHide(let id):
            model.removeCursorHiddenRange(id: id)
            persistTimelineEditChanges(for: .moveCursorHide)
        case .marker(let id):
            model.removeMarker(id: id)
            persistTimelineEditChanges(for: .moveMarker)
        }
        self.selectedTimelineItem = nil
    }

    private func timelineX(_ seconds: Double, width: CGFloat, duration: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        let trackWidth = max(0, width - timelineTrackInset)
        return timelineTrackInset + min(max(0, CGFloat(seconds / duration) * trackWidth), trackWidth)
    }

    private func timelineSeconds(_ x: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        let trackWidth = max(1, width - timelineTrackInset)
        let trackX = min(max(0, x - timelineTrackInset), trackWidth)
        return Double(trackX / trackWidth) * duration
    }

    private func timelineDeltaSeconds(_ translation: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        let trackWidth = max(1, width - timelineTrackInset)
        return Double(translation / trackWidth) * duration
    }

    private var timelineTrackInset: CGFloat { 76 }

    private func inspectorSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func compactNumberField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func numericStringSlider(
        _ title: String,
        text: Binding<String>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        let value = Binding<Double>(
            get: {
                let parsed = Double(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? range.lowerBound
                return min(max(parsed, range.lowerBound), range.upperBound)
            },
            set: { nextValue in
                text.wrappedValue = String(format: format, min(max(nextValue, range.lowerBound), range.upperBound))
            }
        )
        return labeledSlider(title, value: value, range: range, format: format)
    }

    private func colorPickerRow(_ title: String, selection: Binding<RGBAColor>) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            ForEach(canvasColorSwatches, id: \.self) { color in
                Button {
                    selection.wrappedValue = color
                } label: {
                    Circle()
                        .fill(Color(rgba: color))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(selection.wrappedValue == color ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: selection.wrappedValue == color ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var canvasColorSwatches: [RGBAColor] {
        [.black, .white, .purple, .blue, .cyan, .green, .amber, .pink]
    }

    @ViewBuilder private var canvasPreviewBackground: some View {
        switch model.canvasBackgroundStyle {
        case .none:
            Color.black
        case .solid:
            Color(rgba: model.canvasPrimaryColor)
        case .gradient:
            LinearGradient(
                colors: [Color(rgba: model.canvasPrimaryColor), Color(rgba: model.canvasSecondaryColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .image:
            if let image = model.canvasBackgroundImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
    }

    @ViewBuilder private var zoomFocusOverlay: some View {
        if let zoomID = selectedZoomID,
           let zoom = model.zoomRow(id: zoomID),
           let centerX = secondsValue(zoom.centerX),
           let centerY = secondsValue(zoom.centerY),
           let size = secondsValue(zoom.size) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)
                let boxWidth = max(40, width * CGFloat(size))
                let boxHeight = max(40, height * CGFloat(size))
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .frame(width: boxWidth, height: boxHeight)
                    .position(
                        x: min(max(CGFloat(centerX) * width, boxWidth / 2), width - boxWidth / 2),
                        y: min(max(CGFloat(centerY) * height, boxHeight / 2), height - boxHeight / 2)
                    )
                    .overlay(alignment: .topLeading) {
                        Text("\(zoom.scale)x")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                            .offset(x: 10, y: 10)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                model.updateZoomFocus(
                                    id: zoomID,
                                    centerX: Double(value.location.x / width),
                                    centerY: Double(value.location.y / height)
                                )
                            }
                            .onEnded { _ in
                                model.saveEditDecisions()
                            }
                    )
                    .help("Drag to move the selected zoom focus")
            }
            .allowsHitTesting(true)
        }
    }

    @ViewBuilder private var overlayPreviewOverlay: some View {
        if !model.overlayRows.isEmpty {
            GeometryReader { proxy in
                let contentFrame = previewContentFrame(in: proxy.size)
                ZStack(alignment: .topLeading) {
                    ForEach(model.overlayRows(at: model.currentTimeSeconds)) { overlay in
                        let frame = overlayPreviewFrame(overlay, in: contentFrame)
                        overlayPreview(overlay)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(selectedTimelineItem == .overlay(overlay.id) ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                            .overlay(alignment: .bottomTrailing) {
                                if selectedTimelineItem == .overlay(overlay.id) {
                                    overlayResizeHandle()
                                        .offset(x: 5, y: 5)
                                        .gesture(
                                            DragGesture(minimumDistance: 1)
                                                .onChanged { value in
                                                    if activeOverlayResizeDrag?.id != overlay.id {
                                                        activeOverlayResizeDrag = OverlayPreviewResizeDragState(
                                                            id: overlay.id,
                                                            startWidth: secondsValue(overlay.width) ?? 0.2,
                                                            startHeight: secondsValue(overlay.height) ?? 0.15
                                                        )
                                                    }
                                                    guard let drag = activeOverlayResizeDrag, drag.id == overlay.id else { return }
                                                    model.updateOverlayFrame(
                                                        id: overlay.id,
                                                        width: drag.startWidth + Double(value.translation.width / max(contentFrame.width, 1)),
                                                        height: drag.startHeight + Double(value.translation.height / max(contentFrame.height, 1))
                                                    )
                                                }
                                                .onEnded { _ in
                                                    activeOverlayResizeDrag = nil
                                                    model.saveOverlays()
                                                }
                                        )
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTimelineItem = .overlay(overlay.id)
                                editorInspectorTab = .overlays
                            }
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        if activeOverlayDrag?.id != overlay.id {
                                            activeOverlayDrag = OverlayPreviewDragState(
                                                id: overlay.id,
                                                startX: secondsValue(overlay.x) ?? 0,
                                                startY: secondsValue(overlay.y) ?? 0
                                            )
                                        }
                                        guard let drag = activeOverlayDrag, drag.id == overlay.id else { return }
                                        model.updateOverlayFrame(
                                            id: overlay.id,
                                            x: drag.startX + Double(value.translation.width / max(contentFrame.width, 1)),
                                            y: drag.startY + Double(value.translation.height / max(contentFrame.height, 1))
                                        )
                                    }
                                    .onEnded { _ in
                                        activeOverlayDrag = nil
                                        model.saveOverlays()
                                    }
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder private var captionPreviewOverlay: some View {
        if model.captionBurnInEnabled, let caption = model.activeCaption(at: model.currentTimeSeconds) {
            VStack {
                if model.captionPlacement == .bottom || model.captionPlacement == .middle {
                    Spacer()
                }
                Text(caption.text)
                    .font(.system(size: CGFloat(secondsValue(model.captionFontSize) ?? 34), weight: .bold))
                    .foregroundStyle(Color(rgba: model.captionTextColor))
                    .multilineTextAlignment(.center)
                    .lineLimit(model.captionMaxLineCount)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(rgba: model.captionBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 32)
                    .padding(.vertical, max(18, CGFloat((secondsValue(model.captionSafeMargin) ?? 0.07) * 360)))
                    .onTapGesture {
                        selectedTimelineItem = .caption(caption.id)
                        editorInspectorTab = .captions
                    }
                if model.captionPlacement == .top {
                    Spacer()
                }
                if model.captionPlacement == .middle {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
        }
    }

    @ViewBuilder private func overlayPreview(_ overlay: EditableOverlayRow) -> some View {
        switch overlay.kind {
        case .text:
            Text(overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Title" : overlay.text)
                .font(.system(size: CGFloat(secondsValue(overlay.fontSize) ?? 34), weight: .bold))
                .foregroundStyle(Color(rgba: overlay.textColor))
                .multilineTextAlignment(.center)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(rgba: overlay.fillColor), in: RoundedRectangle(cornerRadius: 8))
                .opacity(secondsValue(overlay.opacity) ?? 1)
        case .rectangle:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(rgba: overlay.fillColor).opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(rgba: overlay.strokeColor), lineWidth: 3))
                .opacity(secondsValue(overlay.opacity) ?? 1)
        case .ellipse:
            Ellipse()
                .fill(Color(rgba: overlay.fillColor).opacity(0.22))
                .overlay(Ellipse().stroke(Color(rgba: overlay.strokeColor), lineWidth: 3))
                .opacity(secondsValue(overlay.opacity) ?? 1)
        case .line, .arrow:
            GeometryReader { proxy in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height * 0.2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * 0.8))
                }
                .stroke(Color(rgba: overlay.strokeColor), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .overlay(alignment: .bottomTrailing) {
                    if overlay.kind == .arrow {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(Color(rgba: overlay.strokeColor))
                            .font(.headline.weight(.bold))
                    }
                }
            }
            .opacity(secondsValue(overlay.opacity) ?? 1)
        case .callout:
            Text(overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Callout" : overlay.text)
                .font(.system(size: CGFloat(secondsValue(overlay.fontSize) ?? 28), weight: .bold))
                .foregroundStyle(Color(rgba: overlay.textColor))
                .multilineTextAlignment(.center)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(rgba: overlay.fillColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(rgba: overlay.strokeColor), lineWidth: 2))
                .opacity(secondsValue(overlay.opacity) ?? 1)
        case .image:
            if let image = model.overlayImage(for: overlay) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .opacity(secondsValue(overlay.opacity) ?? 1)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.1))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        case .highlight:
            highlightPreview(overlay)
        }
    }

    private func overlayResizeHandle() -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.black.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Rectangle())
    }

    @ViewBuilder private func highlightPreview(_ overlay: EditableOverlayRow) -> some View {
        let opacity = secondsValue(overlay.opacity) ?? 0.6
        let stroke = Color(rgba: overlay.strokeColor)
        let fill = Color(rgba: overlay.fillColor)
        let cornerRadius = CGFloat(secondsValue(overlay.cornerRadius) ?? 12)
        switch overlay.highlightShape {
        case .ellipse:
            Ellipse()
                .fill(fill.opacity(overlay.highlightMode == .outline ? 0.03 : min(opacity, 0.28)))
                .overlay(Ellipse().stroke(stroke, style: StrokeStyle(lineWidth: 3, dash: overlay.highlightMode == .outline ? [] : [7, 4])))
                .shadow(color: stroke.opacity(overlay.highlightMode == .spotlight ? 0.45 : 0), radius: CGFloat(secondsValue(overlay.featherRadius) ?? 0))
        case .rectangle:
            Rectangle()
                .fill(fill.opacity(overlay.highlightMode == .outline ? 0.03 : min(opacity, 0.28)))
                .overlay(Rectangle().stroke(stroke, style: StrokeStyle(lineWidth: 3, dash: overlay.highlightMode == .outline ? [] : [7, 4])))
                .shadow(color: stroke.opacity(overlay.highlightMode == .spotlight ? 0.45 : 0), radius: CGFloat(secondsValue(overlay.featherRadius) ?? 0))
        case .roundedRectangle:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(fill.opacity(overlay.highlightMode == .outline ? 0.03 : min(opacity, 0.28)))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(stroke, style: StrokeStyle(lineWidth: 3, dash: overlay.highlightMode == .outline ? [] : [7, 4])))
                .shadow(color: stroke.opacity(overlay.highlightMode == .spotlight ? 0.45 : 0), radius: CGFloat(secondsValue(overlay.featherRadius) ?? 0))
        }
    }

    private func overlayPreviewFrame(_ overlay: EditableOverlayRow, in contentFrame: CGRect) -> CGRect {
        let x = CGFloat(secondsValue(overlay.x) ?? 0)
        let y = CGFloat(secondsValue(overlay.y) ?? 0)
        let width = CGFloat(secondsValue(overlay.width) ?? 0.2)
        let height = CGFloat(secondsValue(overlay.height) ?? 0.15)
        return CGRect(
            x: contentFrame.minX + x * contentFrame.width,
            y: contentFrame.minY + y * contentFrame.height,
            width: max(20, width * contentFrame.width),
            height: max(20, height * contentFrame.height)
        )
    }

    @ViewBuilder private var cursorPreviewOverlay: some View {
        if model.cursorPreviewMetadata != nil {
            GeometryReader { proxy in
                let contentFrame = previewContentFrame(in: proxy.size)
                ZStack {
                    if model.cursorClickEffectsVisible,
                       let click = model.cursorClick(at: model.currentTimeSeconds) {
                        let point = previewPoint(click.position, in: contentFrame)
                        let progress = model.cursorClickProgress(click, at: model.currentTimeSeconds)
                        let ringSize = CGFloat(36 * model.cursorClickScale * (0.65 + progress))
                        Circle()
                            .stroke(Color(rgba: model.cursorClickColor).opacity(model.cursorClickOpacity * (1 - progress)), lineWidth: 3)
                            .frame(width: ringSize, height: ringSize)
                            .position(point)
                    }

                    if model.cursorPointerVisible,
                       let sample = model.cursorSample(at: model.currentTimeSeconds) {
                        cursorPointerPreview(style: model.cursorPointerStyle)
                            .scaleEffect(model.cursorPointerScale)
                            .position(previewPoint(sample.position, in: contentFrame))
                    }

                    if model.cursorKeyboardVisible,
                       let label = model.keyboardPreviewLabel(at: model.currentTimeSeconds) {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.82 * model.cursorKeyboardOpacity), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                            .position(x: contentFrame.midX, y: max(contentFrame.minY + 32, contentFrame.maxY - 34))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func cursorPointerPreview(style: EditorCursorPointerStyle) -> some View {
        switch style {
        case .macOS:
            Image(systemName: "cursorarrow")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color(rgba: model.cursorPointerFillColor))
                .shadow(color: Color(rgba: model.cursorPointerStrokeColor).opacity(0.95), radius: 1.6)
        case .touchDot:
            Circle()
                .fill(Color(rgba: model.cursorPointerFillColor).opacity(0.92))
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(Color(rgba: model.cursorPointerStrokeColor).opacity(0.95), lineWidth: 2)
                )
        }
    }

    private func previewContentFrame(in size: CGSize) -> CGRect {
        let padding = model.canvasPreviewPadding
        let availableWidth = max(1, size.width - padding * 2)
        let availableHeight = max(1, size.height - padding * 2)
        let aspectRatio = model.canvasPreviewAspectRatio ?? (availableWidth / max(availableHeight, 1))
        let availableRatio = availableWidth / max(availableHeight, 1)
        let contentSize: CGSize
        if availableRatio > aspectRatio {
            let height = availableHeight
            contentSize = CGSize(width: height * aspectRatio, height: height)
        } else {
            let width = availableWidth
            contentSize = CGSize(width: width, height: width / max(aspectRatio, 0.01))
        }
        return CGRect(
            x: padding + (availableWidth - contentSize.width) / 2,
            y: padding + (availableHeight - contentSize.height) / 2,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    private func previewPoint(_ point: NormalizedCapturePoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + CGFloat(point.x) * frame.width,
            y: frame.minY + (1 - CGFloat(point.y)) * frame.height
        )
    }

    private var selectedZoomID: String? {
        if case .zoom(let id) = selectedTimelineItem {
            return id
        }
        return nil
    }

    private func valueLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
    }

    private func projectHeader(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        let status = overviewStatus(summary: summary, manifest: manifest)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(manifest.metadata.lessonTitle)
                        .font(.largeTitle.weight(.semibold))
                    Text(projectSubtitle(manifest))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                statusPill(status.title, systemImage: status.systemImage, tint: status.tint)
            }

            HStack(spacing: 10) {
                if let projectURL = model.projectURL {
                    Label(projectURL.path, systemImage: "folder")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                Button {
                    model.revealProject()
                } label: {
                    Label("Reveal", systemImage: "arrow.up.forward.app")
                }
                .disabled(model.projectURL == nil)
            }
        }
    }

    private func lessonOverviewPanel(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                nextStepCard(summary: summary, manifest: manifest)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                readinessCard(summary: summary, manifest: manifest)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 16) {
                nextStepCard(summary: summary, manifest: manifest)
                readinessCard(summary: summary, manifest: manifest)
            }
        }
    }

    private func nextStepCard(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        let status = overviewStatus(summary: summary, manifest: manifest)
        let hasScreen = manifest.media.screen != nil
        let hasBlockingIssues = hasBlockingIssues(summary)

        return DashboardCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: status.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(status.tint)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Next Step")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(status.title)
                        .font(.title2.weight(.semibold))
                    Text(status.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        if !hasScreen {
                            Button {
                                quickRecorder.presentControlBar(preferences: preferences)
                            } label: {
                                Label("Open Recorder", systemImage: "record.circle")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                model.importVideoForEditing(preferences.snapshot)
                            } label: {
                                Label("Import Video", systemImage: "film")
                            }

                            Button {
                                appRouter.openSettings(.capture)
                            } label: {
                                Label("Check Defaults", systemImage: "gearshape")
                            }
                        } else if hasBlockingIssues {
                            Button {
                                showTechnicalDetails = true
                            } label: {
                                Label("Show Issues", systemImage: "exclamationmark.triangle")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                model.revealProject()
                            } label: {
                                Label("Reveal Bundle", systemImage: "folder")
                            }
                        } else {
                            Button {
                                model.togglePlayback()
                            } label: {
                                Label(model.isPlaying ? "Pause Preview" : "Play Preview", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                model.inspectRender(preferences.snapshot)
                            } label: {
                                Label("Check Render", systemImage: "checkmark.seal")
                            }

                            Button {
                                model.packageLearnHouse(preferences.snapshot)
                            } label: {
                                Label(model.isPackagingLearnHouse ? "Packaging..." : "Package LearnHouse", systemImage: "shippingbox")
                            }
                            .disabled(model.isPackagingLearnHouse || manifest.media.screen == nil)
                        }
                    }
                }
            }
        }
    }

    private func readinessCard(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lesson Readiness")
                    .font(.headline)
                readinessLine(
                    "Screen Video",
                    status: manifest.media.screen == nil ? "Needed" : "Ready",
                    detail: manifest.media.screen?.relativePath ?? "Record a take or import an existing video.",
                    systemImage: "display",
                    tint: manifest.media.screen == nil ? .orange : .green
                )
                readinessLine(
                    "Voice",
                    status: audioStatus(manifest),
                    detail: audioDetail(manifest),
                    systemImage: "waveform",
                    tint: hasAudio(manifest) ? .green : .secondary
                )
                readinessLine(
                    "Webcam",
                    status: manifest.media.webcam == nil ? "Optional" : "Captured",
                    detail: manifest.media.webcam?.relativePath ?? "Add a camera track when presenter presence matters.",
                    systemImage: "video",
                    tint: manifest.media.webcam == nil ? .secondary : .green
                )
                readinessLine(
                    "Review",
                    status: reviewStatus(manifest),
                    detail: reviewDetail(manifest),
                    systemImage: "film.stack",
                    tint: manifest.media.screen == nil ? .secondary : .blue
                )
                readinessLine(
                    "Export",
                    status: exportStatus(summary, manifest: manifest),
                    detail: exportDetail(summary, manifest: manifest),
                    systemImage: "square.and.arrow.up",
                    tint: exportTint(summary, manifest: manifest)
                )
            }
        }
    }

    private func statusPill(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 1))
    }

    private func readinessLine(_ title: String, status: String, detail: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
    }

    private func overviewStatus(
        summary: ProjectBundleSummary,
        manifest: ProjectManifest
    ) -> (title: String, detail: String, systemImage: String, tint: Color) {
        if manifest.media.screen == nil {
            return (
                "Add video",
                "This bundle has lesson structure, but no screen video yet. Record a take or import an existing video to start editing.",
                "record.circle",
                .orange
            )
        }

        if hasBlockingIssues(summary) {
            return (
                "Fix project issues",
                "The recording exists, but the bundle has a blocking issue before it can render cleanly.",
                "xmark.octagon",
                .red
            )
        }

        if !summary.issues.isEmpty {
            return (
                "Check warnings",
                "The recording can be reviewed, but there are warnings worth checking before export.",
                "exclamationmark.triangle",
                .orange
            )
        }

        if model.cutRows.isEmpty && model.zoomRows.isEmpty && model.annotationItemCount == 0 {
            return (
                "Review the recording",
                "Preview the take, trim dead air, add zooms where focus matters, and open annotations when you need callouts.",
                "play.rectangle",
                .blue
            )
        }

        return (
            "Ready to render",
            "The lesson has media and review edits. Export a video or package the lesson for LearnHouse.",
            "checkmark.seal.fill",
            .green
        )
    }

    private func projectSubtitle(_ manifest: ProjectManifest) -> String {
        let courseParts = [manifest.metadata.courseTitle, manifest.metadata.moduleTitle]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        if !courseParts.isEmpty {
            return courseParts.joined(separator: " / ")
        }

        let summary = manifest.metadata.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !summary.isEmpty {
            return summary
        }

        return "Local lesson bundle ready for recording, review, and export."
    }

    private func hasBlockingIssues(_ summary: ProjectBundleSummary) -> Bool {
        summary.issues.contains { $0.severity == .error }
    }

    private func hasAudio(_ manifest: ProjectManifest) -> Bool {
        manifest.media.microphoneAudio != nil || manifest.media.systemAudio != nil
    }

    private func audioStatus(_ manifest: ProjectManifest) -> String {
        if manifest.media.microphoneAudio != nil, manifest.media.systemAudio != nil {
            return "Mic + System"
        }
        if manifest.media.microphoneAudio != nil {
            return "Mic"
        }
        if manifest.media.systemAudio != nil {
            return "System"
        }
        return "Optional"
    }

    private func audioDetail(_ manifest: ProjectManifest) -> String {
        let files = [manifest.media.microphoneAudio?.relativePath, manifest.media.systemAudio?.relativePath].compactMap { $0 }
        return files.isEmpty ? "No voice or system audio has been captured yet." : files.joined(separator: " + ")
    }

    private func reviewStatus(_ manifest: ProjectManifest) -> String {
        guard manifest.media.screen != nil else { return "Waiting" }
        if model.cutRows.isEmpty && model.zoomRows.isEmpty && model.annotationItemCount == 0 {
            return "Ready"
        }
        return "Edited"
    }

    private func reviewDetail(_ manifest: ProjectManifest) -> String {
        guard manifest.media.screen != nil else { return "Record or import video first, then review the take." }

        let pieces = [
            countLabel(model.cutRows.filter(\.isEnabled).count, singular: "cut"),
            countLabel(model.zoomRows.filter(\.isEnabled).count, singular: "zoom"),
            countLabel(model.annotationItemCount, singular: "annotation")
        ].filter { !$0.hasPrefix("0 ") }

        return pieces.isEmpty ? "Preview, cut retakes, add zooms, and mark important moments." : pieces.joined(separator: ", ")
    }

    private func exportStatus(_ summary: ProjectBundleSummary, manifest: ProjectManifest) -> String {
        if manifest.media.screen == nil { return "Waiting" }
        if hasBlockingIssues(summary) { return "Blocked" }
        if !summary.issues.isEmpty { return "Check" }
        return "Ready"
    }

    private func exportDetail(_ summary: ProjectBundleSummary, manifest: ProjectManifest) -> String {
        if manifest.media.screen == nil {
            return "Export unlocks after recording or importing video."
        }
        if hasBlockingIssues(summary) {
            return "Resolve bundle errors before rendering."
        }
        if !summary.issues.isEmpty {
            return "Warnings are visible in technical details."
        }
        return "Video export and LearnHouse packaging are available."
    }

    private func exportTint(_ summary: ProjectBundleSummary, manifest: ProjectManifest) -> Color {
        if manifest.media.screen == nil { return .gray }
        if hasBlockingIssues(summary) { return .red }
        if !summary.issues.isEmpty { return .orange }
        return .green
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
    }

    private func openAnnotationOverlayFromEditor() {
        let storeURL = model.projectURL == nil ? nil : model.prepareAnnotationSidecarForOverlay()
        annotationOverlay.open(preferences: preferences.snapshot, annotationStoreURL: storeURL, forceToolbarVisible: true)
    }

    private var firstRunDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showRecoveryNotice {
                recoveryNotice
            }

            startLessonPanel

            HStack(alignment: .top, spacing: 16) {
                workflowPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                appToolsPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var recoveryNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Recovered From Previous Crash")
                    .font(.headline)
                Text("LessonMeld skipped launch-time overlays and extra windows this time. Open tools manually after the main window is stable.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Dismiss") {
                showRecoveryNotice = false
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    private var startLessonPanel: some View {
        EditorPanel(title: "Start a Lesson", subtitle: "Record into a local lesson project, or import an existing video and edit it immediately.") {
            HStack(spacing: 10) {
                Button {
                    quickRecorder.presentControlBar(preferences: preferences)
                } label: {
                    Label(quickRecorder.isRecording ? "Show Recorder" : "Record Lesson", systemImage: quickRecorder.isRecording ? "slider.horizontal.3" : "record.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.importVideoForEditing(preferences.snapshot)
                } label: {
                    Label("Edit Video", systemImage: "film")
                }

                Button {
                    model.newProject(preferences.snapshot)
                } label: {
                    Label("New Project...", systemImage: "doc.badge.plus")
                }

                Button {
                    model.openProject()
                } label: {
                    Label("Open Lesson", systemImage: "folder")
                }

                if quickRecorder.isRecording {
                    Button(quickRecorder.isPaused ? "Resume" : "Pause") {
                        quickRecorder.togglePause()
                    }
                    Button("Stop") {
                        quickRecorder.stopRecording()
                    }
                }
            }

            if quickRecorder.isRecording || quickRecorder.isStopping {
                HStack(spacing: 8) {
                    Circle()
                        .fill(quickRecorder.isStopping ? Color.secondary : (quickRecorder.isPaused ? Color.orange : Color.red))
                        .frame(width: 8, height: 8)
                    Text(quickRecorder.isStopping ? "Stopping..." : "Recording \(quickRecorder.formattedElapsed)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                }
                .foregroundStyle(.secondary)
            } else if let projectPath = quickRecorder.lastProjectPath {
                HStack(spacing: 10) {
                    Button {
                        model.loadProject(URL(fileURLWithPath: projectPath))
                    } label: {
                        Label("Review Last Lesson", systemImage: "film.stack")
                    }
                    Text(URL(fileURLWithPath: projectPath).lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("Edit Video imports an MP4 or MOV into a local lesson bundle and opens the editor for preview, cuts, zooms, trims, annotations, and export.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var workflowPanel: some View {
        EditorPanel(title: "Workflow", subtitle: "The normal path for a curriculum lesson.") {
            VStack(alignment: .leading, spacing: 10) {
                workflowRow("Set Up", "Permissions and defaults", systemImage: "checklist") {
                    openWindow(id: "onboarding")
                    NSApplication.shared.activate()
                }
                workflowRow("Record", "Screen, webcam, mic, and optional system audio", systemImage: "record.circle") {
                    quickRecorder.presentControlBar(preferences: preferences)
                }
                workflowRow("Edit Video", "Import or open media, then cut, trim, zoom, annotate, and export", systemImage: "film") {
                    model.importVideoForEditing(preferences.snapshot)
                }
                workflowRow("Review", "Preview playback and check the lesson before export", systemImage: "film.stack") {
                    model.openProject()
                }
                workflowRow("Render", "Export video or package for LearnHouse", systemImage: "shippingbox") {
                    appRouter.openSettings(.export)
                }
            }
        }
    }

    private var appToolsPanel: some View {
        EditorPanel(title: "App Tools", subtitle: "Setup, preferences, commands, and live annotation are always local.") {
            VStack(alignment: .leading, spacing: 10) {
                permissionRow("Screen", isGranted: quickRecorder.screenGranted)
                permissionRow("Mic", isGranted: quickRecorder.microphoneGranted)
                permissionRow("Camera", isGranted: quickRecorder.cameraGranted)

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        appToolButtons
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        appToolButtons
                    }
                }
            }
        }
    }

    private var appToolButtons: some View {
        Group {
            Button {
                appRouter.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Button {
                openWindow(id: "onboarding")
                NSApplication.shared.activate()
            } label: {
                Label("Onboarding", systemImage: "checklist")
            }

            Button {
                openWindow(id: "command-palette")
                NSApplication.shared.activate()
            } label: {
                Label("Commands", systemImage: "command")
            }

            Button {
                if annotationOverlay.isPresented {
                    annotationOverlay.close()
                } else {
                    openAnnotationOverlayFromEditor()
                }
            } label: {
                Label(annotationOverlay.isPresented ? "Close Tools" : "Annotate", systemImage: "paintpalette")
            }
        }
    }

    private func workflowRow(_ title: String, _ detail: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func permissionRow(_ title: String, isGranted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(isGranted ? "Ready" : "Needs Access")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isGranted ? .green : .orange)
        }
    }

    private var emptyState: some View {
        EditorPanel(title: "Create or Open a Lesson Project", subtitle: "The editor works directly against local lesson bundles.") {
            HStack {
                Button {
                    model.importVideoForEditing(preferences.snapshot)
                } label: {
                    Label("Edit Video...", systemImage: "film")
                }

                Button {
                    model.newProject(preferences.snapshot)
                } label: {
                    Label("New Project...", systemImage: "doc.badge.plus")
                }

                Button {
                    model.openProject()
                } label: {
                    Label("Open Lesson...", systemImage: "folder")
                }
            }
            Text("Importing a video creates a local lesson bundle with the media ready for preview, cuts, zooms, trims, annotations, and export.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recorderEntryPanel: some View {
        EditorPanel(title: "Record a Lesson", subtitle: "Open the floating recorder to choose display, window, area, camera, microphone, and system audio.") {
            HStack(spacing: 10) {
                Button {
                    quickRecorder.presentControlBar(preferences: preferences)
                } label: {
                    Label(quickRecorder.isRecording ? "Show Controls" : "New Recording...", systemImage: quickRecorder.isRecording ? "slider.horizontal.3" : "record.circle")
                }

                if quickRecorder.isRecording {
                    Button(quickRecorder.isPaused ? "Resume" : "Pause") {
                        quickRecorder.togglePause()
                    }

                    Button("Stop") {
                        quickRecorder.stopRecording()
                    }
                }
            }

            if quickRecorder.isRecording || quickRecorder.isStopping {
                HStack(spacing: 8) {
                    Circle()
                        .fill(quickRecorder.isPaused ? Color.orange : Color.red)
                        .frame(width: 8, height: 8)
                    Text(quickRecorder.isStopping ? "Stopping..." : "Recording \(quickRecorder.formattedElapsed)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                }
                .foregroundStyle(.secondary)
            } else {
                Text("Recording continues until you press Stop. Auto-stop, countdown, region size, and notes live behind the recorder gear.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let projectPath = quickRecorder.lastProjectPath {
                Divider()
                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: projectPath)])
                    } label: {
                        Label("Reveal Lesson Bundle", systemImage: "arrow.up.forward.app")
                    }

                    Text(URL(fileURLWithPath: projectPath).lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var recordPanel: some View {
        EditorPanel(title: "Record Lesson", subtitle: "Use the floating recorder for display, window, area, camera, microphone, and system audio.") {
            HStack(spacing: 10) {
                Button {
                    quickRecorder.presentControlBar(preferences: preferences)
                } label: {
                    Label(quickRecorder.isRecording ? "Show Recording Controls" : "New Recording...", systemImage: quickRecorder.isRecording ? "slider.horizontal.3" : "record.circle")
                }

                if quickRecorder.isRecording {
                    Button(quickRecorder.isPaused ? "Resume" : "Pause") {
                        quickRecorder.togglePause()
                    }

                    Button("Stop") {
                        quickRecorder.stopRecording()
                    }
                }
            }

            if quickRecorder.isRecording || quickRecorder.isStopping {
                HStack(spacing: 8) {
                    Circle()
                        .fill(quickRecorder.isStopping ? Color.secondary : (quickRecorder.isPaused ? Color.orange : Color.red))
                        .frame(width: 8, height: 8)
                    Text(quickRecorder.isStopping ? "Stopping..." : "Recording \(quickRecorder.formattedElapsed)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                }
                .foregroundStyle(.secondary)
            } else {
                Text("Recordings continue until you press Stop, then open in the editor as local lesson bundles.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let projectPath = quickRecorder.lastProjectPath {
                Divider()
                HStack(spacing: 10) {
                    Button {
                        model.loadProject(URL(fileURLWithPath: projectPath))
                    } label: {
                        Label("Review Last Lesson", systemImage: "film.stack")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: projectPath)])
                    } label: {
                        Label("Reveal", systemImage: "arrow.up.forward.app")
                    }

                    Text(URL(fileURLWithPath: projectPath).lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func projectSummary(_ summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Project", subtitle: "Manifest and validation status.") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                valueRow("Schema", "\(summary.schemaVersion)")
                valueRow("Files", "\(summary.fileCount)")
                valueRow("Markers", "\(summary.markerCount)")
                valueRow("Course", manifest.metadata.courseTitle ?? "None")
                valueRow("Tracks", "\(manifest.tracks.count)")
                valueRow("Issues", summary.issues.isEmpty ? "None" : "\(summary.issues.count)")
            }

            ForEach(summary.issues.indices, id: \.self) { index in
                issueRow(summary.issues[index].severity.rawValue, summary.issues[index].message, path: summary.issues[index].path)
            }
        }
    }

    private func lessonMarkersPanel(manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Markers", subtitle: "Plan chapters before recording, flag moments while recording, or clean up the lesson outline after review.") {
            HStack(spacing: 10) {
                Toggle("Show marker list", isOn: $showLessonMarkers)
                    .toggleStyle(.checkbox)

                Spacer()

                Button {
                    model.addMarkerAtPlayhead()
                    showLessonMarkers = true
                } label: {
                    Label(manifest.media.screen == nil ? "Add Marker" : "Add at Playhead", systemImage: "flag")
                }

                Button {
                    model.saveMarkers()
                } label: {
                    Label("Save Markers", systemImage: "checkmark.circle")
                }
                .disabled(model.projectURL == nil)
            }

            if showLessonMarkers {
                if model.markerRows.isEmpty {
                    Text("No markers yet. Add a chapter, retake, note, or segment marker when there is a point you want to find again.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("Time").foregroundStyle(.secondary)
                            Text("Type").foregroundStyle(.secondary)
                            Text("Title").foregroundStyle(.secondary)
                            Text("Notes").foregroundStyle(.secondary)
                            Text("").accessibilityHidden(true)
                        }

                        ForEach($model.markerRows) { $marker in
                            GridRow {
                                TextField("Time", text: $marker.timeSeconds)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 98)

                                Picker("Type", selection: $marker.kind) {
                                    ForEach(ProjectTimelineMarkerKind.allCases, id: \.self) { kind in
                                        Text(markerKindLabel(kind)).tag(kind)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 140)

                                TextField("Title", text: $marker.title)
                                    .textFieldStyle(.roundedBorder)

                                TextField("Notes", text: $marker.notes)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    model.removeMarker(id: marker.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("Markers are hidden for free-form review. Existing markers stay in the project and exports can still use them.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func markerKindLabel(_ kind: ProjectTimelineMarkerKind) -> String {
        switch kind {
        case .chapter:
            "Chapter"
        case .retake:
            "Retake"
        case .presenterNote:
            "Note"
        case .segment:
            "Segment"
        }
    }

    private var metadataPanel: some View {
        EditorPanel(title: "Lesson Details", subtitle: "These labels appear in exports, LearnHouse packages, and agent manifests.") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Lesson").foregroundStyle(.secondary)
                    TextField("Lesson title", text: $model.metadataLessonTitle)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Course").foregroundStyle(.secondary)
                    TextField("Course title", text: $model.metadataCourseTitle)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Module").foregroundStyle(.secondary)
                    TextField("Module title", text: $model.metadataModuleTitle)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Instructor").foregroundStyle(.secondary)
                    TextField("Instructor", text: $model.metadataInstructor)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Tags").foregroundStyle(.secondary)
                    TextField("workshop, curriculum, onboarding", text: $model.metadataTags)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Summary")
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.metadataSummary)
                    .font(.body)
                    .frame(minHeight: 76)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }

            Button {
                model.saveMetadata()
            } label: {
                Label("Save Lesson Details", systemImage: "checkmark.circle")
            }
            .disabled(model.projectURL == nil)
        }
    }

    private func annotationProjectPanel(manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Annotations", subtitle: "Open the live overlay for callouts, whiteboard work, and saved lesson notes.") {
            HStack(spacing: 10) {
                Button {
                    openAnnotationOverlayFromEditor()
                } label: {
                    Label(annotationOverlay.isPresented ? "Show Annotation Tools" : "Open Annotation Tools", systemImage: "paintpalette")
                }
                .buttonStyle(.borderedProminent)

                if annotationOverlay.isPresented {
                    Button {
                        annotationOverlay.close()
                    } label: {
                        Label("Close Tools", systemImage: "xmark")
                    }
                }
            }

            HStack(spacing: 12) {
                statusPill(annotationSaveStatus(manifest), systemImage: manifest.media.annotations == nil ? "circle" : "checkmark.circle", tint: manifest.media.annotations == nil ? .gray : .green)
                Text(countLabel(model.annotationItemCount, singular: "saved annotation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(annotationOverlay.isPresented ? "Overlay is open. Use the floating toolbar, then close it when finished." : "Opening the tools will save annotations with this lesson automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func annotationSaveStatus(_ manifest: ProjectManifest) -> String {
        manifest.media.annotations == nil ? "Not saved yet" : model.annotationSidecarStatus
    }

    private func previewPanel(manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Preview", subtitle: "Screen recording playback and timeline scrubber.") {
            if manifest.media.screen == nil {
                Text("This project does not reference a screen recording yet.")
                    .foregroundStyle(.secondary)
            } else if let player = model.player {
                ProjectVideoPlayer(player: player)
                    .frame(height: 360)
                    .background(.black, in: RoundedRectangle(cornerRadius: 8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 12) {
                    Button {
                        model.togglePlayback()
                    } label: {
                        Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                    }

                    Text(model.formattedCurrentTime)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { model.currentTimeSeconds },
                            set: { model.seek(to: $0) }
                        ),
                        in: 0...max(model.previewDurationSeconds, 1)
                    )

                    Text(model.formattedDuration)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)
                }

                HStack {
                    Button("Set Trim Start") {
                        model.setTrimStartToPlayhead()
                    }
                    Button("Set Trim End") {
                        model.setTrimEndToPlayhead()
                    }
                    Button("Add 5s Cut") {
                        model.addCutAtPlayhead()
                    }
                    Button("Copy Frame") {
                        model.copyCurrentFrame()
                    }
                    Button("Export Frame...") {
                        model.exportCurrentFrame()
                    }
                }
            } else {
                Text("Preview will load after the project screen video is available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cutListPanel(manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Cuts", subtitle: "Save project-local edit decisions for retakes and cleanup cuts.") {
            if manifest.media.screen == nil {
                Text("Cuts need a screen source.")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Add Cut") {
                        model.addCutAtPlayhead()
                    }
                    Button("Save Edit Decisions") {
                        model.saveEditDecisions()
                    }
                    Button(model.isTrimming ? "Exporting..." : "Export Cut List") {
                        model.exportEditDecisions()
                    }
                    .disabled(model.isTrimming || model.projectURL == nil)
                    Button("Reload") {
                        model.reloadEditDecisions()
                    }
                    Spacer()
                    Text("\(model.cutRows.filter(\.isEnabled).count) enabled / \(model.cutRows.count) total")
                        .foregroundStyle(.secondary)
                }

                if model.cutRows.isEmpty {
                    Text("No cuts yet. Scrub to a retake or dead spot and add a cut.")
                        .foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("On").foregroundStyle(.secondary)
                            Text("Start").foregroundStyle(.secondary)
                            Text("End").foregroundStyle(.secondary)
                            Text("Reason").foregroundStyle(.secondary)
                            Text("").accessibilityHidden(true)
                        }

                        ForEach($model.cutRows) { $cut in
                            GridRow {
                                Toggle("", isOn: $cut.isEnabled)
                                    .labelsHidden()
                                TextField("Start", text: $cut.startSeconds)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 90)
                                TextField("End", text: $cut.endSeconds)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 90)
                                TextField("Reason", text: $cut.reason)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    model.removeCut(id: cut.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !model.editValidationIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.editValidationIssues.indices, id: \.self) { index in
                            let issue = model.editValidationIssues[index]
                            issueRow(issue.severity.rawValue, issue.message, path: issue.path)
                        }
                    }
                }
            }
        }
    }

    private func zoomRegionPanel(manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Zoom Regions", subtitle: "Burn simple presenter-friendly zooms into the full render.") {
            if manifest.media.screen == nil {
                Text("Zoom regions need a screen source.")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Add Zoom") {
                        model.addZoomAtPlayhead()
                    }
                    Button("Save Edit Decisions") {
                        model.saveEditDecisions()
                    }
                    Button("Reload") {
                        model.reloadEditDecisions()
                    }
                    Spacer()
                    Text("\(model.zoomRows.filter(\.isEnabled).count) enabled / \(model.zoomRows.count) total")
                        .foregroundStyle(.secondary)
                }

                if model.zoomRows.isEmpty {
                    Text("No zooms yet. Scrub to an important area and add a zoom region.")
                        .foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("On").foregroundStyle(.secondary)
                            Text("Start").foregroundStyle(.secondary)
                            Text("End").foregroundStyle(.secondary)
                            Text("Scale").foregroundStyle(.secondary)
                            Text("X").foregroundStyle(.secondary)
                            Text("Y").foregroundStyle(.secondary)
                            Text("Size").foregroundStyle(.secondary)
                            Text("").accessibilityHidden(true)
                        }

                        ForEach($model.zoomRows) { $zoom in
                            GridRow {
                                Toggle("", isOn: $zoom.isEnabled)
                                    .labelsHidden()
                                zoomField("Start", text: $zoom.startSeconds)
                                zoomField("End", text: $zoom.endSeconds)
                                zoomField("Scale", text: $zoom.scale)
                                zoomField("X", text: $zoom.centerX)
                                zoomField("Y", text: $zoom.centerY)
                                zoomField("Size", text: $zoom.size)
                                Button {
                                    model.removeZoom(id: zoom.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func renderPanel(manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Render & Package", subtitle: "Create the final lesson video or package the project for LearnHouse.") {
            HStack(spacing: 12) {
                Picker("Quality", selection: $model.renderQuality) {
                    ForEach(RenderQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue.capitalized).tag(quality)
                    }
                }
                Picker("File", selection: $model.renderFileType) {
                    ForEach(RenderFileType.allCases, id: \.self) { fileType in
                        Text(fileType.rawValue.uppercased()).tag(fileType)
                    }
                }
            }

            HStack {
                TextField("Destination", text: $model.renderDestinationPath)
                    .font(.system(.body, design: .monospaced))
                Button("Choose...") {
                    model.chooseRenderDestination()
                }
            }

            HStack {
                Button("Check Readiness") {
                    model.inspectRender(preferences.snapshot)
                }
                Button(model.isRendering ? "Rendering..." : "Export Render") {
                    model.exportRender(preferences.snapshot)
                }
                .disabled(model.isRendering || model.projectURL == nil)
                Button("Cancel") {
                    model.cancelRender()
                }
                .disabled(!model.isRendering)
                Button(model.isPackagingLearnHouse ? "Packaging..." : "Package LearnHouse") {
                    model.packageLearnHouse(preferences.snapshot)
                }
                .disabled(model.isPackagingLearnHouse || manifest.media.screen == nil)
            }

            if model.isRendering {
                HStack {
                    ProgressView(value: model.renderProgress)
                        .frame(maxWidth: 280)
                    Text("\(Int((model.renderProgress * 100).rounded()))%")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)
                }
            }

            if let inspection = model.renderInspection {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    valueRow("Webcam PiP", inspection.hasWebcamOverlay ? "Yes" : "No")
                    valueRow("Cursor Effects", inspection.hasCursorEffects ? "Yes" : "No")
                    valueRow("Overlays", inspection.hasOverlays ? "Yes" : "No")
                    valueRow("Annotations", inspection.hasAnnotations ? "Yes" : "No")
                    valueRow("Captions", inspection.hasCaptions ? "Yes" : "No")
                    valueRow("Zoom Regions", inspection.hasZoomRegions ? "Yes" : "No")
                    valueRow("Audio Sources", "\(inspection.audioSourceCount)")
                    valueRow("Render Issues", inspection.issues.isEmpty ? "None" : "\(inspection.issues.count)")
                }

                ForEach(inspection.issues.indices, id: \.self) { index in
                    issueRow(inspection.issues[index].severity.rawValue, inspection.issues[index].message, path: inspection.issues[index].path)
                }
            }
        }
    }

    private func trimPanel(manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Trim Export", subtitle: "Create a contiguous teaching cut from the screen recording.") {
            if manifest.media.screen == nil {
                Text("This project does not reference a screen video.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    TextField("Start seconds", text: $model.trimStartSeconds)
                        .textFieldStyle(.roundedBorder)
                    TextField("End seconds", text: $model.trimEndSeconds)
                        .textFieldStyle(.roundedBorder)
                    TextField("Source duration", text: $model.sourceDurationSeconds)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    TextField("Destination", text: $model.trimDestinationPath)
                        .font(.system(.body, design: .monospaced))
                    Button("Choose...") {
                        model.chooseTrimDestination()
                    }
                }

                Button(model.isTrimming ? "Exporting Trim..." : "Export Trim") {
                    model.exportTrim()
                }
                .disabled(model.isTrimming || model.projectURL == nil)
            }
        }
    }

    private func mediaPanel(manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Media", subtitle: "Files referenced by the project manifest.") {
            if manifest.media.allFiles.isEmpty {
                Text("No media files are referenced yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manifest.media.allFiles.indices, id: \.self) { index in
                    let file = manifest.media.allFiles[index]
                    HStack(alignment: .firstTextBaseline) {
                        Label(file.role.rawValue, systemImage: icon(for: file.role))
                            .frame(width: 180, alignment: .leading)
                        Text(file.relativePath)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        if let byteCount = file.byteCount {
                            Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func markerPanel(manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Markers", subtitle: "Chapter, retake, note, and segment markers.") {
            if manifest.markers.isEmpty {
                Text("No markers yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manifest.markers.indices, id: \.self) { index in
                    let marker = manifest.markers[index]
                    HStack(alignment: .firstTextBaseline) {
                        Text(formatSeconds(marker.timeSeconds))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 80, alignment: .leading)
                        Text(marker.kind.rawValue)
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)
                        Text(marker.title)
                        Spacer()
                    }
                }
            }
        }
    }

    private func technicalDetailsPanel(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Technical Details", subtitle: "Bundle diagnostics for troubleshooting, CLI work, and agent handoff.") {
            DisclosureGroup(isExpanded: $showTechnicalDetails) {
                VStack(alignment: .leading, spacing: 18) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        valueRow("Schema", "\(summary.schemaVersion)")
                        valueRow("Files", "\(summary.fileCount)")
                        valueRow("Tracks", "\(manifest.tracks.count)")
                        valueRow("Markers", "\(summary.markerCount)")
                        valueRow("Course", manifest.metadata.courseTitle ?? "None")
                        valueRow("Issues", summary.issues.isEmpty ? "None" : "\(summary.issues.count)")
                    }

                    if !summary.issues.isEmpty {
                        technicalSectionTitle("Issues")
                        ForEach(summary.issues.indices, id: \.self) { index in
                            issueRow(summary.issues[index].severity.rawValue, summary.issues[index].message, path: summary.issues[index].path)
                        }
                    }

                    technicalSectionTitle("Media")
                    if manifest.media.allFiles.isEmpty {
                        Text("No media files are referenced yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manifest.media.allFiles.indices, id: \.self) { index in
                            let file = manifest.media.allFiles[index]
                            HStack(alignment: .firstTextBaseline) {
                                Label(file.role.rawValue, systemImage: icon(for: file.role))
                                    .frame(width: 180, alignment: .leading)
                                Text(file.relativePath)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                if let byteCount = file.byteCount {
                                    Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                }
                .padding(.top, 10)
            } label: {
                HStack {
                    Label(showTechnicalDetails ? "Hide bundle details" : "Show bundle details", systemImage: "wrench.and.screwdriver")
                    Spacer()
                    Text("\(countLabel(summary.fileCount, singular: "file")), \(countLabel(summary.markerCount, singular: "marker"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func technicalSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func issueRow(_ severity: String, _ message: String, path: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(severity.capitalized, systemImage: severity == "error" ? "xmark.octagon" : "exclamationmark.triangle")
                .foregroundStyle(severity == "error" ? .red : .orange)
                .frame(width: 120, alignment: .leading)
            Text(path.map { "\($0): \(message)" } ?? message)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func zoomField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .frame(width: 72)
    }

    private func icon(for role: ProjectFileRole) -> String {
        switch role {
        case .screenVideo: "display"
        case .webcamVideo: "video"
        case .microphoneAudio, .systemAudio: "waveform"
        case .cursorMetadata: "cursorarrow.motionlines"
        case .annotations: "pencil.tip"
        case .overlays: "square.on.square"
        case .captions, .transcript: "captions.bubble"
        case .thumbnail: "photo"
        case .manifest: "doc.text"
        case .attachment: "paperclip"
        }
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, remainder)
    }

    private func secondsValue(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let seconds = Double(trimmed), seconds.isFinite else { return nil }
        return max(0, seconds)
    }
}

private enum EditorInspectorTab: String, CaseIterable, Identifiable {
    case edits
    case canvas
    case cuts
    case zooms
    case overlays
    case camera
    case audio
    case captions
    case cursor
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edits: "Edit"
        case .canvas: "Canvas"
        case .cuts: "Cuts"
        case .zooms: "Zooms"
        case .overlays: "Overlays"
        case .camera: "Camera"
        case .audio: "Audio"
        case .captions: "Captions"
        case .cursor: "Cursor"
        case .export: "Export"
        }
    }
}

private enum TimelineSelection: Equatable {
    case cut(String)
    case speed(String)
    case audioVolume(String)
    case zoom(String)
    case overlay(String)
    case caption(String)
    case cameraRegion(String)
    case cursorHide(String)
    case marker(String)
}

private enum TimelineDragAction: Equatable {
    case trimStart
    case trimEnd
    case moveCut
    case resizeCutStart
    case resizeCutEnd
    case moveSpeed
    case resizeSpeedStart
    case resizeSpeedEnd
    case moveAudioVolume
    case resizeAudioVolumeStart
    case resizeAudioVolumeEnd
    case moveZoom
    case resizeZoomStart
    case resizeZoomEnd
    case moveOverlay
    case resizeOverlayStart
    case resizeOverlayEnd
    case moveCaption
    case resizeCaptionStart
    case resizeCaptionEnd
    case moveCameraRegion
    case resizeCameraRegionStart
    case resizeCameraRegionEnd
    case moveCursorHide
    case resizeCursorHideStart
    case resizeCursorHideEnd
    case moveMarker
}

private struct TimelineDragState {
    var action: TimelineDragAction
    var id: String
    var startSeconds: Double
    var endSeconds: Double
}

private struct OverlayPreviewDragState {
    var id: String
    var startX: Double
    var startY: Double
}

private struct OverlayPreviewResizeDragState {
    var id: String
    var startWidth: Double
    var startHeight: Double
}

private struct ProjectVideoPlayer: NSViewRepresentable {
    var player: AVPlayer
    var controlsStyle: AVPlayerViewControlsStyle = .floating

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = controlsStyle
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
        if view.controlsStyle != controlsStyle {
            view.controlsStyle = controlsStyle
        }
    }
}

private struct DashboardCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct EditorPanel<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func contentPadding(top: CGFloat) -> some View {
        padding(.top, top)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Color {
    init(rgba: RGBAColor) {
        self.init(
            red: min(1, max(0, rgba.red)),
            green: min(1, max(0, rgba.green)),
            blue: min(1, max(0, rgba.blue)),
            opacity: min(1, max(0, rgba.alpha))
        )
    }
}

private extension EditorCanvasAspectRatio {
    var previewAspectRatio: CGFloat? {
        switch self {
        case .source:
            nil
        case .custom:
            nil
        case .square1x1:
            1
        case .portrait4x5:
            4 / 5
        case .portrait9x16:
            9 / 16
        case .standard4x3:
            4 / 3
        case .widescreen16x9:
            16 / 9
        }
    }
}

private struct EditableCutRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var reason: String
    var isEnabled: Bool
}

private struct EditableSpeedRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var playbackRate: String
}

private struct EditableAudioVolumeRegionRow: Identifiable, Equatable {
    var id: String
    var track: EditorAudioTrackRole
    var startSeconds: String
    var endSeconds: String
    var gain: String
    var fadeInSeconds: String
    var fadeOutSeconds: String
    var isEnabled: Bool
}

private struct EditableCaptionRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var text: String
}

private struct EditableZoomRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var scale: String
    var centerX: String
    var centerY: String
    var size: String
    var focusMode: ZoomFocusMode
    var easing: ZoomEasing
    var isEnabled: Bool
}

private struct EditableOverlayRow: Identifiable, Equatable {
    var id: String
    var kind: OverlayKind
    var startSeconds: String
    var endSeconds: String
    var text: String
    var x: String
    var y: String
    var width: String
    var height: String
    var opacity: String
    var fontSize: String
    var fadeInSeconds: String
    var fadeOutSeconds: String
    var animationPreset: OverlayAnimationPreset
    var cornerRadius: String
    var highlightMode: OverlayHighlightMode
    var highlightShape: OverlayHighlightShape
    var blurRadius: String
    var featherRadius: String
    var textColor: RGBAColor
    var fillColor: RGBAColor
    var strokeColor: RGBAColor
    var imagePath: String
    var zIndex: Int
    var isEnabled: Bool
}

private struct EditableCameraRegionRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var preset: CameraLayoutPreset
    var layoutAnimation: CameraLayoutAnimation
    var transitionSeconds: String
    var isEnabled: Bool
}

private struct EditableCameraReactionRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var text: String
    var isEnabled: Bool
}

private protocol EditableTimelineRangeRow {
    var id: String { get }
    var startSeconds: String { get set }
    var endSeconds: String { get set }
}

extension EditableCutRow: EditableTimelineRangeRow {}
extension EditableSpeedRow: EditableTimelineRangeRow {}
extension EditableAudioVolumeRegionRow: EditableTimelineRangeRow {}
extension EditableCaptionRow: EditableTimelineRangeRow {}
extension EditableZoomRow: EditableTimelineRangeRow {}
extension EditableOverlayRow: EditableTimelineRangeRow {}
extension EditableCameraRegionRow: EditableTimelineRangeRow {}
extension EditableTimeRangeRow: EditableTimelineRangeRow {}

private struct EditableMarkerRow: Identifiable, Equatable {
    var id: String
    var kind: ProjectTimelineMarkerKind
    var timeSeconds: String
    var title: String
    var notes: String
}

private struct EditableTimeRangeRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
}

@MainActor
private final class ProjectEditorModel: ObservableObject {
    @Published var projectURL: URL?
    @Published var manifest: ProjectManifest?
    @Published var summary: ProjectBundleSummary?
    @Published var renderInspection: RenderInspection?
    @Published var player: AVPlayer?
    @Published var currentTimeSeconds: Double = 0
    @Published var previewDurationSeconds: Double = 0
    @Published var isPlaying = false
    @Published var cutRows: [EditableCutRow] = []
    @Published var speedRows: [EditableSpeedRow] = []
    @Published var zoomRows: [EditableZoomRow] = []
    @Published var overlayRows: [EditableOverlayRow] = []
    @Published var markerRows: [EditableMarkerRow] = []
    @Published var editValidationIssues: [EditValidationIssue] = []
    @Published var renderQuality: RenderQuality = .highest
    @Published var renderFileType: RenderFileType = .mp4
    @Published var renderDestinationPath = ""
    @Published var trimDestinationPath = ""
    @Published var trimStartSeconds = "0"
    @Published var trimEndSeconds = ""
    @Published var sourceDurationSeconds = ""
    @Published var isRendering = false
    @Published var renderProgress = 0.0
    @Published var isTrimming = false
    @Published var isPackagingLearnHouse = false
    @Published var isExportingFrame = false
    @Published var metadataLessonTitle = ""
    @Published var metadataCourseTitle = ""
    @Published var metadataModuleTitle = ""
    @Published var metadataInstructor = ""
    @Published var metadataSummary = ""
    @Published var metadataTags = ""
    @Published var canvasAspectRatio: EditorCanvasAspectRatio = .source
    @Published var canvasCustomWidth = "1920"
    @Published var canvasCustomHeight = "1080"
    @Published var canvasBackgroundStyle: EditorCanvasBackgroundStyle = .none
    @Published var canvasPrimaryColor: RGBAColor = .black
    @Published var canvasSecondaryColor: RGBAColor = .purple
    @Published var canvasBackgroundImagePath = ""
    @Published var canvasBackgroundImage: NSImage?
    @Published var canvasPaddingRatio = 0.0
    @Published var canvasInsetRatio = 0.0
    @Published var canvasCornerRadiusRatio = 0.0
    @Published var canvasShadowEnabled = false
    @Published var canvasShadowOpacity = 0.34
    @Published var canvasCropEnabled = false
    @Published var canvasCropX = "0"
    @Published var canvasCropY = "0"
    @Published var canvasCropWidth = "1"
    @Published var canvasCropHeight = "1"
    @Published var zoomAutoGenerationEnabled = true
    @Published var cursorPreviewMetadata: InteractionMetadataDocument?
    @Published var cursorPointerStyle: EditorCursorPointerStyle = .macOS
    @Published var cursorPointerVisible = true
    @Published var cursorSmoothMovement = true
    @Published var cursorPointerScale = 1.0
    @Published var cursorPointerFillColor: RGBAColor = .white
    @Published var cursorPointerStrokeColor: RGBAColor = .black
    @Published var cursorClickEffectsVisible = true
    @Published var cursorClickColor: RGBAColor = .yellow
    @Published var cursorClickScale = 1.0
    @Published var cursorClickOpacity = 0.85
    @Published var cursorClickDuration = 0.42
    @Published var cursorClickSoundEnabled = false
    @Published var cursorClickSoundVolume = 0.45
    @Published var cursorKeyboardVisible = true
    @Published var cursorKeyboardOpacity = 0.9
    @Published var cursorHiddenRangeRows: [EditableTimeRangeRow] = []
    @Published var cameraCorner: PictureInPictureCorner = .bottomTrailing
    @Published var cameraWidthRatio = "0.22"
    @Published var cameraMarginRatio = "0.04"
    @Published var cameraAspectRatio: PictureInPictureAspectRatio = .widescreen16x9
    @Published var cameraFrameShape: PictureInPictureFrameShape = .roundedRectangle
    @Published var cameraCornerRadius = "12"
    @Published var cameraMirrored = false
    @Published var cameraBorderEnabled = false
    @Published var cameraShadowEnabled = true
    @Published var cameraRegionRows: [EditableCameraRegionRow] = []
    @Published var cameraReactionRows: [EditableCameraReactionRow] = []
    @Published var screenAudioGain = "1"
    @Published var screenAudioMuted = false
    @Published var screenAudioSoloed = false
    @Published var microphoneAudioGain = "1"
    @Published var microphoneAudioMuted = false
    @Published var microphoneAudioSoloed = false
    @Published var systemAudioGain = "1"
    @Published var systemAudioMuted = false
    @Published var systemAudioSoloed = false
    @Published var backgroundMusicPath = ""
    @Published var backgroundMusicStart = "0"
    @Published var backgroundMusicSourceStart = "0"
    @Published var backgroundMusicDuration = ""
    @Published var backgroundMusicGain = "0.28"
    @Published var backgroundMusicLoop = true
    @Published var backgroundMusicDuckUnderVoice = true
    @Published var backgroundMusicDuckedGain = "0.12"
    @Published var backgroundMusicFadeIn = "0.5"
    @Published var backgroundMusicFadeOut = "0.5"
    @Published var audioVolumeRows: [EditableAudioVolumeRegionRow] = []
    @Published var captionRows: [EditableCaptionRow] = []
    @Published var captionBurnInEnabled = true
    @Published var captionPlacement: EditorCaptionPlacement = .bottom
    @Published var captionFontName = "Helvetica-Bold"
    @Published var captionFontSize = "34"
    @Published var captionTextColor: RGBAColor = .white
    @Published var captionBackgroundColor = RGBAColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 0.72)
    @Published var captionMaxLineCount = 3
    @Published var captionSafeMargin = "0.07"
    @Published var annotationItemCount = 0
    @Published var annotationSidecarStatus = "Not initialized"
    @Published var annotationDraftText = "Annotation note"
    @Published var annotationDraftX = "120"
    @Published var annotationDraftY = "120"
    @Published var annotationDraftStart = ""
    @Published var annotationDraftEnd = ""
    @Published var message = ""
    @Published var messageIsError = false
    private var timeObserver: Any?
    private var lastEditDecisionList: EditDecisionList?
    private var renderTask: Task<Void, Never>?
    private static let minimumTimelineRangeSeconds = 0.1

    func apply(_ preferences: LessonMeldPreferences) {
        renderQuality = RenderQuality(rawValue: preferences.export.defaultRenderQuality.rawValue) ?? .highest
        renderFileType = RenderFileType(rawValue: preferences.export.defaultFileType.rawValue) ?? .mp4
        refreshDefaultDestinations()
    }

    func teardown() {
        removeTimeObserver()
        player?.pause()
        player = nil
        renderTask?.cancel()
        renderTask = nil
    }

    var formattedCurrentTime: String {
        Self.formatClock(currentTimeSeconds)
    }

    var formattedDuration: String {
        previewDurationSeconds > 0 ? Self.formatClock(previewDurationSeconds) : "--:--"
    }

    func cursorSample(at seconds: Double) -> CursorSample? {
        guard let cursorPreviewMetadata else { return nil }
        let hiddenRanges = cursorHiddenRangeRows.compactMap { row -> EditTimeRange? in
            guard let start = Double(row.startSeconds.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let end = Double(row.endSeconds.trimmingCharacters(in: .whitespacesAndNewlines)),
                  end > start else {
                return nil
            }
            return EditTimeRange(startSeconds: start, endSeconds: end)
        }
        guard !hiddenRanges.contains(where: { $0.contains(seconds) }) else { return nil }
        return cursorPreviewMetadata.cursorSamples
            .filter { $0.timestampSeconds <= seconds && $0.isVisible }
            .max { $0.timestampSeconds < $1.timestampSeconds }
    }

    func cursorClick(at seconds: Double) -> CursorClick? {
        guard let cursorPreviewMetadata else { return nil }
        return cursorPreviewMetadata.clicks
            .filter {
                $0.phase == .down
                    && seconds >= $0.timestampSeconds
                    && seconds <= $0.timestampSeconds + max(0.05, cursorClickDuration)
            }
            .max { $0.timestampSeconds < $1.timestampSeconds }
    }

    func cursorClickProgress(_ click: CursorClick, at seconds: Double) -> Double {
        let duration = max(0.05, cursorClickDuration)
        return min(1, max(0, (seconds - click.timestampSeconds) / duration))
    }

    func keyboardPreviewLabel(at seconds: Double) -> String? {
        guard let cursorPreviewMetadata else { return nil }
        let event = cursorPreviewMetadata.keystrokes
            .filter {
                $0.phase == .down
                    && !$0.isRepeat
                    && seconds >= $0.timestampSeconds
                    && seconds <= $0.timestampSeconds + 0.9
            }
            .max(by: { $0.timestampSeconds < $1.timestampSeconds })
        guard let event else {
            return nil
        }
        return Self.keyboardLabel(for: event)
    }

    var canvasPreviewAspectRatio: CGFloat? {
        if canvasAspectRatio == .custom,
           let width = Double(canvasCustomWidth.trimmingCharacters(in: .whitespacesAndNewlines)),
           let height = Double(canvasCustomHeight.trimmingCharacters(in: .whitespacesAndNewlines)),
           width > 0,
           height > 0 {
            return CGFloat(width / height)
        }
        return canvasAspectRatio.previewAspectRatio
    }

    var canvasPreviewPadding: CGFloat {
        CGFloat(canvasPaddingRatio) * 120
    }

    var canvasPreviewCornerRadius: CGFloat {
        CGFloat(canvasCornerRadiusRatio) * 360
    }

    func importVideoForEditing(_ preferences: LessonMeldPreferences) {
        let panel = NSOpenPanel()
        panel.title = "Create Digital Meld LessonMeld Project from Video"
        panel.message = "Choose an MP4 or MOV file to import into a local lesson bundle."
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.editableVideoContentTypes

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            setMessage("Importing \(sourceURL.lastPathComponent)...")
            let projectURL = try importVideo(sourceURL, preferences: preferences)
            loadProject(projectURL)
            setMessage("Imported \(sourceURL.lastPathComponent) for editing.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func newProject(_ preferences: LessonMeldPreferences) {
        do {
            let panel = NSSavePanel()
            panel.title = "New Digital Meld LessonMeld Project"
            panel.nameFieldStringValue = "Untitled Lesson.dmlm"
            panel.prompt = "Create"
            panel.canCreateDirectories = true
            let defaultDirectory = Self.expandedURL(preferences.general.defaultProjectDirectory)
            try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
            panel.directoryURL = defaultDirectory

            guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
            let projectURL = Self.projectURLWithExtension(selectedURL)
            if FileManager.default.fileExists(atPath: ProjectBundle.manifestURL(in: projectURL).path) {
                throw ProjectEditorError.destinationExists(projectURL.path)
            }

            let lessonTitle = Self.lessonTitle(from: projectURL)
            guard let template = LessonTemplateLibrary.template(id: preferences.general.defaultTemplateID)
                ?? LessonTemplateLibrary.defaultTemplates.first else {
                throw ProjectEditorError.templateNotFound(preferences.general.defaultTemplateID)
            }
            let manifest = template.seedManifest(lessonTitle: lessonTitle)
            try ProjectBundle.writeManifest(manifest, to: projectURL)
            loadProject(projectURL)
            setMessage("Created \(lessonTitle).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Digital Meld LessonMeld Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if let projectType = Self.lessonProjectContentType {
            panel.allowedContentTypes = [projectType]
        }
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(url)
    }

    private func importVideo(_ sourceURL: URL, preferences: LessonMeldPreferences) throws -> URL {
        let sourceExtension = sourceURL.pathExtension.lowercased()
        guard Self.supportedEditableVideoExtensions.contains(sourceExtension) else {
            throw ProjectEditorError.unsupportedVideoType(sourceURL.lastPathComponent)
        }

        let existingProjectURL = projectURL
        let existingManifest = manifest
        let shouldAttachToCurrentProject = existingProjectURL != nil && existingManifest?.media.screen == nil
        let destinationProjectURL: URL
        var nextManifest: ProjectManifest

        if shouldAttachToCurrentProject, let existingProjectURL, let existingManifest {
            destinationProjectURL = existingProjectURL
            nextManifest = existingManifest
            try FileManager.default.createDirectory(at: destinationProjectURL, withIntermediateDirectories: true)
        } else {
            let defaultDirectory = Self.expandedURL(preferences.general.defaultProjectDirectory)
            try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
            destinationProjectURL = try Self.makeImportedVideoProjectURL(for: sourceURL, in: defaultDirectory)

            guard let template = LessonTemplateLibrary.template(id: preferences.general.defaultTemplateID)
                ?? LessonTemplateLibrary.defaultTemplates.first else {
                throw ProjectEditorError.templateNotFound(preferences.general.defaultTemplateID)
            }
            nextManifest = template.seedManifest(lessonTitle: Self.lessonTitle(fromImportedVideo: sourceURL))
            try FileManager.default.createDirectory(at: destinationProjectURL, withIntermediateDirectories: true)
        }

        let mediaFileName = Self.uniqueScreenMediaFileName(fileExtension: sourceExtension, in: destinationProjectURL)
        let destinationMediaURL = destinationProjectURL.appendingPathComponent(mediaFileName)
        let sourcePath = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
        let destinationPath = destinationMediaURL.resolvingSymlinksInPath().standardizedFileURL.path
        if sourcePath != destinationPath {
            try FileManager.default.copyItem(at: sourceURL, to: destinationMediaURL)
        }

        nextManifest.media.screen = Self.projectFile(
            for: destinationMediaURL,
            role: .screenVideo,
            projectURL: destinationProjectURL,
            mimeType: Self.videoMimeType(for: sourceExtension)
        )
        if !nextManifest.tracks.contains(where: { $0.id == "screen" || $0.kind == .screen }) {
            nextManifest.tracks.append(TimelineTrack(id: "screen", kind: .screen, displayName: "Screen"))
        }
        if nextManifest.metadata.lessonTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || nextManifest.metadata.lessonTitle == "Untitled Lesson" {
            nextManifest.metadata.lessonTitle = Self.lessonTitle(fromImportedVideo: sourceURL)
        }
        if !nextManifest.exportPresets.contains("learnhouse-1080p") {
            nextManifest.exportPresets.append("learnhouse-1080p")
        }
        nextManifest.updatedAt = Date()

        try ProjectBundle.writeManifest(nextManifest, to: destinationProjectURL)
        return destinationProjectURL
    }

    func loadProject(_ url: URL) {
        do {
            let loadedManifest = try ProjectBundle.loadManifest(at: url)
            try applyLoadedProject(url: url, manifest: loadedManifest, messagePrefix: "Loaded")
        } catch ProjectBundleError.manifestNotFound {
            do {
                let repair = try ProjectBundle.repair(at: url)
                try applyLoadedProject(
                    url: url,
                    manifest: repair.manifest,
                    messagePrefix: repair.wroteManifest ? "Recovered" : "Loaded"
                )
            } catch {
                setError(error.localizedDescription)
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), max(previewDurationSeconds, 0))
        currentTimeSeconds = clamped
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setTrimStartToPlayhead() {
        trimStartSeconds = Self.formatSecondsForEditing(currentTimeSeconds)
    }

    func setTrimEndToPlayhead() {
        trimEndSeconds = Self.formatSecondsForEditing(currentTimeSeconds)
    }

    func updateTrimStart(_ seconds: Double, duration: Double) {
        let end = optionalTimelineSeconds(trimEndSeconds) ?? duration
        let clamped = min(max(0, seconds), max(0, end - Self.minimumTimelineRangeSeconds))
        trimStartSeconds = Self.formatSecondsForEditing(clamped)
        clearTimelineValidation()
    }

    func updateTrimEnd(_ seconds: Double, duration: Double) {
        let start = optionalTimelineSeconds(trimStartSeconds) ?? 0
        let clamped = max(min(max(0, seconds), max(duration, start + Self.minimumTimelineRangeSeconds)), start + Self.minimumTimelineRangeSeconds)
        trimEndSeconds = Self.formatSecondsForEditing(clamped)
        clearTimelineValidation()
    }

    func clearTrim(duration: Double) {
        trimStartSeconds = "0"
        trimEndSeconds = Self.formatSecondsForEditing(duration)
        clearTimelineValidation()
    }

    func stepPlayhead(by delta: Double) {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + abs(delta))
        seek(to: min(max(currentTimeSeconds + delta, 0), max(duration, 0)))
    }

    func copyCurrentFrame() {
        guard !isExportingFrame else { return }
        isExportingFrame = true
        setMessage("Copying current frame...")
        Task {
            do {
                let image = try await currentFrameImage()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                isExportingFrame = false
                setMessage("Copied current frame.")
            } catch {
                isExportingFrame = false
                setError(error.localizedDescription)
            }
        }
    }

    func exportCurrentFrame() {
        guard !isExportingFrame else { return }
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let panel = NSSavePanel()
            panel.title = "Export Current Frame"
            panel.nameFieldStringValue = "\(Self.fileSlug(manifest.metadata.lessonTitle))-frame.png"
            panel.allowedContentTypes = [.png]
            panel.canCreateDirectories = true
            panel.directoryURL = projectURL.appendingPathComponent("Exports", isDirectory: true)
            guard panel.runModal() == .OK, let outputURL = panel.url else { return }

            isExportingFrame = true
            setMessage("Exporting current frame...")
            Task {
                do {
                    let data = try await currentFramePNGData()
                    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: outputURL, options: [.atomic])
                    isExportingFrame = false
                    setMessage("Exported frame \(outputURL.path).")
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                } catch {
                    isExportingFrame = false
                    setError(error.localizedDescription)
                }
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func addCutAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 5)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 5, max(duration, start + 0.5))
        cutRows.append(
            EditableCutRow(
                id: "cut-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                reason: "Retake",
                isEnabled: true
            )
        )
    }

    func removeCut(id: String) {
        cutRows.removeAll { $0.id == id }
    }

    func moveCut(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &cutRows)
    }

    func resizeCut(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &cutRows)
    }

    func toggleCutEnabled(id: String) {
        guard let index = cutRows.firstIndex(where: { $0.id == id }) else { return }
        cutRows[index].isEnabled.toggle()
        clearTimelineValidation()
    }

    func duplicateCut(id: String, duration: Double) {
        guard let source = cutRows.first(where: { $0.id == id }),
              let start = optionalTimelineSeconds(source.startSeconds),
              let end = optionalTimelineSeconds(source.endSeconds) else {
            return
        }
        let length = max(Self.minimumTimelineRangeSeconds, end - start)
        let nextStart = min(max(0, start + length), max(0, duration - length))
        var duplicate = source
        duplicate.id = "cut-\(UUID().uuidString)"
        duplicate.startSeconds = Self.formatSecondsForEditing(nextStart)
        duplicate.endSeconds = Self.formatSecondsForEditing(nextStart + length)
        cutRows.append(duplicate)
        clearTimelineValidation()
    }

    func addSpeedRegionAtPlayhead(rate: Double) {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 4)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 4, max(duration, start + 0.5))
        speedRows.append(
            EditableSpeedRow(
                id: "speed-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                playbackRate: Self.formatSecondsForEditing(rate)
            )
        )
        clearTimelineValidation()
    }

    func removeSpeedRegion(id: String) {
        speedRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func moveSpeedRegion(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &speedRows)
    }

    func resizeSpeedRegion(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &speedRows)
    }

    func addZoomAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 3)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 3, max(duration, start + 0.5))
        zoomRows.append(
            EditableZoomRow(
                id: "zoom-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                scale: "1.6",
                centerX: "0.5",
                centerY: "0.5",
                size: "0.5",
                focusMode: .manual,
                easing: .smooth,
                isEnabled: true
            )
        )
    }

    func addInstantZoomAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 1)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.1, 0))
        let end = min(start + 1.5, max(duration, start + 0.1))
        zoomRows.append(
            EditableZoomRow(
                id: "zoom-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                scale: "1.8",
                centerX: "0.5",
                centerY: "0.5",
                size: "0.42",
                focusMode: .manual,
                easing: .instant,
                isEnabled: true
            )
        )
    }

    func removeZoom(id: String) {
        zoomRows.removeAll { $0.id == id }
    }

    func moveZoom(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &zoomRows)
    }

    func resizeZoom(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &zoomRows)
    }

    func toggleZoomEnabled(id: String) {
        guard let index = zoomRows.firstIndex(where: { $0.id == id }) else { return }
        zoomRows[index].isEnabled.toggle()
        clearTimelineValidation()
    }

    func duplicateZoom(id: String, duration: Double) {
        guard let source = zoomRows.first(where: { $0.id == id }),
              let start = optionalTimelineSeconds(source.startSeconds),
              let end = optionalTimelineSeconds(source.endSeconds) else {
            return
        }
        let length = max(Self.minimumTimelineRangeSeconds, end - start)
        let nextStart = min(max(0, start + length), max(0, duration - length))
        var duplicate = source
        duplicate.id = "zoom-\(UUID().uuidString)"
        duplicate.startSeconds = Self.formatSecondsForEditing(nextStart)
        duplicate.endSeconds = Self.formatSecondsForEditing(nextStart + length)
        zoomRows.append(duplicate)
        clearTimelineValidation()
    }

    func updateZoomFocus(id: String, centerX: Double? = nil, centerY: Double? = nil, size: Double? = nil) {
        guard let index = zoomRows.firstIndex(where: { $0.id == id }) else { return }
        if let centerX {
            zoomRows[index].centerX = Self.formatNormalized(min(max(centerX, 0), 1))
        }
        if let centerY {
            zoomRows[index].centerY = Self.formatNormalized(min(max(centerY, 0), 1))
        }
        if let size {
            zoomRows[index].size = Self.formatNormalized(min(max(size, 0.08), 1))
        }
        zoomRows[index].focusMode = .manual
        clearTimelineValidation()
    }

    func zoomRow(id: String) -> EditableZoomRow? {
        zoomRows.first { $0.id == id }
    }

    func addOverlayAtPlayhead(kind: OverlayKind) {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 4)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 4, max(duration, start + 0.5))
        overlayRows.append(Self.defaultOverlayRow(kind: kind, start: start, end: end, zIndex: overlayRows.count))
        clearTimelineValidation()
    }

    func chooseOverlayImageAtPlayhead() {
        let id = "overlay-\(UUID().uuidString)"
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 4)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 4, max(duration, start + 0.5))
        overlayRows.append(Self.defaultOverlayRow(id: id, kind: .image, start: start, end: end, zIndex: overlayRows.count))
        if !chooseImage(forOverlayID: id) {
            overlayRows.removeAll { $0.id == id && $0.imagePath.isEmpty }
        }
    }

    func removeOverlay(id: String) {
        overlayRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func moveOverlay(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &overlayRows)
    }

    func resizeOverlay(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &overlayRows)
    }

    func toggleOverlayEnabled(id: String) {
        guard let index = overlayRows.firstIndex(where: { $0.id == id }) else { return }
        overlayRows[index].isEnabled.toggle()
        clearTimelineValidation()
    }

    func updateOverlayFrame(id: String, x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) {
        guard let index = overlayRows.firstIndex(where: { $0.id == id }) else { return }
        let currentX = optionalTimelineSeconds(overlayRows[index].x) ?? 0
        let currentY = optionalTimelineSeconds(overlayRows[index].y) ?? 0
        let currentWidth = optionalTimelineSeconds(overlayRows[index].width) ?? 0.2
        let currentHeight = optionalTimelineSeconds(overlayRows[index].height) ?? 0.15
        if let x {
            overlayRows[index].x = Self.formatNormalized(min(max(x, 0), max(0, 1 - currentWidth)))
        }
        if let y {
            overlayRows[index].y = Self.formatNormalized(min(max(y, 0), max(0, 1 - currentHeight)))
        }
        if let width {
            overlayRows[index].width = Self.formatNormalized(min(max(width, 0.04), max(0.04, 1 - currentX)))
        }
        if let height {
            overlayRows[index].height = Self.formatNormalized(min(max(height, 0.04), max(0.04, 1 - currentY)))
        }
    }

    func overlayRows(at seconds: Double) -> [EditableOverlayRow] {
        overlayRows
            .filter { row in
                guard row.isEnabled,
                      let start = optionalTimelineSeconds(row.startSeconds),
                      let end = optionalTimelineSeconds(row.endSeconds) else {
                    return false
                }
                return seconds >= start && seconds <= end
            }
            .sorted { $0.zIndex < $1.zIndex }
    }

    @discardableResult
    func chooseImage(forOverlayID id: String) -> Bool {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let panel = NSOpenPanel()
            panel.title = "Choose Overlay Image"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.png, .jpeg]
            panel.prompt = "Choose"
            guard panel.runModal() == .OK, let sourceURL = panel.url else { return false }

            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destinationURL = try Self.uniqueOverlayAssetURL(for: sourceURL, projectURL: projectURL)
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            guard let index = overlayRows.firstIndex(where: { $0.id == id }) else { return false }
            overlayRows[index].kind = .image
            overlayRows[index].imagePath = Self.projectFile(
                for: destinationURL,
                role: .attachment,
                projectURL: projectURL,
                mimeType: Self.imageMimeType(for: destinationURL.pathExtension)
            ).relativePath
            saveOverlays()
            return true
        } catch {
            setError(error.localizedDescription)
            return false
        }
    }

    func overlayImage(for row: EditableOverlayRow) -> NSImage? {
        guard let projectURL, !row.imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let imageURL = ProjectBundle.fileURL(
            for: ProjectFile(relativePath: row.imagePath, role: .attachment),
            in: projectURL
        )
        return NSImage(contentsOf: imageURL)
    }

    func chooseBackgroundMusic() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let panel = NSOpenPanel()
            panel.title = "Choose Background Music"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.audio]
            panel.prompt = "Choose"
            guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destinationURL = try Self.uniqueAudioAssetURL(for: sourceURL, projectURL: projectURL)
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            backgroundMusicPath = Self.projectFile(
                for: destinationURL,
                role: .attachment,
                projectURL: projectURL,
                mimeType: Self.audioMimeType(for: destinationURL.pathExtension)
            ).relativePath
            if backgroundMusicDuration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let remaining = max(0.5, (previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? 0)) - (Double(backgroundMusicStart) ?? 0))
                backgroundMusicDuration = Self.formatSecondsForEditing(remaining)
            }
            saveEditorSettings()
        } catch {
            setError(error.localizedDescription)
        }
    }

    func clearBackgroundMusic() {
        backgroundMusicPath = ""
        backgroundMusicDuration = ""
        saveEditorSettings()
    }

    func addAudioVolumeRegionAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 4)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 4, max(duration, start + 0.5))
        audioVolumeRows.append(
            EditableAudioVolumeRegionRow(
                id: "audio-volume-\(UUID().uuidString)",
                track: .all,
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                gain: "0.6",
                fadeInSeconds: "0.12",
                fadeOutSeconds: "0.12",
                isEnabled: true
            )
        )
        clearTimelineValidation()
    }

    func removeAudioVolumeRegion(id: String) {
        audioVolumeRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func moveAudioVolumeRegion(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &audioVolumeRows)
    }

    func resizeAudioVolumeRegion(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &audioVolumeRows)
    }

    func toggleAudioVolumeRegionEnabled(id: String) {
        guard let index = audioVolumeRows.firstIndex(where: { $0.id == id }) else { return }
        audioVolumeRows[index].isEnabled.toggle()
        clearTimelineValidation()
    }

    func addCaptionAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 3)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 3, max(duration, start + 0.5))
        captionRows.append(
            EditableCaptionRow(
                id: "caption-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end),
                text: "Caption text"
            )
        )
        clearTimelineValidation()
    }

    func removeCaption(id: String) {
        captionRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func moveCaption(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &captionRows)
    }

    func resizeCaption(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &captionRows)
    }

    func activeCaption(at seconds: Double) -> EditableCaptionRow? {
        captionRows
            .filter { row in
                guard let start = optionalTimelineSeconds(row.startSeconds),
                      let end = optionalTimelineSeconds(row.endSeconds) else {
                    return false
                }
                return seconds >= start && seconds <= end
            }
            .sorted { ($0.startSeconds, $0.id) < ($1.startSeconds, $1.id) }
            .last
    }

    func addCameraRegionAtPlayhead(preset: CameraLayoutPreset) {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 4)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 4, max(duration, start + 0.5))
        cameraRegionRows.append(EditableCameraRegionRow(
            id: "camera-region-\(UUID().uuidString)",
            startSeconds: Self.formatSecondsForEditing(start),
            endSeconds: Self.formatSecondsForEditing(end),
            preset: preset,
            layoutAnimation: .fade,
            transitionSeconds: "0.18",
            isEnabled: true
        ))
        clearTimelineValidation()
    }

    func removeCameraRegion(id: String) {
        cameraRegionRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func moveCameraRegion(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &cameraRegionRows)
    }

    func resizeCameraRegion(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &cameraRegionRows)
    }

    func toggleCameraRegionEnabled(id: String) {
        guard let index = cameraRegionRows.firstIndex(where: { $0.id == id }) else { return }
        cameraRegionRows[index].isEnabled.toggle()
        clearTimelineValidation()
    }

    func addCameraReactionAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 2)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.5, 0))
        let end = min(start + 1.5, max(duration, start + 0.5))
        cameraReactionRows.append(EditableCameraReactionRow(
            id: "camera-reaction-\(UUID().uuidString)",
            startSeconds: Self.formatSecondsForEditing(start),
            endSeconds: Self.formatSecondsForEditing(end),
            text: "👍",
            isEnabled: true
        ))
        clearTimelineValidation()
    }

    func removeCameraReaction(id: String) {
        cameraReactionRows.removeAll { $0.id == id }
        clearTimelineValidation()
    }

    func generateAutoZoomsFromClicks() {
        do {
            guard zoomAutoGenerationEnabled else {
                throw ProjectEditorError.invalidMetadata("Automatic click zooms are disabled for this project.")
            }
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            guard let cursorMetadata = manifest.media.cursorMetadata else {
                throw ProjectEditorError.invalidMetadata("This project has no cursor/click metadata.")
            }

            let metadataURL = ProjectBundle.fileURL(for: cursorMetadata, in: projectURL)
            let data = try Data(contentsOf: metadataURL)
            let metadata = try DMLessonJSON.decoder().decode(InteractionMetadataDocument.self, from: data)
            let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? 0)
            let clicks = metadata.clicks
                .filter { $0.phase == .down }
                .sorted { $0.timestampSeconds < $1.timestampSeconds }
            guard !clicks.isEmpty else {
                setMessage("No click events were found in cursor metadata.")
                return
            }

            var added = 0
            for click in clicks.prefix(24) {
                let start = max(0, click.timestampSeconds - 0.25)
                let end = duration > 0 ? min(duration, click.timestampSeconds + 1.35) : click.timestampSeconds + 1.35
                guard end > start else { continue }
                zoomRows.append(
                    EditableZoomRow(
                        id: "zoom-click-\(UUID().uuidString)",
                        startSeconds: Self.formatSecondsForEditing(start),
                        endSeconds: Self.formatSecondsForEditing(end),
                        scale: click.clickCount > 1 ? "2.1" : "1.8",
                        centerX: Self.formatNormalized(click.position.x),
                        centerY: Self.formatNormalized(click.position.y),
                        size: "0.38",
                        focusMode: .clickMetadata,
                        easing: .smooth,
                        isEnabled: true
                    )
                )
                added += 1
            }
            clearTimelineValidation()
            if added > 0 {
                saveEditDecisions()
                setMessage("Added \(added) click zoom\(added == 1 ? "" : "s").")
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func addMarkerAtPlayhead() {
        let number = markerRows.count + 1
        let time = previewDurationSeconds > 0 ? currentTimeSeconds : 0
        markerRows.append(
            EditableMarkerRow(
                id: "marker-\(UUID().uuidString)",
                kind: .chapter,
                timeSeconds: Self.formatSecondsForEditing(time),
                title: "Marker \(number)",
                notes: ""
            )
        )
    }

    func removeMarker(id: String) {
        markerRows.removeAll { $0.id == id }
    }

    func moveMarker(id: String, to seconds: Double, duration: Double) {
        guard let index = markerRows.firstIndex(where: { $0.id == id }) else { return }
        markerRows[index].timeSeconds = Self.formatSecondsForEditing(min(max(0, seconds), max(duration, 0)))
        clearTimelineValidation()
    }

    func duplicateMarker(id: String, duration: Double) {
        guard let source = markerRows.first(where: { $0.id == id }),
              let seconds = optionalTimelineSeconds(source.timeSeconds) else {
            return
        }
        var duplicate = source
        duplicate.id = "marker-\(UUID().uuidString)"
        duplicate.title = "\(source.title) Copy"
        duplicate.timeSeconds = Self.formatSecondsForEditing(min(seconds + 1, max(duration, 0)))
        markerRows.append(duplicate)
        clearTimelineValidation()
    }

    func addCursorHiddenRangeAtPlayhead() {
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? currentTimeSeconds + 2)
        let start = min(max(currentTimeSeconds, 0), max(duration - 0.25, 0))
        let end = min(start + 2, max(duration, start + 0.25))
        cursorHiddenRangeRows.append(
            EditableTimeRangeRow(
                id: "cursor-hide-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(start),
                endSeconds: Self.formatSecondsForEditing(end)
            )
        )
    }

    func removeCursorHiddenRange(id: String) {
        cursorHiddenRangeRows.removeAll { $0.id == id }
    }

    func moveCursorHiddenRange(id: String, start: Double, end: Double, duration: Double) {
        updateRangeRow(id: id, start: start, end: end, duration: duration, rows: &cursorHiddenRangeRows)
    }

    func resizeCursorHiddenRange(id: String, start: Double, end: Double, duration: Double) {
        resizeRangeRow(id: id, start: start, end: end, duration: duration, rows: &cursorHiddenRangeRows)
    }

    func saveMarkers() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let nextMarkers = try markerRows.map { row in
                let timeSeconds = try parseSeconds(row.timeSeconds, label: "Marker time")
                let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else {
                    throw ProjectEditorError.invalidMetadata("Marker title is required.")
                }
                return ProjectTimelineMarker(
                    id: row.id,
                    kind: row.kind,
                    timeSeconds: timeSeconds,
                    title: title,
                    notes: Self.optionalText(row.notes)
                )
            }
            .sorted { first, second in
                if first.timeSeconds == second.timeSeconds {
                    return first.title.localizedStandardCompare(second.title) == .orderedAscending
                }
                return first.timeSeconds < second.timeSeconds
            }

            let updated = try ProjectBundle.updateManifest(at: projectURL) { manifest in
                manifest.markers = nextMarkers
            }
            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            loadMarkerRows(updated.markers)
            loadEditDecisions(projectURL: projectURL, manifest: updated)
            setMessage("Saved lesson markers.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func saveEditDecisions() {
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let editDecisionList = try makeEditDecisionList(projectURL: projectURL, manifest: manifest)
            editValidationIssues = editDecisionList.validate()
            if editValidationIssues.contains(where: { $0.severity == .error }) {
                throw ProjectEditorError.editValidationFailed
            }
            try EditDecisionListFile.save(editDecisionList, toProject: projectURL)
            lastEditDecisionList = editDecisionList
            setMessage("Saved \(EditDecisionListFile.defaultFileName).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func saveOverlays() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let store = try makeOverlayStore()
            try OverlayStoreFile.save(store, toProject: projectURL)
            let updated = try attachOverlayStore(projectURL: projectURL)
            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            renderInspection = nil
            setMessage("Saved \(OverlayStoreFile.defaultFileName).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func reloadOverlays() {
        guard let projectURL, let manifest else { return }
        loadOverlays(projectURL: projectURL, manifest: manifest)
        setMessage("Reloaded overlays.")
    }

    func saveCaptions() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let transcript = try makeTranscriptDocument()
            try writeCaptionSidecars(transcript, projectURL: projectURL)
            let updated = try attachCaptionSidecars(projectURL: projectURL)
            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            renderInspection = nil
            setMessage("Saved captions.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func importCaptions() {
        do {
            guard projectURL != nil else {
                throw ProjectEditorError.projectRequired
            }
            let panel = NSOpenPanel()
            panel.title = "Import Captions"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = Self.captionImportContentTypes
            panel.prompt = "Import"
            guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: sourceURL)
            let transcript = try TranscriptImporter.transcript(from: data, fileName: sourceURL.lastPathComponent)
            captionRows = transcript.segments.map(Self.editableCaptionRow(from:))
            saveCaptions()
        } catch {
            setError(error.localizedDescription)
        }
    }

    func exportCaptionSidecars() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let transcript = try makeTranscriptDocument()
            try writeCaptionSidecars(transcript, projectURL: projectURL)
            let updated = try attachCaptionSidecars(projectURL: projectURL)
            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            setMessage("Exported caption sidecars.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func exportEditDecisions() {
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let editDecisionList = try makeEditDecisionList(projectURL: projectURL, manifest: manifest)
            editValidationIssues = editDecisionList.validate()
            if editValidationIssues.contains(where: { $0.severity == .error }) {
                throw ProjectEditorError.editValidationFailed
            }
            try EditDecisionListFile.save(editDecisionList, toProject: projectURL)
            lastEditDecisionList = editDecisionList

            let destinationURL = try destinationURL(path: trimDestinationPath)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw ProjectEditorError.destinationExists(destinationURL.path)
            }
            let plan = try ExportJob(
                id: "edit-decisions-\(UUID().uuidString)",
                editDecisionList: editDecisionList,
                destinationURL: destinationURL,
                preset: ExportPreset(
                    id: "app-edit-decisions",
                    fileType: ExportFileType(rawValue: renderFileType.rawValue) ?? .mp4,
                    quality: ExportQuality(rawValue: renderQuality.rawValue) ?? .highest
                )
            ).makePlan()

            isTrimming = true
            setMessage("Exporting cut list...")
            Task {
                do {
                    let output = try await AVAssetTrimExportService().export(plan: plan)
                    await MainActor.run {
                        self.isTrimming = false
                        self.setMessage("Exported cut list \(output.path).")
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                } catch {
                    await MainActor.run {
                        self.isTrimming = false
                        self.setError(error.localizedDescription)
                    }
                }
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func reloadEditDecisions() {
        guard let projectURL, let manifest else { return }
        loadEditDecisions(projectURL: projectURL, manifest: manifest)
        setMessage("Reloaded edit decisions.")
    }

    func saveEditorSettings() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let settings = try currentEditorSettings()
            try EditorSettingsFile.save(settings, toProject: projectURL)
            renderInspection = nil
            setMessage("Saved \(EditorSettingsFile.defaultFileName).")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func resetCanvasSettings() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let settings = EditorSettings()
            applyEditorSettings(settings)
            try EditorSettingsFile.save(settings, toProject: projectURL)
            renderInspection = nil
            setMessage("Reset canvas settings.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func chooseCanvasBackgroundImage() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let panel = NSOpenPanel()
            panel.title = "Choose Canvas Background Image"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.png, .jpeg]
            panel.prompt = "Choose"
            guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destinationURL = try Self.uniqueCanvasBackgroundURL(for: sourceURL, projectURL: projectURL)
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            canvasBackgroundStyle = .image
            canvasBackgroundImagePath = Self.projectFile(
                for: destinationURL,
                role: .attachment,
                projectURL: projectURL,
                mimeType: Self.imageMimeType(for: destinationURL.pathExtension)
            ).relativePath
            canvasBackgroundImage = NSImage(contentsOf: destinationURL)
            saveEditorSettings()
        } catch {
            setError(error.localizedDescription)
        }
    }

    func saveMetadata() {
        do {
            guard let projectURL else {
                throw ProjectEditorError.projectRequired
            }
            let title = metadataLessonTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw ProjectEditorError.invalidMetadata("Lesson title is required.")
            }

            let updated = try ProjectBundle.updateManifest(at: projectURL) { manifest in
                manifest.metadata.lessonTitle = title
                manifest.metadata.courseTitle = Self.optionalText(metadataCourseTitle)
                manifest.metadata.moduleTitle = Self.optionalText(metadataModuleTitle)
                manifest.metadata.instructor = Self.optionalText(metadataInstructor)
                manifest.metadata.summary = Self.optionalText(metadataSummary)
                manifest.metadata.tags = Self.tags(from: metadataTags)
            }

            manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            setMessage("Saved lesson metadata.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func initializeAnnotationSidecar() {
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let storeURL = try annotationStoreURL(projectURL: projectURL, manifest: manifest, createIfMissing: true)
            let updated = try attachAnnotationStore(projectURL: projectURL, storeURL: storeURL)
            self.manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            loadAnnotationStatus(projectURL: projectURL, manifest: updated)
            setMessage("Initialized annotations sidecar.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func prepareAnnotationSidecarForOverlay() -> URL? {
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let storeURL = try annotationStoreURL(projectURL: projectURL, manifest: manifest, createIfMissing: true)
            let updated = try attachAnnotationStore(projectURL: projectURL, storeURL: storeURL)
            self.manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            loadAnnotationStatus(projectURL: projectURL, manifest: updated)
            return storeURL
        } catch {
            setError(error.localizedDescription)
            return nil
        }
    }

    func reloadAnnotations() {
        guard let projectURL, let manifest else { return }
        loadAnnotationStatus(projectURL: projectURL, manifest: manifest)
        setMessage("Reloaded annotation sidecar.")
    }

    func addTextAnnotation(_ preferences: LessonMeldPreferences) {
        do {
            guard let projectURL, let manifest else {
                throw ProjectEditorError.projectRequired
            }
            let text = annotationDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ProjectEditorError.invalidMetadata("Annotation text is required.")
            }

            let x = try parseRegionValue(annotationDraftX, label: "Annotation X")
            let y = try parseRegionValue(annotationDraftY, label: "Annotation Y")
            let start = try optionalSeconds(annotationDraftStart, label: "Annotation start") ?? max(currentTimeSeconds, 0)
            let end = try optionalSeconds(annotationDraftEnd, label: "Annotation end") ?? defaultAnnotationEnd(after: start)
            let timeRange = AnnotationTimeRange(startSeconds: start, endSeconds: end)
            guard timeRange.isValid else {
                throw ProjectEditorError.invalidNumber("Annotation end must be greater than annotation start.")
            }
            let storeURL = try annotationStoreURL(projectURL: projectURL, manifest: manifest, createIfMissing: true)
            var store = try loadAnnotationStore(at: storeURL)
            store.add(AnnotationItem(
                displayID: 0,
                kind: .text,
                points: [CGPoint(x: x, y: y)],
                timeRange: timeRange,
                color: Self.annotationColor(from: preferences.annotation.defaultColorHex),
                lineWidth: CGFloat(preferences.annotation.lineWidth),
                text: text,
                textStyle: AnnotationTextStyle(fontSize: 24)
            ))
            try writeAnnotationStore(store, to: storeURL)
            let updated = try attachAnnotationStore(projectURL: projectURL, storeURL: storeURL)
            self.manifest = updated
            summary = try ProjectBundle.inspect(at: projectURL)
            loadAnnotationStatus(projectURL: projectURL, manifest: updated)
            annotationDraftStart = Self.formatSecondsForEditing(start)
            annotationDraftEnd = Self.formatSecondsForEditing(end)
            setMessage("Added text annotation.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func chooseRenderDestination() {
        chooseDestination(defaultPath: renderDestinationPath, fileType: renderFileType) { [weak self] url in
            self?.renderDestinationPath = url.path
        }
    }

    func chooseTrimDestination() {
        chooseDestination(defaultPath: trimDestinationPath, fileType: renderFileType) { [weak self] url in
            self?.trimDestinationPath = url.path
        }
    }

    func inspectRender(_ preferences: LessonMeldPreferences) {
        guard let projectURL else {
            setError("Open a project before inspecting render output.")
            return
        }

        do {
            let destinationURL = try destinationURL(path: renderDestinationPath)
            let loadedManifest = try ProjectBundle.loadManifest(at: projectURL)
            do {
                let plan = try renderPlan(
                    projectURL: projectURL,
                    manifest: loadedManifest,
                    destinationURL: destinationURL,
                    preferences: preferences
                )
                renderInspection = RenderInspection(
                    projectURL: projectURL,
                    lessonTitle: loadedManifest.metadata.lessonTitle,
                    hasWebcamOverlay: plan.webcamOverlay != nil,
                    hasCursorEffects: plan.cursorSource != nil,
                    hasAnnotations: plan.annotationSource != nil,
                    hasOverlays: plan.overlaySource != nil,
                    hasCaptions: plan.captionSource != nil,
                    hasZoomRegions: !plan.zoomRegions.isEmpty,
                    audioSourceCount: plan.audioSources.count,
                    plan: plan,
                    issues: plan.validate(options: .export)
                )
            } catch let error as RenderPlanError {
                renderInspection = RenderInspection(
                    projectURL: projectURL,
                    lessonTitle: loadedManifest.metadata.lessonTitle,
                    hasWebcamOverlay: loadedManifest.media.webcam != nil,
                    hasCursorEffects: loadedManifest.media.cursorMetadata != nil,
                    hasAnnotations: loadedManifest.media.annotations != nil,
                    hasOverlays: loadedManifest.media.overlays != nil,
                    hasCaptions: !loadedManifest.media.transcripts.isEmpty || !loadedManifest.media.captions.isEmpty,
                    hasZoomRegions: Self.projectHasZoomRegions(projectURL),
                    audioSourceCount: [loadedManifest.media.microphoneAudio, loadedManifest.media.systemAudio].compactMap { $0 }.count,
                    plan: nil,
                    issues: [
                        RenderValidationIssue(
                            severity: .error,
                            message: error.localizedDescription
                        )
                    ]
                )
            }
            setMessage("Render inspection completed.")
        } catch {
            setError(error.localizedDescription)
        }
    }

    func exportRender(_ preferences: LessonMeldPreferences) {
        guard let projectURL else {
            setError("Open a project before exporting.")
            return
        }

        isRendering = true
        renderProgress = 0
        setMessage("Rendering full project...")

        renderTask = Task {
            do {
                let destinationURL = try destinationURL(path: renderDestinationPath)
                let loadedManifest = try ProjectBundle.loadManifest(at: projectURL)
                let plan = try renderPlan(
                    projectURL: projectURL,
                    manifest: loadedManifest,
                    destinationURL: destinationURL,
                    preferences: preferences
                )
                let output = try await AVFoundationRenderService().export(plan: plan) { [weak self] progress in
                    self?.renderProgress = min(max(progress, 0), 1)
                }
                await MainActor.run {
                    self.isRendering = false
                    self.renderProgress = 1
                    self.renderTask = nil
                    self.setMessage("Rendered \(output.path).")
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                }
            } catch RenderExportError.exportCancelled {
                await MainActor.run {
                    self.isRendering = false
                    self.renderTask = nil
                    self.setMessage("Render cancelled.")
                }
            } catch {
                await MainActor.run {
                    self.isRendering = false
                    self.renderTask = nil
                    self.setError(error.localizedDescription)
                }
            }
        }
    }

    func packageLearnHouse(_ preferences: LessonMeldPreferences) {
        guard let projectURL else {
            setError("Open a project before packaging.")
            return
        }
        guard !isPackagingLearnHouse else { return }

        isPackagingLearnHouse = true
        setMessage("Packaging LearnHouse export...")
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
                    self.isPackagingLearnHouse = false
                    let revealPath = result.archivePath ?? result.packagePath
                    self.setMessage("Packaged LearnHouse export.")
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: revealPath)])
                }
            } catch {
                await MainActor.run {
                    self.isPackagingLearnHouse = false
                    self.setError(error.localizedDescription)
                }
            }
        }
    }

    func cancelRender() {
        renderTask?.cancel()
        setMessage("Cancelling render...")
    }

    private func renderPlan(
        projectURL: URL,
        manifest: ProjectManifest,
        destinationURL: URL,
        preferences: LessonMeldPreferences
    ) throws -> RenderPlan {
        let editDecisionList = EditDecisionListFile.exists(in: projectURL)
            ? try EditDecisionListFile.load(fromProject: projectURL)
            : nil
        let editorSettings = try EditorSettingsFile.loadIfPresent(fromProject: projectURL)
        var plan = try RenderPlan.make(
            manifest: manifest,
            projectURL: projectURL,
            destinationURL: destinationURL,
            preset: RenderPreset(fileType: renderFileType, quality: renderQuality),
            editDecisionList: editDecisionList,
            editorSettings: editorSettings
        )
        if plan.webcamOverlay != nil, manifest.capture == nil, editorSettings?.camera == nil {
            plan.webcamOverlay?.placement = Self.webcamPlacement(from: preferences.capture)
        }
        return plan
    }

    func exportTrim() {
        guard let projectURL, let manifest, let screen = manifest.media.screen else {
            setError("Open a project with a screen recording before trimming.")
            return
        }

        do {
            let start = try parseSeconds(trimStartSeconds, label: "Trim start")
            let end = try parseSeconds(trimEndSeconds, label: "Trim end")
            let duration = try parseSeconds(sourceDurationSeconds, label: "Source duration")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Trim end must be greater than trim start.")
            }
            guard duration >= end else {
                throw ProjectEditorError.invalidNumber("Source duration must be greater than or equal to trim end.")
            }

            let destinationURL = try destinationURL(path: trimDestinationPath)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw ProjectEditorError.destinationExists(destinationURL.path)
            }

            let editList = EditDecisionList(
                id: "app-trim-\(UUID().uuidString)",
                sourceMediaURL: ProjectBundle.fileURL(for: screen, in: projectURL),
                sourceDurationSeconds: duration,
                trimRange: EditTimeRange(startSeconds: start, endSeconds: end)
            )
            let job = ExportJob(
                id: "trim-\(UUID().uuidString)",
                editDecisionList: editList,
                destinationURL: destinationURL,
                preset: ExportPreset(
                    id: "app-trim",
                    fileType: ExportFileType(rawValue: renderFileType.rawValue) ?? .mp4,
                    quality: ExportQuality(rawValue: renderQuality.rawValue) ?? .highest
                )
            )
            let plan = try job.makePlan()

            isTrimming = true
            setMessage("Exporting trim...")
            Task {
                do {
                    let output = try await AVAssetTrimExportService().export(plan: plan)
                    await MainActor.run {
                        self.isTrimming = false
                        self.setMessage("Exported trim \(output.path).")
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                } catch {
                    await MainActor.run {
                        self.isTrimming = false
                        self.setError(error.localizedDescription)
                    }
                }
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    func revealProject() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    private func configurePreview(projectURL: URL, manifest: ProjectManifest) {
        removeTimeObserver()
        currentTimeSeconds = 0
        previewDurationSeconds = 0
        isPlaying = false

        guard let screen = manifest.media.screen else {
            player = nil
            return
        }

        let screenURL = ProjectBundle.fileURL(for: screen, in: projectURL)
        let nextPlayer = AVPlayer(url: screenURL)
        player = nextPlayer
        timeObserver = nextPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTimeSeconds = seconds
                }
            }
        }

        Task {
            do {
                let asset = AVURLAsset(url: screenURL)
                let duration = try await asset.load(.duration).seconds
                await MainActor.run {
                    guard duration.isFinite, duration > 0 else { return }
                    self.previewDurationSeconds = duration
                    if self.sourceDurationSeconds.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.sourceDurationSeconds = Self.formatSecondsForEditing(duration)
                    }
                    if self.trimEndSeconds.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.trimEndSeconds = Self.formatSecondsForEditing(duration)
                    }
                }
            } catch {
                await MainActor.run {
                    self.setError("Could not load preview duration: \(error.localizedDescription)")
                }
            }
        }
    }

    private func currentFrameImage() async throws -> NSImage {
        guard let projectURL, let manifest, let screen = manifest.media.screen else {
            throw ProjectEditorError.projectRequired
        }
        let screenURL = ProjectBundle.fileURL(for: screen, in: projectURL)
        let asset = AVURLAsset(url: screenURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.08, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
        let time = CMTime(seconds: max(0, currentTimeSeconds), preferredTimescale: 600)
        let cgImage = try await generator.image(at: time).image
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return image
    }

    private func currentFramePNGData() async throws -> Data {
        let image = try await currentFrameImage()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ProjectEditorError.frameExportFailed
        }
        return pngData
    }

    private func applyLoadedProject(url: URL, manifest loadedManifest: ProjectManifest, messagePrefix: String) throws {
        projectURL = url
        manifest = loadedManifest
        summary = try ProjectBundle.inspect(at: url)
        renderInspection = nil
        editValidationIssues = []
        loadMetadataFields(loadedManifest.metadata)
        loadMarkerRows(loadedManifest.markers)
        loadAnnotationStatus(projectURL: url, manifest: loadedManifest)
        loadEditorSettings(projectURL: url)
        loadCursorPreviewMetadata(projectURL: url, manifest: loadedManifest)
        loadOverlays(projectURL: url, manifest: loadedManifest)
        loadCaptions(projectURL: url, manifest: loadedManifest)
        refreshDefaultDestinations()
        configurePreview(projectURL: url, manifest: loadedManifest)
        loadEditDecisions(projectURL: url, manifest: loadedManifest)
        setMessage("\(messagePrefix) \(loadedManifest.metadata.lessonTitle).")
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func loadCursorPreviewMetadata(projectURL: URL, manifest: ProjectManifest) {
        guard let cursorMetadata = manifest.media.cursorMetadata else {
            cursorPreviewMetadata = nil
            return
        }

        do {
            let metadataURL = ProjectBundle.fileURL(for: cursorMetadata, in: projectURL)
            let data = try Data(contentsOf: metadataURL)
            cursorPreviewMetadata = try DMLessonJSON.decoder().decode(InteractionMetadataDocument.self, from: data)
        } catch {
            cursorPreviewMetadata = nil
            setError("Could not load cursor metadata preview: \(error.localizedDescription)")
        }
    }

    private func loadOverlays(projectURL: URL, manifest: ProjectManifest) {
        do {
            let store: OverlayStore
            if let overlays = manifest.media.overlays {
                let url = ProjectBundle.fileURL(for: overlays, in: projectURL)
                let data = try Data(contentsOf: url)
                store = try DMLessonJSON.decoder().decode(OverlayStore.self, from: data)
            } else if let existing = try OverlayStoreFile.loadIfPresent(fromProject: projectURL) {
                store = existing
            } else {
                store = OverlayStore()
            }
            overlayRows = store.overlays.map(Self.editableOverlayRow(from:))
        } catch {
            overlayRows = []
            setError("Could not load overlays: \(error.localizedDescription)")
        }
    }

    private func loadCaptions(projectURL: URL, manifest: ProjectManifest) {
        do {
            guard let source = Self.captionSourceFile(in: manifest) else {
                captionRows = []
                return
            }
            let url = ProjectBundle.fileURL(for: source, in: projectURL)
            guard FileManager.default.fileExists(atPath: url.path) else {
                captionRows = []
                return
            }
            let data = try Data(contentsOf: url)
            let transcript: TranscriptDocument
            if source.mimeType == "application/json" || source.relativePath.lowercased().hasSuffix(".json") {
                transcript = try DMLessonJSON.decoder().decode(TranscriptDocument.self, from: data)
            } else {
                transcript = try TranscriptImporter.transcript(from: data, fileName: source.relativePath)
            }
            captionRows = transcript.segments.map(Self.editableCaptionRow(from:))
        } catch {
            captionRows = []
            setError("Could not load captions: \(error.localizedDescription)")
        }
    }

    private func loadEditDecisions(projectURL: URL, manifest: ProjectManifest) {
        do {
            let editDecisionList: EditDecisionList
            if EditDecisionListFile.exists(in: projectURL) {
                editDecisionList = try EditDecisionListFile.load(fromProject: projectURL)
            } else {
                editDecisionList = defaultEditDecisionList(projectURL: projectURL, manifest: manifest)
            }

            lastEditDecisionList = editDecisionList
            cutRows = editDecisionList.cuts.map { cut in
                EditableCutRow(
                    id: cut.id,
                    startSeconds: Self.formatSecondsForEditing(cut.range.startSeconds),
                    endSeconds: Self.formatSecondsForEditing(cut.range.endSeconds),
                    reason: cut.reason ?? "",
                    isEnabled: cut.isEnabled
                )
            }
            speedRows = editDecisionList.speedRegions.map(Self.editableSpeedRow(from:))
            zoomRows = editDecisionList.zoomRegions.map { zoom in
                let size = min(zoom.focusRect.width, zoom.focusRect.height)
                return EditableZoomRow(
                    id: zoom.id,
                    startSeconds: Self.formatSecondsForEditing(zoom.range.startSeconds),
                    endSeconds: Self.formatSecondsForEditing(zoom.range.endSeconds),
                    scale: Self.formatSecondsForEditing(zoom.scale),
                    centerX: Self.formatNormalized(zoom.focusRect.centerX),
                    centerY: Self.formatNormalized(zoom.focusRect.centerY),
                    size: Self.formatNormalized(size),
                    focusMode: zoom.focusMode ?? .manual,
                    easing: zoom.easing ?? .smooth,
                    isEnabled: zoom.isEnabled
                )
            }
            if let trimRange = editDecisionList.trimRange {
                trimStartSeconds = Self.formatSecondsForEditing(trimRange.startSeconds)
                trimEndSeconds = Self.formatSecondsForEditing(trimRange.endSeconds)
            } else {
                trimStartSeconds = "0"
                trimEndSeconds = editDecisionList.sourceDurationSeconds.map(Self.formatSecondsForEditing) ?? ""
            }
            sourceDurationSeconds = editDecisionList.sourceDurationSeconds.map(Self.formatSecondsForEditing) ?? sourceDurationSeconds
            editValidationIssues = editDecisionList.validate()
        } catch {
            cutRows = []
            speedRows = []
            zoomRows = []
            editValidationIssues = []
            setError("Could not load edit decisions: \(error.localizedDescription)")
        }
    }

    private func loadEditorSettings(projectURL: URL) {
        do {
            let settings = try EditorSettingsFile.loadIfPresent(fromProject: projectURL) ?? EditorSettings()
            applyEditorSettings(settings)
        } catch {
            applyEditorSettings(EditorSettings())
            setError("Could not load \(EditorSettingsFile.defaultFileName): \(error.localizedDescription)")
        }
    }

    private func updateRangeRow<Row: EditableTimelineRangeRow>(
        id: String,
        start: Double,
        end: Double,
        duration: Double,
        rows: inout [Row]
    ) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let length = max(Self.minimumTimelineRangeSeconds, end - start)
        let maxStart = max(0, duration - length)
        let nextStart = min(max(0, start), maxStart)
        rows[index].startSeconds = Self.formatSecondsForEditing(nextStart)
        rows[index].endSeconds = Self.formatSecondsForEditing(nextStart + length)
        clearTimelineValidation()
    }

    private func resizeRangeRow<Row: EditableTimelineRangeRow>(
        id: String,
        start: Double,
        end: Double,
        duration: Double,
        rows: inout [Row]
    ) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let nextStart = min(max(0, start), max(0, duration - Self.minimumTimelineRangeSeconds))
        let nextEnd = min(max(end, nextStart + Self.minimumTimelineRangeSeconds), max(duration, nextStart + Self.minimumTimelineRangeSeconds))
        rows[index].startSeconds = Self.formatSecondsForEditing(nextStart)
        rows[index].endSeconds = Self.formatSecondsForEditing(nextEnd)
        clearTimelineValidation()
    }

    private func optionalTimelineSeconds(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Double(trimmed), seconds.isFinite else { return nil }
        return seconds
    }

    private func clearTimelineValidation() {
        editValidationIssues = []
    }

    private func applyEditorSettings(_ settings: EditorSettings) {
        let canvas = settings.canvas
        canvasAspectRatio = canvas.aspectRatio
        canvasCustomWidth = String(canvas.customSize?.width ?? 1920)
        canvasCustomHeight = String(canvas.customSize?.height ?? 1080)
        canvasBackgroundStyle = canvas.background.style
        canvasPrimaryColor = canvas.background.primaryColor
        canvasSecondaryColor = canvas.background.secondaryColor
        canvasBackgroundImagePath = canvas.background.imagePath ?? ""
        loadCanvasBackgroundImage()
        canvasPaddingRatio = canvas.paddingRatio
        canvasInsetRatio = canvas.insetRatio
        canvasCornerRadiusRatio = canvas.cornerRadiusRatio
        canvasShadowEnabled = canvas.shadow.isEnabled
        canvasShadowOpacity = canvas.shadow.opacity
        if let cropRect = canvas.cropRect {
            canvasCropEnabled = true
            canvasCropX = Self.formatNormalized(cropRect.x)
            canvasCropY = Self.formatNormalized(cropRect.y)
            canvasCropWidth = Self.formatNormalized(cropRect.width)
            canvasCropHeight = Self.formatNormalized(cropRect.height)
        } else {
            canvasCropEnabled = false
            canvasCropX = "0"
            canvasCropY = "0"
            canvasCropWidth = "1"
            canvasCropHeight = "1"
        }
        zoomAutoGenerationEnabled = settings.zoom?.automaticClickZoomsEnabled ?? true
        let cursor = settings.cursor ?? EditorCursorSettings()
        cursorPointerStyle = cursor.pointerStyle
        cursorPointerVisible = cursor.pointerVisible
        cursorSmoothMovement = cursor.smoothMovement
        cursorPointerScale = cursor.pointerScale
        cursorPointerFillColor = cursor.pointerFillColor
        cursorPointerStrokeColor = cursor.pointerStrokeColor
        cursorClickEffectsVisible = cursor.clickEffects.rippleVisible
        cursorClickColor = cursor.clickEffects.color
        cursorClickScale = cursor.clickEffects.scale
        cursorClickOpacity = cursor.clickEffects.opacity
        cursorClickDuration = cursor.clickEffects.durationSeconds
        cursorClickSoundEnabled = cursor.clickEffects.soundEnabled
        cursorClickSoundVolume = cursor.clickEffects.soundVolume
        cursorKeyboardVisible = cursor.keyboardOverlay.isVisible
        cursorKeyboardOpacity = cursor.keyboardOverlay.opacity
        cursorHiddenRangeRows = cursor.hiddenRanges.enumerated().map { index, range in
            EditableTimeRangeRow(
                id: "cursor-hide-\(index)-\(UUID().uuidString)",
                startSeconds: Self.formatSecondsForEditing(range.startSeconds),
                endSeconds: Self.formatSecondsForEditing(range.endSeconds)
            )
        }
        let camera = settings.camera ?? EditorCameraSettings()
        cameraCorner = camera.defaultPlacement.corner
        cameraWidthRatio = Self.formatNormalized(camera.defaultPlacement.widthRatio)
        cameraMarginRatio = Self.formatNormalized(camera.defaultPlacement.marginRatio)
        cameraAspectRatio = camera.defaultPlacement.aspectRatio
        cameraFrameShape = camera.defaultPlacement.frameShape
        cameraCornerRadius = Self.formatSecondsForEditing(camera.defaultPlacement.cornerRadius)
        cameraMirrored = camera.defaultPlacement.isMirrored
        cameraBorderEnabled = camera.defaultPlacement.borderEnabled
        cameraShadowEnabled = camera.defaultPlacement.shadowEnabled
        cameraRegionRows = camera.layoutRegions.map(Self.editableCameraRegionRow(from:))
        cameraReactionRows = camera.reactions.map(Self.editableCameraReactionRow(from:))
        let audio = settings.audio ?? EditorAudioSettings()
        screenAudioGain = Self.formatSecondsForEditing(audio.screenAudio.gain)
        screenAudioMuted = audio.screenAudio.isMuted
        screenAudioSoloed = audio.screenAudio.isSoloed
        microphoneAudioGain = Self.formatSecondsForEditing(audio.microphoneAudio.gain)
        microphoneAudioMuted = audio.microphoneAudio.isMuted
        microphoneAudioSoloed = audio.microphoneAudio.isSoloed
        systemAudioGain = Self.formatSecondsForEditing(audio.systemAudio.gain)
        systemAudioMuted = audio.systemAudio.isMuted
        systemAudioSoloed = audio.systemAudio.isSoloed
        if let music = audio.backgroundMusic {
            backgroundMusicPath = music.relativePath
            backgroundMusicStart = Self.formatSecondsForEditing(music.startSeconds)
            backgroundMusicSourceStart = Self.formatSecondsForEditing(music.sourceStartSeconds)
            backgroundMusicDuration = music.durationSeconds.map(Self.formatSecondsForEditing) ?? ""
            backgroundMusicGain = Self.formatSecondsForEditing(music.gain)
            backgroundMusicLoop = music.loop
            backgroundMusicDuckUnderVoice = music.duckUnderVoice
            backgroundMusicDuckedGain = Self.formatSecondsForEditing(music.duckedGain)
            backgroundMusicFadeIn = Self.formatSecondsForEditing(music.fadeInSeconds)
            backgroundMusicFadeOut = Self.formatSecondsForEditing(music.fadeOutSeconds)
        } else {
            backgroundMusicPath = ""
            backgroundMusicStart = "0"
            backgroundMusicSourceStart = "0"
            backgroundMusicDuration = ""
            backgroundMusicGain = "0.28"
            backgroundMusicLoop = true
            backgroundMusicDuckUnderVoice = true
            backgroundMusicDuckedGain = "0.12"
            backgroundMusicFadeIn = "0.5"
            backgroundMusicFadeOut = "0.5"
        }
        audioVolumeRows = audio.volumeRegions.map(Self.editableAudioVolumeRegionRow(from:))
        let captions = settings.captions ?? EditorCaptionSettings()
        captionBurnInEnabled = captions.burnInEnabled
        captionPlacement = captions.placement
        captionFontName = captions.fontName
        captionFontSize = Self.formatSecondsForEditing(captions.fontSize)
        captionTextColor = captions.textColor
        captionBackgroundColor = captions.backgroundColor
        captionMaxLineCount = captions.maxLineCount
        captionSafeMargin = Self.formatNormalized(captions.safeMarginRatio)
    }

    private func currentEditorSettings() throws -> EditorSettings {
        let customSize: EditorCanvasCustomSize?
        if canvasAspectRatio == .custom {
            customSize = EditorCanvasCustomSize(
                width: try parseDimension(canvasCustomWidth, label: "Canvas width"),
                height: try parseDimension(canvasCustomHeight, label: "Canvas height")
            )
        } else {
            customSize = nil
        }

        let backgroundImagePath: String?
        if canvasBackgroundStyle == .image {
            let imagePath = canvasBackgroundImagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !imagePath.isEmpty else {
                throw ProjectEditorError.invalidMetadata("Choose a canvas background image or select a different background mode.")
            }
            backgroundImagePath = imagePath
        } else {
            backgroundImagePath = nil
        }

        let cropRect: NormalizedEditRect?
        if canvasCropEnabled {
            let x = try parseUnitInterval(canvasCropX, label: "Crop X")
            let y = try parseUnitInterval(canvasCropY, label: "Crop Y")
            let width = try parseUnitInterval(canvasCropWidth, label: "Crop width")
            let height = try parseUnitInterval(canvasCropHeight, label: "Crop height")
            guard width > 0, height > 0 else {
                throw ProjectEditorError.invalidNumber("Crop width and height must be greater than zero.")
            }
            guard x + width <= 1, y + height <= 1 else {
                throw ProjectEditorError.invalidNumber("Crop rectangle must fit inside the source video.")
            }
            cropRect = NormalizedEditRect(x: x, y: y, width: width, height: height)
        } else {
            cropRect = nil
        }

        let cursorHiddenRanges = try cursorHiddenRangeRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Cursor hide start")
            let end = try parseSeconds(row.endSeconds, label: "Cursor hide end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Cursor hide end must be greater than cursor hide start.")
            }
            return EditTimeRange(startSeconds: start, endSeconds: end)
        }

        let cameraRegions = try cameraRegionRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Camera region start")
            let end = try parseSeconds(row.endSeconds, label: "Camera region end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Camera region end must be greater than camera region start.")
            }
            return CameraLayoutRegion(
                id: row.id,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                preset: row.preset,
                placement: row.preset == .custom ? try cameraPlacementFromFields() : nil,
                animation: row.layoutAnimation,
                transitionSeconds: try parseNonNegative(row.transitionSeconds, label: "Camera transition"),
                isEnabled: row.isEnabled
            )
        }
        let cameraReactions = try cameraReactionRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Camera reaction start")
            let end = try parseSeconds(row.endSeconds, label: "Camera reaction end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Camera reaction end must be greater than camera reaction start.")
            }
            return CameraReaction(
                id: row.id,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                text: row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "👍" : row.text,
                isEnabled: row.isEnabled
            )
        }

        let backgroundMusic: EditorBackgroundMusicSettings?
        let musicPath = backgroundMusicPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if musicPath.isEmpty {
            backgroundMusic = nil
        } else {
            backgroundMusic = EditorBackgroundMusicSettings(
                relativePath: musicPath,
                startSeconds: try parseSeconds(backgroundMusicStart, label: "Music start"),
                sourceStartSeconds: try parseSeconds(backgroundMusicSourceStart, label: "Music source start"),
                durationSeconds: try optionalSeconds(backgroundMusicDuration, label: "Music duration"),
                gain: try parseNonNegative(backgroundMusicGain, label: "Music gain"),
                loop: backgroundMusicLoop,
                duckUnderVoice: backgroundMusicDuckUnderVoice,
                duckedGain: try parseNonNegative(backgroundMusicDuckedGain, label: "Ducked music gain"),
                fadeInSeconds: try parseNonNegative(backgroundMusicFadeIn, label: "Music fade in"),
                fadeOutSeconds: try parseNonNegative(backgroundMusicFadeOut, label: "Music fade out")
            )
        }

        let audioVolumeRegions = try audioVolumeRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Volume region start")
            let end = try parseSeconds(row.endSeconds, label: "Volume region end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Volume region end must be greater than volume region start.")
            }
            return EditorAudioVolumeRegion(
                id: row.id,
                track: row.track,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                gain: try parseNonNegative(row.gain, label: "Volume region gain"),
                fadeInSeconds: try parseNonNegative(row.fadeInSeconds, label: "Volume region fade in"),
                fadeOutSeconds: try parseNonNegative(row.fadeOutSeconds, label: "Volume region fade out"),
                isEnabled: row.isEnabled
            )
        }

        return EditorSettings(
            canvas: EditorCanvasSettings(
                aspectRatio: canvasAspectRatio,
                background: EditorCanvasBackground(
                    style: canvasBackgroundStyle,
                    primaryColor: canvasPrimaryColor,
                    secondaryColor: canvasSecondaryColor,
                    imagePath: backgroundImagePath
                ),
                paddingRatio: canvasPaddingRatio,
                insetRatio: canvasInsetRatio,
                cornerRadiusRatio: canvasCornerRadiusRatio,
                shadow: EditorCanvasShadow(
                    isEnabled: canvasShadowEnabled,
                    opacity: canvasShadowOpacity
                ),
                cropRect: cropRect,
                customSize: customSize
            ),
            zoom: EditorZoomSettings(automaticClickZoomsEnabled: zoomAutoGenerationEnabled),
            cursor: EditorCursorSettings(
                pointerStyle: cursorPointerStyle,
                pointerVisible: cursorPointerVisible,
                smoothMovement: cursorSmoothMovement,
                pointerScale: cursorPointerScale,
                pointerFillColor: cursorPointerFillColor,
                pointerStrokeColor: cursorPointerStrokeColor,
                hiddenRanges: cursorHiddenRanges,
                clickEffects: EditorClickEffectSettings(
                    rippleVisible: cursorClickEffectsVisible,
                    color: cursorClickColor,
                    scale: cursorClickScale,
                    opacity: cursorClickOpacity,
                    durationSeconds: cursorClickDuration,
                    soundEnabled: cursorClickSoundEnabled,
                    soundVolume: cursorClickSoundVolume
                ),
                keyboardOverlay: EditorKeyboardOverlaySettings(
                    isVisible: cursorKeyboardVisible,
                    opacity: cursorKeyboardOpacity
                )
            ),
            camera: EditorCameraSettings(
                defaultPlacement: try cameraPlacementFromFields(),
                layoutRegions: cameraRegions,
                reactions: cameraReactions
            ),
            audio: EditorAudioSettings(
                screenAudio: EditorAudioTrackSettings(
                    gain: try parseNonNegative(screenAudioGain, label: "Screen audio gain"),
                    isMuted: screenAudioMuted,
                    isSoloed: screenAudioSoloed
                ),
                microphoneAudio: EditorAudioTrackSettings(
                    gain: try parseNonNegative(microphoneAudioGain, label: "Microphone audio gain"),
                    isMuted: microphoneAudioMuted,
                    isSoloed: microphoneAudioSoloed
                ),
                systemAudio: EditorAudioTrackSettings(
                    gain: try parseNonNegative(systemAudioGain, label: "System audio gain"),
                    isMuted: systemAudioMuted,
                    isSoloed: systemAudioSoloed
                ),
                backgroundMusic: backgroundMusic,
                volumeRegions: audioVolumeRegions
            ),
            captions: EditorCaptionSettings(
                burnInEnabled: captionBurnInEnabled,
                placement: captionPlacement,
                fontName: captionFontName,
                fontSize: try parsePositive(captionFontSize, label: "Caption font size"),
                textColor: captionTextColor,
                backgroundColor: captionBackgroundColor,
                maxLineCount: captionMaxLineCount,
                safeMarginRatio: try parseUnitInterval(captionSafeMargin, label: "Caption safe margin")
            )
        )
    }

    private func cameraPlacementFromFields() throws -> PictureInPicturePlacement {
        PictureInPicturePlacement(
            corner: cameraCorner,
            widthRatio: try parseUnitInterval(cameraWidthRatio, label: "Camera size"),
            marginRatio: try parseUnitInterval(cameraMarginRatio, label: "Camera margin"),
            aspectRatio: cameraAspectRatio,
            frameShape: cameraFrameShape,
            cornerRadius: try parseNonNegative(cameraCornerRadius, label: "Camera corners"),
            isMirrored: cameraMirrored,
            borderEnabled: cameraBorderEnabled,
            shadowEnabled: cameraShadowEnabled
        )
    }

    private func loadCanvasBackgroundImage() {
        guard let projectURL, !canvasBackgroundImagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            canvasBackgroundImage = nil
            return
        }
        let imageURL = ProjectBundle.fileURL(
            for: ProjectFile(relativePath: canvasBackgroundImagePath, role: .attachment),
            in: projectURL
        )
        canvasBackgroundImage = NSImage(contentsOf: imageURL)
    }

    private func loadMetadataFields(_ metadata: LessonMetadata) {
        metadataLessonTitle = metadata.lessonTitle
        metadataCourseTitle = metadata.courseTitle ?? ""
        metadataModuleTitle = metadata.moduleTitle ?? ""
        metadataInstructor = metadata.instructor ?? ""
        metadataSummary = metadata.summary ?? ""
        metadataTags = metadata.tags.joined(separator: ", ")
    }

    private func loadMarkerRows(_ markers: [ProjectTimelineMarker]) {
        markerRows = markers
            .sorted { first, second in
                if first.timeSeconds == second.timeSeconds {
                    return first.title.localizedStandardCompare(second.title) == .orderedAscending
                }
                return first.timeSeconds < second.timeSeconds
            }
            .map { marker in
                EditableMarkerRow(
                    id: marker.id,
                    kind: marker.kind,
                    timeSeconds: Self.formatSecondsForEditing(marker.timeSeconds),
                    title: marker.title,
                    notes: marker.notes ?? ""
                )
            }
    }

    private func loadAnnotationStatus(projectURL: URL, manifest: ProjectManifest) {
        do {
            guard let annotations = manifest.media.annotations else {
                annotationItemCount = 0
                annotationSidecarStatus = "Not initialized"
                return
            }

            let url = ProjectBundle.fileURL(for: annotations, in: projectURL)
            guard FileManager.default.fileExists(atPath: url.path) else {
                annotationItemCount = 0
                annotationSidecarStatus = "Missing file"
                return
            }

            let store = try loadAnnotationStore(at: url)
            annotationItemCount = store.annotations.count
            annotationSidecarStatus = store.isLocked ? "Locked" : "Ready"
        } catch {
            annotationItemCount = 0
            annotationSidecarStatus = "Unreadable: \(error.localizedDescription)"
        }
    }

    private func annotationStoreURL(
        projectURL: URL,
        manifest: ProjectManifest,
        createIfMissing: Bool
    ) throws -> URL {
        let url = manifest.media.annotations
            .map { ProjectBundle.fileURL(for: $0, in: projectURL) }
            ?? projectURL.appendingPathComponent("annotations.json")

        if createIfMissing, !FileManager.default.fileExists(atPath: url.path) {
            try writeAnnotationStore(AnnotationStore(), to: url)
        }
        return url
    }

    private func loadAnnotationStore(at url: URL) throws -> AnnotationStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AnnotationStore()
        }
        let data = try Data(contentsOf: url)
        return try DMLessonJSON.decoder().decode(AnnotationStore.self, from: data)
    }

    private func writeAnnotationStore(_ store: AnnotationStore, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try DMLessonJSON.encoder().encode(store)
        try data.write(to: url, options: [.atomic])
    }

    private func makeOverlayStore() throws -> OverlayStore {
        let overlays = try overlayRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Overlay start")
            let end = try parseSeconds(row.endSeconds, label: "Overlay end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Overlay end must be greater than overlay start.")
            }
            let x = try parseUnitInterval(row.x, label: "Overlay X")
            let y = try parseUnitInterval(row.y, label: "Overlay Y")
            let width = try parseUnitInterval(row.width, label: "Overlay width")
            let height = try parseUnitInterval(row.height, label: "Overlay height")
            guard width > 0, height > 0 else {
                throw ProjectEditorError.invalidNumber("Overlay width and height must be greater than zero.")
            }
            guard x + width <= 1, y + height <= 1 else {
                throw ProjectEditorError.invalidNumber("Overlay frame must fit inside the preview.")
            }
            let imagePath = row.imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if row.kind == .image, imagePath.isEmpty {
                throw ProjectEditorError.invalidMetadata("Image overlays need a selected image.")
            }
            let opacity = try parseUnitInterval(row.opacity, label: "Overlay opacity")
            let fontSize = try parsePositive(row.fontSize, label: "Overlay text size")
            let fadeIn = try parseNonNegative(row.fadeInSeconds, label: "Overlay fade in")
            let fadeOut = try parseNonNegative(row.fadeOutSeconds, label: "Overlay fade out")
            let cornerRadius = try parseNonNegative(row.cornerRadius, label: "Overlay corners")
            let blurRadius = try parseNonNegative(row.blurRadius, label: "Overlay blur")
            let featherRadius = try parseNonNegative(row.featherRadius, label: "Overlay feather")
            return OverlayItem(
                id: row.id,
                kind: row.kind,
                timeRange: EditTimeRange(startSeconds: start, endSeconds: end),
                frame: NormalizedEditRect(x: x, y: y, width: width, height: height),
                opacity: opacity,
                zIndex: row.zIndex,
                style: OverlayStyle(
                    text: row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? row.kind.title : row.text,
                    fontSize: fontSize,
                    textColor: row.textColor,
                    fillColor: (row.kind == .rectangle || row.kind == .ellipse) ? row.fillColor : nil,
                    strokeColor: row.strokeColor,
                    backgroundColor: (row.kind == .text || row.kind == .callout) ? row.fillColor : nil,
                    cornerRadius: cornerRadius,
                    shadowEnabled: row.kind != .highlight,
                    imagePath: imagePath.isEmpty ? nil : imagePath,
                    highlightMode: row.kind == .highlight ? row.highlightMode : nil,
                    highlightShape: row.kind == .highlight ? row.highlightShape : nil,
                    blurRadius: row.kind == .highlight ? blurRadius : nil,
                    featherRadius: row.kind == .highlight ? featherRadius : nil
                ),
                animation: OverlayAnimation(
                    fadeInSeconds: fadeIn,
                    fadeOutSeconds: fadeOut,
                    preset: row.animationPreset
                ),
                isEnabled: row.isEnabled
            )
        }
        return OverlayStore(overlays: overlays)
    }

    private func makeTranscriptDocument() throws -> TranscriptDocument {
        let segments = try captionRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Caption start")
            let end = try parseSeconds(row.endSeconds, label: "Caption end")
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Caption end must be greater than caption start.")
            }
            guard !text.isEmpty else {
                throw ProjectEditorError.invalidMetadata("Caption text is required.")
            }
            return TranscriptSegment(
                id: row.id,
                startSeconds: start,
                endSeconds: end,
                text: text
            )
        }
        .sorted { $0.startSeconds < $1.startSeconds }
        return TranscriptDocument(title: metadataLessonTitle.trimmingCharacters(in: .whitespacesAndNewlines), segments: segments)
    }

    private func writeCaptionSidecars(_ transcript: TranscriptDocument, projectURL: URL) throws {
        let jsonURL = projectURL.appendingPathComponent("transcript.json")
        let vttURL = projectURL.appendingPathComponent("captions.vtt")
        let srtURL = projectURL.appendingPathComponent("captions.srt")
        let txtURL = projectURL.appendingPathComponent("transcript.txt")
        try DMLessonJSON.encoder().encode(transcript).write(to: jsonURL, options: [.atomic])
        try TranscriptExporter.vtt(transcript).data(using: .utf8)?.write(to: vttURL, options: [.atomic])
        try TranscriptExporter.srt(transcript).data(using: .utf8)?.write(to: srtURL, options: [.atomic])
        try TranscriptExporter.plainText(transcript).data(using: .utf8)?.write(to: txtURL, options: [.atomic])
    }

    private func attachOverlayStore(projectURL: URL) throws -> ProjectManifest {
        try ProjectBundle.updateManifest(at: projectURL) { manifest in
            let storeURL = OverlayStoreFile.url(inProject: projectURL)
            manifest.media.overlays = Self.projectFile(
                for: storeURL,
                role: .overlays,
                projectURL: projectURL,
                mimeType: "application/json"
            )
            if !manifest.tracks.contains(where: { $0.id == "overlays" }) {
                manifest.tracks.append(TimelineTrack(id: "overlays", kind: .overlays, displayName: "Overlays"))
            }
        }
    }

    private func attachCaptionSidecars(projectURL: URL) throws -> ProjectManifest {
        try ProjectBundle.updateManifest(at: projectURL) { manifest in
            manifest.media.transcripts.removeAll { ["transcript.json", "transcript.txt"].contains($0.relativePath) }
            manifest.media.transcripts.append(Self.projectFile(
                for: projectURL.appendingPathComponent("transcript.json"),
                role: .transcript,
                projectURL: projectURL,
                mimeType: "application/json"
            ))
            manifest.media.transcripts.append(Self.projectFile(
                for: projectURL.appendingPathComponent("transcript.txt"),
                role: .transcript,
                projectURL: projectURL,
                mimeType: "text/plain"
            ))
            manifest.media.captions.removeAll { ["captions.vtt", "captions.srt"].contains($0.relativePath) }
            manifest.media.captions.append(Self.projectFile(
                for: projectURL.appendingPathComponent("captions.vtt"),
                role: .captions,
                projectURL: projectURL,
                mimeType: "text/vtt"
            ))
            manifest.media.captions.append(Self.projectFile(
                for: projectURL.appendingPathComponent("captions.srt"),
                role: .captions,
                projectURL: projectURL,
                mimeType: "application/x-subrip"
            ))
            if !manifest.tracks.contains(where: { $0.id == "captions" }) {
                manifest.tracks.append(TimelineTrack(id: "captions", kind: .captions, displayName: "Captions"))
            }
        }
    }

    private func attachAnnotationStore(projectURL: URL, storeURL: URL) throws -> ProjectManifest {
        try ProjectBundle.updateManifest(at: projectURL) { manifest in
            manifest.media.annotations = Self.projectFile(for: storeURL, role: .annotations, projectURL: projectURL, mimeType: "application/json")
            if !manifest.tracks.contains(where: { $0.id == "annotations" }) {
                manifest.tracks.append(TimelineTrack(id: "annotations", kind: .annotations, displayName: "Annotations"))
            }
        }
    }

    private static func projectFile(
        for url: URL,
        role: ProjectFileRole,
        projectURL: URL,
        mimeType: String? = nil
    ) -> ProjectFile {
        let projectPath = projectURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let relativePath: String
        if filePath.hasPrefix(projectPath + "/") {
            relativePath = String(filePath.dropFirst(projectPath.count + 1))
        } else {
            relativePath = filePath
        }
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? NSNumber)?.int64Value
        return ProjectFile(relativePath: relativePath, role: role, mimeType: mimeType, byteCount: byteCount)
    }

    private func defaultEditDecisionList(projectURL: URL, manifest: ProjectManifest) -> EditDecisionList {
        EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: manifest.media.screen.map { ProjectBundle.fileURL(for: $0, in: projectURL) },
            sourceDurationSeconds: previewDurationSeconds > 0 ? previewDurationSeconds : nil,
            markers: manifest.markers.map { marker in
                TimelineMarker(
                    id: marker.id,
                    kind: editMarkerKind(for: marker.kind),
                    timeSeconds: marker.timeSeconds,
                    title: marker.title,
                    notes: marker.notes
                )
            }
        )
    }

    private func makeEditDecisionList(projectURL: URL, manifest: ProjectManifest) throws -> EditDecisionList {
        let duration = try optionalSeconds(sourceDurationSeconds, label: "Source duration")
            ?? (previewDurationSeconds > 0 ? previewDurationSeconds : nil)
        let trimStart = try optionalSeconds(trimStartSeconds, label: "Trim start")
        let trimEnd = try optionalSeconds(trimEndSeconds, label: "Trim end")
        let trimRange: EditTimeRange?
        if let trimStart, let trimEnd {
            guard trimEnd > trimStart else {
                throw ProjectEditorError.invalidNumber("Trim end must be greater than trim start.")
            }
            trimRange = EditTimeRange(startSeconds: trimStart, endSeconds: trimEnd)
        } else {
            trimRange = nil
        }

        let cuts = try cutRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Cut start")
            let end = try parseSeconds(row.endSeconds, label: "Cut end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Cut end must be greater than cut start.")
            }
            return TimelineCut(
                id: row.id,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                reason: row.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : row.reason,
                isEnabled: row.isEnabled
            )
        }

        let speedRegions = try speedRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Speed start")
            let end = try parseSeconds(row.endSeconds, label: "Speed end")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Speed end must be greater than speed start.")
            }
            return SpeedRegion(
                id: row.id,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                playbackRate: try parsePositive(row.playbackRate, label: "Speed rate")
            )
        }

        let zoomRegions = try zoomRows.map { row in
            let start = try parseSeconds(row.startSeconds, label: "Zoom start")
            let end = try parseSeconds(row.endSeconds, label: "Zoom end")
            let scale = try parsePositive(row.scale, label: "Zoom scale")
            let centerX = try parseUnitInterval(row.centerX, label: "Zoom X")
            let centerY = try parseUnitInterval(row.centerY, label: "Zoom Y")
            let size = try parseUnitInterval(row.size, label: "Zoom size")
            guard end > start else {
                throw ProjectEditorError.invalidNumber("Zoom end must be greater than zoom start.")
            }
            guard size > 0 else {
                throw ProjectEditorError.invalidNumber("Zoom size must be greater than zero.")
            }
            let halfSize = size / 2
            let normalizedCenterX = min(max(centerX, halfSize), 1 - halfSize)
            let normalizedCenterY = min(max(centerY, halfSize), 1 - halfSize)
            return ZoomRegion(
                id: row.id,
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                focusRect: NormalizedEditRect(
                    x: normalizedCenterX - halfSize,
                    y: normalizedCenterY - halfSize,
                    width: size,
                    height: size
                ),
                scale: scale,
                isEnabled: row.isEnabled,
                focusMode: row.focusMode,
                easing: row.easing
            )
        }

        let existing = lastEditDecisionList ?? defaultEditDecisionList(projectURL: projectURL, manifest: manifest)
        return EditDecisionList(
            id: existing.id,
            sourceMediaURL: manifest.media.screen.map { ProjectBundle.fileURL(for: $0, in: projectURL) },
            sourceDurationSeconds: duration,
            trimRange: trimRange,
            cuts: cuts,
            speedRegions: speedRegions,
            zoomRegions: zoomRegions,
            markers: existing.markers
        )
    }

    private func editMarkerKind(for kind: ProjectTimelineMarkerKind) -> TimelineMarkerKind {
        switch kind {
        case .chapter:
            .chapter
        case .retake:
            .retake
        case .presenterNote, .segment:
            .note
        }
    }

    private func chooseDestination(defaultPath: String, fileType: RenderFileType, onChoose: (URL) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Choose Export Destination"
        panel.nameFieldStringValue = URL(fileURLWithPath: defaultPath).lastPathComponent
        if let contentType = UTType(filenameExtension: fileType.fileExtension) {
            panel.allowedContentTypes = [contentType]
        }
        panel.canCreateDirectories = true

        if !defaultPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: defaultPath).deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        onChoose(url)
    }

    private func refreshDefaultDestinations() {
        guard let projectURL else { return }
        let baseName = projectURL.deletingPathExtension().lastPathComponent
        let root = projectURL.deletingLastPathComponent()
        let fileExtension = renderFileType.fileExtension
        if renderDestinationPath.isEmpty || URL(fileURLWithPath: renderDestinationPath).pathExtension != fileExtension {
            renderDestinationPath = root.appendingPathComponent("\(baseName)-render.\(fileExtension)").path
        }
        if trimDestinationPath.isEmpty || URL(fileURLWithPath: trimDestinationPath).pathExtension != fileExtension {
            trimDestinationPath = root.appendingPathComponent("\(baseName)-trim.\(fileExtension)").path
        }
    }

    private func destinationURL(path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectEditorError.invalidDestination
        }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
    }

    private static func expandedURL(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    private static func projectURLWithExtension(_ url: URL) -> URL {
        url.pathExtension.lowercased() == "dmlm" ? url : url.appendingPathExtension("dmlm")
    }

    private static var editableVideoContentTypes: [UTType] {
        [.mpeg4Movie, .quickTimeMovie]
    }

    private static var captionImportContentTypes: [UTType] {
        ["json", "vtt", "srt", "txt", "md"].compactMap { UTType(filenameExtension: $0) }
    }

    private static let supportedEditableVideoExtensions: Set<String> = ["mp4", "mov"]

    private static func makeImportedVideoProjectURL(for sourceURL: URL, in root: URL) throws -> URL {
        let baseName = fileSlug(lessonTitle(fromImportedVideo: sourceURL))
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let projectURL = root.appendingPathComponent("\(baseName)\(suffix).dmlm", isDirectory: true)
            if !FileManager.default.fileExists(atPath: projectURL.path) {
                return projectURL
            }
        }
        return root.appendingPathComponent("\(baseName)-\(UUID().uuidString.lowercased()).dmlm", isDirectory: true)
    }

    private static func uniqueScreenMediaFileName(fileExtension: String, in projectURL: URL) -> String {
        let normalizedExtension = supportedEditableVideoExtensions.contains(fileExtension.lowercased())
            ? fileExtension.lowercased()
            : "mp4"
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let fileName = "screen\(suffix).\(normalizedExtension)"
            if !FileManager.default.fileExists(atPath: projectURL.appendingPathComponent(fileName).path) {
                return fileName
            }
        }
        return "screen-\(UUID().uuidString.lowercased()).\(normalizedExtension)"
    }

    private static func videoMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "mov": "video/quicktime"
        default: "video/mp4"
        }
    }

    private static func imageMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        default: "image/png"
        }
    }

    private static func audioMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "m4a": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "caf": "audio/x-caf"
        default: "audio/*"
        }
    }

    private static func uniqueCanvasBackgroundURL(for sourceURL: URL, projectURL: URL) throws -> URL {
        let backgroundDirectory = projectURL.appendingPathComponent("backgrounds", isDirectory: true)
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let fileExtension = ["jpg", "jpeg", "png"].contains(sourceExtension) ? sourceExtension : "png"
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let destinationURL = backgroundDirectory.appendingPathComponent("canvas-background\(suffix).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
        }
        return backgroundDirectory.appendingPathComponent("canvas-background-\(UUID().uuidString.lowercased()).\(fileExtension)")
    }

    private static func uniqueOverlayAssetURL(for sourceURL: URL, projectURL: URL) throws -> URL {
        let assetDirectory = projectURL.appendingPathComponent("overlays/assets", isDirectory: true)
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let fileExtension = ["jpg", "jpeg", "png"].contains(sourceExtension) ? sourceExtension : "png"
        let baseName = fileSlug(sourceURL.deletingPathExtension().lastPathComponent)
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let destinationURL = assetDirectory.appendingPathComponent("\(baseName)\(suffix).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
        }
        return assetDirectory.appendingPathComponent("\(baseName)-\(UUID().uuidString.lowercased()).\(fileExtension)")
    }

    private static func uniqueAudioAssetURL(for sourceURL: URL, projectURL: URL) throws -> URL {
        let assetDirectory = projectURL.appendingPathComponent("audio/assets", isDirectory: true)
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let fileExtension = ["m4a", "mp3", "wav", "caf", "aiff", "aif"].contains(sourceExtension) ? sourceExtension : "m4a"
        let baseName = fileSlug(sourceURL.deletingPathExtension().lastPathComponent)
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let destinationURL = assetDirectory.appendingPathComponent("\(baseName)\(suffix).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
        }
        return assetDirectory.appendingPathComponent("\(baseName)-\(UUID().uuidString.lowercased()).\(fileExtension)")
    }

    private static var lessonProjectContentType: UTType? {
        UTType(filenameExtension: "dmlm")
    }

    private static func lessonTitle(from projectURL: URL) -> String {
        let title = projectURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled Lesson" : title
    }

    private static func lessonTitle(fromImportedVideo url: URL) -> String {
        let title = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Imported Video" : title
    }

    private static func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func tags(from value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func annotationColor(from hex: String) -> RGBAColor {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6, raw.allSatisfy({ $0.isHexDigit }), let value = UInt32(raw, radix: 16) else {
            return .yellow
        }
        return RGBAColor(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
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

    private static func projectHasZoomRegions(_ projectURL: URL) -> Bool {
        guard let editDecisionList = try? EditDecisionListFile.load(fromProject: projectURL) else {
            return false
        }
        return !editDecisionList.enabledZoomRegions.isEmpty
    }

    private static func captionSourceFile(in manifest: ProjectManifest) -> ProjectFile? {
        if let transcript = manifest.media.transcripts.first(where: {
            $0.mimeType == "application/json" || $0.relativePath.lowercased().hasSuffix(".json")
        }) {
            return transcript
        }
        if let caption = manifest.media.captions.first(where: {
            $0.mimeType == "application/json" || $0.relativePath.lowercased().hasSuffix(".json")
        }) {
            return caption
        }
        return manifest.media.captions.first ?? manifest.media.transcripts.first
    }

    private func parseSeconds(_ value: String, label: String) throws -> Double {
        guard let seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), seconds >= 0 else {
            throw ProjectEditorError.invalidNumber("\(label) must be a non-negative number.")
        }
        return seconds
    }

    private func parsePositive(_ value: String, label: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), number > 0 else {
            throw ProjectEditorError.invalidNumber("\(label) must be a positive number.")
        }
        return number
    }

    private func parseNonNegative(_ value: String, label: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), number >= 0 else {
            throw ProjectEditorError.invalidNumber("\(label) must be a non-negative number.")
        }
        return number
    }

    private func parseUnitInterval(_ value: String, label: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), number >= 0, number <= 1 else {
            throw ProjectEditorError.invalidNumber("\(label) must be between 0 and 1.")
        }
        return number
    }

    private func parseDimension(_ value: String, label: String) throws -> Int {
        guard let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), number >= 16 else {
            throw ProjectEditorError.invalidNumber("\(label) must be at least 16 pixels.")
        }
        return number
    }

    private func optionalSeconds(_ value: String, label: String) throws -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try parseSeconds(trimmed, label: label)
    }

    private func defaultAnnotationEnd(after start: Double) -> Double {
        let fallback = start + 3
        let duration = previewDurationSeconds > 0 ? previewDurationSeconds : (Double(sourceDurationSeconds) ?? fallback)
        return max(min(fallback, duration), start + 0.5)
    }

    private static func formatSecondsForEditing(_ seconds: Double) -> String {
        if seconds.rounded() == seconds {
            return String(Int(seconds))
        }
        return String(format: "%.2f", seconds)
    }

    private static func formatNormalized(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func formatClock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let wholeSeconds = Int(seconds)
        let minutes = wholeSeconds / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, remainder)
    }

    private static func defaultOverlayRow(
        id: String = "overlay-\(UUID().uuidString)",
        kind: OverlayKind,
        start: Double,
        end: Double,
        zIndex: Int
    ) -> EditableOverlayRow {
        EditableOverlayRow(
            id: id,
            kind: kind,
            startSeconds: formatSecondsForEditing(start),
            endSeconds: formatSecondsForEditing(end),
            text: kind == .callout ? "Callout" : "Title",
            x: kind == .text ? "0.22" : (kind == .highlight ? "0.26" : "0.30"),
            y: kind == .text ? "0.12" : (kind == .highlight ? "0.28" : "0.30"),
            width: kind == .text ? "0.56" : (kind == .highlight ? "0.48" : "0.32"),
            height: kind == .text ? "0.14" : (kind == .highlight ? "0.28" : "0.20"),
            opacity: "1",
            fontSize: kind == .callout ? "28" : "34",
            fadeInSeconds: "0.18",
            fadeOutSeconds: "0.18",
            animationPreset: kind == .text ? .slideUp : .none,
            cornerRadius: kind == .highlight ? "18" : "12",
            highlightMode: .dim,
            highlightShape: .roundedRectangle,
            blurRadius: "12",
            featherRadius: "18",
            textColor: .white,
            fillColor: kind == .rectangle || kind == .ellipse ? .yellow : RGBAColor(red: 0.02, green: 0.02, blue: 0.025, alpha: kind == .highlight ? 0.58 : 0.68),
            strokeColor: .yellow,
            imagePath: "",
            zIndex: zIndex,
            isEnabled: true
        )
    }

    private static func editableOverlayRow(from overlay: OverlayItem) -> EditableOverlayRow {
        EditableOverlayRow(
            id: overlay.id,
            kind: overlay.kind,
            startSeconds: formatSecondsForEditing(overlay.timeRange.startSeconds),
            endSeconds: formatSecondsForEditing(overlay.timeRange.endSeconds),
            text: overlay.style.text,
            x: formatNormalized(overlay.frame.x),
            y: formatNormalized(overlay.frame.y),
            width: formatNormalized(overlay.frame.width),
            height: formatNormalized(overlay.frame.height),
            opacity: formatNormalized(overlay.opacity),
            fontSize: formatSecondsForEditing(overlay.style.fontSize),
            fadeInSeconds: formatSecondsForEditing(overlay.animation.fadeInSeconds),
            fadeOutSeconds: formatSecondsForEditing(overlay.animation.fadeOutSeconds),
            animationPreset: overlay.animation.preset,
            cornerRadius: formatSecondsForEditing(overlay.style.cornerRadius),
            highlightMode: overlay.style.highlightMode ?? .dim,
            highlightShape: overlay.style.highlightShape ?? .roundedRectangle,
            blurRadius: formatSecondsForEditing(overlay.style.blurRadius ?? 12),
            featherRadius: formatSecondsForEditing(overlay.style.featherRadius ?? 18),
            textColor: overlay.style.textColor,
            fillColor: overlay.style.backgroundColor ?? overlay.style.fillColor ?? .yellow,
            strokeColor: overlay.style.strokeColor,
            imagePath: overlay.style.imagePath ?? "",
            zIndex: overlay.zIndex,
            isEnabled: overlay.isEnabled
        )
    }

    private static func editableSpeedRow(from speed: SpeedRegion) -> EditableSpeedRow {
        EditableSpeedRow(
            id: speed.id,
            startSeconds: formatSecondsForEditing(speed.range.startSeconds),
            endSeconds: formatSecondsForEditing(speed.range.endSeconds),
            playbackRate: formatSecondsForEditing(speed.playbackRate)
        )
    }

    private static func editableAudioVolumeRegionRow(from region: EditorAudioVolumeRegion) -> EditableAudioVolumeRegionRow {
        EditableAudioVolumeRegionRow(
            id: region.id,
            track: region.track,
            startSeconds: formatSecondsForEditing(region.range.startSeconds),
            endSeconds: formatSecondsForEditing(region.range.endSeconds),
            gain: formatSecondsForEditing(region.gain),
            fadeInSeconds: formatSecondsForEditing(region.fadeInSeconds),
            fadeOutSeconds: formatSecondsForEditing(region.fadeOutSeconds),
            isEnabled: region.isEnabled
        )
    }

    private static func editableCaptionRow(from segment: TranscriptSegment) -> EditableCaptionRow {
        EditableCaptionRow(
            id: segment.id,
            startSeconds: formatSecondsForEditing(segment.startSeconds),
            endSeconds: formatSecondsForEditing(segment.endSeconds),
            text: segment.text
        )
    }

    private static func editableCameraRegionRow(from region: CameraLayoutRegion) -> EditableCameraRegionRow {
        EditableCameraRegionRow(
            id: region.id,
            startSeconds: formatSecondsForEditing(region.range.startSeconds),
            endSeconds: formatSecondsForEditing(region.range.endSeconds),
            preset: region.preset,
            layoutAnimation: region.animation,
            transitionSeconds: formatSecondsForEditing(region.transitionSeconds),
            isEnabled: region.isEnabled
        )
    }

    private static func editableCameraReactionRow(from reaction: CameraReaction) -> EditableCameraReactionRow {
        EditableCameraReactionRow(
            id: reaction.id,
            startSeconds: formatSecondsForEditing(reaction.range.startSeconds),
            endSeconds: formatSecondsForEditing(reaction.range.endSeconds),
            text: reaction.text,
            isEnabled: reaction.isEnabled
        )
    }

    private static func keyboardLabel(for event: KeyboardMetadataEvent) -> String {
        var parts: [String] = []
        if event.modifiers.contains(.control) {
            parts.append("Control")
        }
        if event.modifiers.contains(.option) {
            parts.append("Option")
        }
        if event.modifiers.contains(.shift) {
            parts.append("Shift")
        }
        if event.modifiers.contains(.command) {
            parts.append("Command")
        }

        let trimmedKey = event.characters?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let trimmedKey, !trimmedKey.isEmpty {
            parts.append(trimmedKey)
        } else {
            parts.append("Key \(event.keyCode)")
        }
        return parts.joined(separator: " + ")
    }

    private static func fileSlug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "lesson" : collapsed
    }

    private func setMessage(_ value: String) {
        message = value
        messageIsError = false
    }

    private func setError(_ value: String) {
        message = value
        messageIsError = true
    }

    func parseRegionValue(_ value: String, label: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), number >= 0 else {
            throw ProjectEditorError.invalidNumber("\(label) must be a non-negative number.")
        }
        return number
    }
}

private extension PictureInPictureCorner {
    var title: String {
        switch self {
        case .topLeading: "Top Left"
        case .topTrailing: "Top Right"
        case .bottomLeading: "Bottom Left"
        case .bottomTrailing: "Bottom Right"
        }
    }
}

private extension PictureInPictureAspectRatio {
    var title: String {
        switch self {
        case .original: "Original"
        case .square1x1: "1:1"
        case .portrait2x3: "2:3"
        case .landscape3x2: "3:2"
        case .widescreen16x9: "16:9"
        }
    }
}

private extension PictureInPictureFrameShape {
    var title: String {
        switch self {
        case .roundedRectangle: "Rounded"
        case .square: "Square"
        case .circle: "Circle"
        }
    }
}

private enum ProjectEditorError: Error, LocalizedError {
    case projectRequired
    case invalidDestination
    case invalidNumber(String)
    case invalidMetadata(String)
    case destinationExists(String)
    case editValidationFailed
    case templateNotFound(String)
    case frameExportFailed
    case unsupportedVideoType(String)

    var errorDescription: String? {
        switch self {
        case .projectRequired:
            "Open a project first."
        case .invalidDestination:
            "Choose an export destination."
        case .invalidNumber(let message):
            message
        case .invalidMetadata(let message):
            message
        case .destinationExists(let path):
            "Export destination already exists: \(path)"
        case .editValidationFailed:
            "Edit decisions have validation errors. Fix the cut or trim ranges before saving."
        case .templateNotFound(let id):
            "Lesson template was not found: \(id)"
        case .frameExportFailed:
            "Could not export the current preview frame."
        case .unsupportedVideoType(let fileName):
            "Choose an MP4 or MOV video file to import. Unsupported file: \(fileName)"
        }
    }
}
