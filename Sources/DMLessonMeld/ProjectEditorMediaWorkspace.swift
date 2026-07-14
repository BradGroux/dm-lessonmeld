import AppKit
import AVFoundation
import AVKit
import DMLessonMeldCore
import DMLessonMeldSupport
import SwiftUI
import UniformTypeIdentifiers

extension ProjectEditorView {
    func mediaEditorWorkspace(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        GeometryReader { proxy in
            let layout = EditorWorkspaceLayout.resolve(
                containerWidth: proxy.size.width,
                containerHeight: proxy.size.height,
                preferredInspectorWidth: mediaEditorInspectorWidth,
                inspectorVisible: mediaEditorInspectorVisible,
                timelineVisible: mediaEditorTimelineVisible
            )

            VStack(spacing: 0) {
                mediaEditorTopBar(summary: summary, manifest: manifest)
                    .padding(.bottom, 12)

                Divider()

                HStack(spacing: 0) {
                    mediaEditorStage(manifest: manifest)
                        .frame(width: CGFloat(layout.stageWidth))
                        .frame(maxHeight: .infinity)
                        .layoutPriority(1)
                        .clipped()

                    if layout.showsInspector {
                        Divider()

                        mediaEditorInspector(summary: summary, manifest: manifest)
                            .frame(width: CGFloat(layout.inspectorWidth))
                            .background(Color(nsColor: .windowBackgroundColor))
                            .clipped()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if layout.showsTimeline {
                    Divider()

                    mediaTimelineEditor(manifest: manifest)
                        .frame(height: CGFloat(layout.timelineHeight))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func mediaEditorTopBar(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label("Edit Video", systemImage: "film")
                        .font(.headline)
                    statusPill(reviewStatus(manifest), systemImage: "timeline.selection", tint: hasBlockingIssues(summary) ? .red : .blue)
                    if model.hasUnsavedChanges {
                        statusPill("Unsaved", systemImage: "circle.dotted", tint: .orange)
                            .help(model.dirtySummary)
                    }
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
                confirmProjectTransition("import a video") {
                    model.importVideoForEditing(preferences.snapshot)
                }
            } label: {
                Label("Import", systemImage: "film.badge.plus")
            }

            Button {
                model.saveAllDirtyChanges()
            } label: {
                Label(model.hasUnsavedChanges ? "Save Changes" : "Saved", systemImage: "checkmark.circle")
            }
            .disabled(model.projectURL == nil || !model.hasUnsavedChanges)

            Button {
                confirmRevertUnsavedChanges()
            } label: {
                Label("Revert", systemImage: "arrow.counterclockwise")
            }
            .disabled(model.projectURL == nil || !model.hasUnsavedChanges)

            Menu {
                Toggle("Inspector", isOn: $mediaEditorInspectorVisible)
                Toggle("Timeline", isOn: $mediaEditorTimelineVisible)
                Divider()
                Button("Narrow Inspector") {
                    mediaEditorInspectorWidth = max(EditorWorkspaceLayout.minimumInspectorWidth, mediaEditorInspectorWidth - 40)
                }
                Button("Widen Inspector") {
                    mediaEditorInspectorWidth = min(EditorWorkspaceLayout.maximumInspectorWidth, mediaEditorInspectorWidth + 40)
                }
                Button("Reset Layout") {
                    mediaEditorInspectorVisible = true
                    mediaEditorTimelineVisible = true
                    mediaEditorInspectorWidth = 420
                }
            } label: {
                Label("Layout", systemImage: "rectangle.split.3x1")
            }

            Button {
                model.exportRender(preferences.snapshot)
            } label: {
                Label(model.isRendering ? "Rendering..." : "Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartEditorJob(.renderVideo))
        }
    }

    func mediaEditorStage(manifest: ProjectManifest) -> some View {
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
                .accessibilityLabel("Playhead")
                .accessibilityValue("\(model.formattedCurrentTime) of \(model.formattedDuration)")

                Button {
                    model.setTrimStartToPlayhead()
                } label: {
                    Label("Trim In", systemImage: "timeline.selection")
                }
                .keyboardShortcut("i", modifiers: [.option])
                .accessibilityHint("Sets the trim start to the current playhead.")

                Button {
                    model.setTrimEndToPlayhead()
                } label: {
                    Label("Trim Out", systemImage: "timeline.selection")
                }
                .keyboardShortcut("o", modifiers: [.option])
                .accessibilityHint("Sets the trim end to the current playhead.")

                Button {
                    model.addCutAtPlayhead()
                    editorInspectorTab = .cuts
                } label: {
                    Label("Cut", systemImage: "scissors")
                }
                .keyboardShortcut("b", modifiers: [.option])
                .accessibilityHint("Adds a cut at the current playhead.")

                Button {
                    model.addZoomAtPlayhead()
                    editorInspectorTab = .zooms
                } label: {
                    Label("Zoom", systemImage: "plus.magnifyingglass")
                }
                .keyboardShortcut("z", modifiers: [.option])
                .accessibilityHint("Adds a zoom region at the current playhead.")
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Video preview")
            .accessibilityValue("\(model.formattedCurrentTime) of \(model.formattedDuration)")
            .accessibilityHint("Use Space to play or pause. Use the timeline controls to edit video regions.")

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
            }

            if !model.jobHistory.isEmpty {
                editorJobQueueStrip
            }
        }
        .padding(.trailing, 16)
        .padding(.vertical, 14)
    }

    var editorJobQueueStrip: some View {
        HStack(spacing: 10) {
            Label("Jobs", systemImage: "list.bullet.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let activeJob = model.activeEditorJob {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Label(activeJob.title, systemImage: editorJobKindIcon(activeJob.kind))
                            .font(.caption.weight(.semibold))
                        Text(editorJobProgressText(activeJob))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: activeJob.progress)
                        .frame(maxWidth: 280)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Active job")
                .accessibilityValue("\(activeJob.title), \(editorJobProgressText(activeJob))")
            } else if let latestJob = model.recentEditorJobs.first {
                Label("\(latestJob.title): \(latestJob.statusTitle)", systemImage: editorJobStatusIcon(latestJob.status))
                    .font(.caption)
                    .foregroundStyle(editorJobStatusColor(latestJob.status))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let activeJob = model.activeEditorJob, activeJob.isCancellable {
                Button {
                    model.cancelJob(activeJob)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            }

            Menu {
                editorJobHistoryMenuContent
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityLabel("Job history")
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    var editorJobQueueInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                inspectorSectionTitle("Job Queue")
                Spacer()
                Menu {
                    editorJobHistoryMenuContent
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            if let activeJob = model.activeEditorJob {
                VStack(alignment: .leading, spacing: 6) {
                    Label(activeJob.title, systemImage: editorJobKindIcon(activeJob.kind))
                        .font(.caption.weight(.semibold))
                    ProgressView(value: activeJob.progress)
                    HStack {
                        Text(editorJobProgressText(activeJob))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if activeJob.isCancellable {
                            Button("Cancel") {
                                model.cancelJob(activeJob)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            } else if let latestJob = model.recentEditorJobs.first {
                VStack(alignment: .leading, spacing: 6) {
                    Label(latestJob.title, systemImage: editorJobStatusIcon(latestJob.status))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(editorJobStatusColor(latestJob.status))
                    valueLine("Status", latestJob.statusTitle)
                    if let outputPath = latestJob.outputDisplayPath {
                        Text(outputPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    HStack {
                        Button("Reveal") {
                            model.revealJobOutput(latestJob)
                        }
                        .disabled(latestJob.outputPath == nil)
                        Button("Log") {
                            showEditorJobLog(latestJob)
                        }
                        Button("Retry") {
                            model.retryJob(latestJob, preferences: preferences.snapshot)
                        }
                        .disabled(!latestJob.isRetryable)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    @ViewBuilder
    var editorJobHistoryMenuContent: some View {
        if model.recentEditorJobs.isEmpty {
            Text("No jobs yet.")
        } else {
            ForEach(model.recentEditorJobs) { job in
                Section {
                    Button {
                        model.revealJobOutput(job)
                    } label: {
                        Label("Reveal Output", systemImage: "folder")
                    }
                    .disabled(job.outputPath == nil)

                    Button {
                        model.copyJobOutputPath(job)
                    } label: {
                        Label("Copy Output Path", systemImage: "doc.on.doc")
                    }
                    .disabled(job.outputPath == nil)

                    Button {
                        model.retryJob(job, preferences: preferences.snapshot)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .disabled(!job.isRetryable)

                    Button {
                        showEditorJobLog(job)
                    } label: {
                        Label("View Log", systemImage: "doc.text.magnifyingglass")
                    }

                    Button {
                        model.copyJobLog(job)
                    } label: {
                        Label("Copy Log", systemImage: "doc.text")
                    }

                    if job.isCancellable {
                        Button {
                            model.cancelJob(job)
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text("\(job.title) - \(job.statusTitle)")
                }
            }
        }
    }

    func editorJobStatusIcon(_ status: EditorJobStatus) -> String {
        switch status {
        case .queued:
            "clock"
        case .running:
            "progress.indicator"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .cancelled:
            "xmark.circle"
        }
    }

    func editorJobStatusColor(_ status: EditorJobStatus) -> Color {
        switch status {
        case .queued,
             .running:
            .blue
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .orange
        }
    }

    func editorJobKindIcon(_ kind: EditorJobKind) -> String {
        switch kind {
        case .renderVideo:
            "square.and.arrow.up"
        case .trimExport:
            "timeline.selection"
        case .editDecisionExport:
            "scissors"
        case .learnHousePackage:
            "shippingbox"
        case .rawAssetExtract:
            "folder.badge.gearshape"
        case .sharePackage:
            "archivebox"
        case .frameExport:
            "photo"
        case .frameCopy:
            "doc.on.doc"
        case .captionSidecars:
            "captions.bubble"
        }
    }

    func editorJobProgressText(_ job: EditorJobRecord) -> String {
        switch job.status {
        case .queued:
            "Queued"
        case .running:
            "\(Int((job.progress * 100).rounded()))%"
        case .completed,
             .failed,
             .cancelled:
            job.statusTitle
        }
    }

    func showEditorJobLog(_ job: EditorJobRecord) {
        let alert = NSAlert()
        alert.alertStyle = job.status == .failed ? .warning : .informational
        alert.messageText = "\(job.title) Log"
        alert.informativeText = model.jobLogText(job)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func mediaEditorInspector(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            inspectorPanelHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch editorInspectorTab {
                    case .edits:
                        editorEditsInspector(manifest: manifest)
                    case .assets:
                        editorAssetsInspector(summary: summary, manifest: manifest)
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
                    case .presets:
                        editorPresetsInspector(manifest: manifest)
                    case .cursor:
                        editorCursorInspector(manifest: manifest)
                    case .export:
                        editorExportInspector(summary: summary, manifest: manifest)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.visible)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipped()
    }

    var inspectorPanelHeader: some View {
        HStack(spacing: 10) {
            Label(editorInspectorTab.title, systemImage: editorInspectorTab.systemImage)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Menu {
                ForEach(EditorInspectorTab.allCases) { tab in
                    Button {
                        editorInspectorTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .keyboardShortcut(tab.keyboardShortcut, modifiers: [.option])
                }
            } label: {
                Label("Panel", systemImage: "sidebar.right")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Editor panel")
            .accessibilityValue(editorInspectorTab.title)
            .accessibilityHint("Choose the inspector panel. Use Option plus the panel number to switch quickly.")
        }
        .padding(.bottom, 2)
    }

    func inspectorActionGrid(_ actions: [EditorInspectorAction]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 112, maximum: 128), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(actions) { action in
                Button {
                    action.handler()
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .accessibilityHint("Runs \(action.title) in the active inspector.")
            }
        }
    }

    func editorEditsInspector(manifest: ProjectManifest) -> some View {
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
                    .disabled(!model.canStartEditorJob(.trimExport))
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

    func editorCanvasInspector(manifest: ProjectManifest) -> some View {
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

    func editorCutsInspector(manifest: ProjectManifest) -> some View {
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
                    .disabled(!model.canStartEditorJob(.editDecisionExport))
                Button("Reload") { model.reloadEditDecisions() }
            }

            validationIssuesList
        }
    }

    func editorZoomsInspector(manifest: ProjectManifest) -> some View {
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
                                .accessibilityLabel(
                                    EditorRowAccessibilityPolicy.label(
                                        for: .enabled,
                                        kind: .zoom,
                                        startSeconds: zoom.startSeconds
                                    )
                                )
                            Spacer()
                            Button {
                                model.seek(to: secondsValue(zoom.startSeconds) ?? 0)
                            } label: {
                                Image(systemName: "playhead.left")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(
                                EditorRowAccessibilityPolicy.label(
                                    for: .seek,
                                    kind: .zoom,
                                    startSeconds: zoom.startSeconds
                                )
                            )
                            .accessibilityHint("Moves the playhead to this zoom's start time.")
                            Button {
                                model.removeZoom(id: zoom.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(
                                EditorRowAccessibilityPolicy.label(
                                    for: .delete,
                                    kind: .zoom,
                                    startSeconds: zoom.startSeconds
                                )
                            )
                            .accessibilityHint("Removes this zoom region from the project.")
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

    func editorOverlaysInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorSectionTitle("Overlays")
            inspectorActionGrid([
                EditorInspectorAction("Text", systemImage: "textformat") {
                    model.addOverlayAtPlayhead(kind: .text)
                },
                EditorInspectorAction("Callout", systemImage: "text.bubble") {
                    model.addOverlayAtPlayhead(kind: .callout)
                },
                EditorInspectorAction("Shape", systemImage: "rectangle") {
                    model.addOverlayAtPlayhead(kind: .rectangle)
                },
                EditorInspectorAction("Image", systemImage: "photo") {
                    model.chooseOverlayImageAtPlayhead()
                },
                EditorInspectorAction("Highlight", systemImage: "viewfinder") {
                    model.addOverlayAtPlayhead(kind: .highlight)
                }
            ])

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
                        Picker("Kind", selection: $overlay.kind) {
                            ForEach(OverlayKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                        numericStringSlider("X", text: $overlay.x, range: 0...1, format: "%.2f")
                        numericStringSlider("Y", text: $overlay.y, range: 0...1, format: "%.2f")
                        numericStringSlider("Width", text: $overlay.width, range: 0.04...1, format: "%.2f")
                        numericStringSlider("Height", text: $overlay.height, range: 0.04...1, format: "%.2f")
                        numericStringSlider("Opacity", text: $overlay.opacity, range: 0...1, format: "%.2f")
                        numericStringSlider("Text size", text: $overlay.fontSize, range: 10...120, format: "%.0f")
                        numericStringSlider("Fade in", text: $overlay.fadeInSeconds, range: 0...2, format: "%.2f")
                        numericStringSlider("Fade out", text: $overlay.fadeOutSeconds, range: 0...2, format: "%.2f")
                        numericStringSlider("Corners", text: $overlay.cornerRadius, range: 0...96, format: "%.0f")
                        if overlay.kind == .highlight {
                            numericStringSlider("Feather", text: $overlay.featherRadius, range: 0...80, format: "%.0f")
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

            inspectorActionGrid([
                EditorInspectorAction("Save Overlays", systemImage: "checkmark.circle") {
                    model.saveOverlays()
                },
                EditorInspectorAction("Reload", systemImage: "arrow.clockwise") {
                    model.reloadOverlays()
                }
            ])
        }
    }

    func editorCameraInspector(manifest: ProjectManifest) -> some View {
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
                        Toggle(
                            EditorRowAccessibilityPolicy.label(
                                for: .enabled,
                                kind: .reaction,
                                startSeconds: reaction.startSeconds
                            ),
                            isOn: $reaction.isEnabled
                        )
                            .toggleStyle(.checkbox)
                            .labelsHidden()
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
                        .accessibilityLabel(
                            EditorRowAccessibilityPolicy.label(
                                for: .delete,
                                kind: .reaction,
                                startSeconds: reaction.startSeconds
                            )
                        )
                        .accessibilityHint("Removes this camera reaction from the project.")
                    }
                }

                HStack {
                    Button("Save Camera") { model.saveEditorSettings() }
                }
            }
        }
    }

    func editorAudioInspector(manifest: ProjectManifest) -> some View {
        let hasEmbeddedSystemAudio = manifest.media.hasEmbeddedSystemAudio
        let screenAudioDetail = hasEmbeddedSystemAudio
            ? "Includes embedded system audio from the screen recording."
            : "Audio embedded in the screen recording when present."
        let systemAudioDetail = manifest.media.systemAudio?.relativePath
            ?? (hasEmbeddedSystemAudio ? "Embedded in screen video. Use Screen controls for gain, mute, and solo." : "No system audio sidecar in this project.")

        return VStack(alignment: .leading, spacing: 12) {
            inspectorSectionTitle("Tracks")
            audioTrackControls(
                title: "Screen",
                detail: screenAudioDetail,
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
                detail: systemAudioDetail,
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
                Text("No speed regions yet. Add slow-motion or fast-forward ranges that carry through full export.")
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

    func audioTrackControls(
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

    func editorCaptionsInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorSectionTitle("Captions")
            inspectorActionGrid([
                EditorInspectorAction("Add", systemImage: "plus") {
                    model.addCaptionAtPlayhead()
                },
                EditorInspectorAction("Import", systemImage: "square.and.arrow.down") {
                    model.importCaptions()
                }
            ])

            if model.captionRows.isEmpty {
                Text("No captions yet. Import VTT, SRT, JSON, or text, or add a caption manually at the playhead.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach($model.captionRows) { $caption in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .bottom) {
                            compactNumberField("Start", text: $caption.startSeconds)
                            compactNumberField("End", text: $caption.endSeconds)
                            Spacer(minLength: 4)
                            Button {
                                model.seek(to: secondsValue(caption.startSeconds) ?? 0)
                            } label: {
                                Image(systemName: "playhead.left")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(
                                EditorRowAccessibilityPolicy.label(
                                    for: .seek,
                                    kind: .caption,
                                    startSeconds: caption.startSeconds
                                )
                            )
                            .accessibilityHint("Moves the playhead to this caption's start time.")
                            Button {
                                model.removeCaption(id: caption.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(
                                EditorRowAccessibilityPolicy.label(
                                    for: .delete,
                                    kind: .caption,
                                    startSeconds: caption.startSeconds
                                )
                            )
                            .accessibilityHint("Removes this caption from the project.")
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

            inspectorActionGrid([
                EditorInspectorAction("Save Captions", systemImage: "checkmark.circle") {
                    model.saveCaptions()
                },
                EditorInspectorAction("Export Sidecars", systemImage: "square.and.arrow.up") {
                    model.exportCaptionSidecars()
                },
                EditorInspectorAction("Save Style", systemImage: "paintbrush") {
                    model.saveEditorSettings()
                }
            ])
            Text("Captions are stored as project-local JSON and exported as VTT, SRT, and text sidecars for packages.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func editorCursorInspector(manifest: ProjectManifest) -> some View {
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

    func editorPresetsInspector(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorSectionTitle("Project Preset")
            TextField("Preset name", text: $model.presetName)
                .textFieldStyle(.roundedBorder)
            TextField("Summary", text: $model.presetSummary, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                Button {
                    model.exportProjectPreset(preferences.snapshot)
                } label: {
                    Label("Save Preset...", systemImage: "square.and.arrow.up")
                }
                Button {
                    model.previewProjectPreset()
                } label: {
                    Label("Preview Apply...", systemImage: "eye")
                }
                Button {
                    model.applyProjectPreset()
                } label: {
                    Label("Apply Preset...", systemImage: "checkmark.circle")
                }
            }

            if !model.presetPreviewSummary.isEmpty {
                Text(model.presetPreviewSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }

            Divider()

            inspectorSectionTitle("Included")
            valueLine("Canvas, cursor, effects", "Editor settings")
            valueLine("Camera, audio, captions", "Editor settings")
            valueLine("Capture defaults", "From app settings")
            valueLine("Annotation defaults", "From app settings")
            valueLine("Export defaults", "From app settings")
            valueLine("Export preset IDs", manifest.exportPresets.isEmpty ? "None" : manifest.exportPresets.joined(separator: ", "))

            Divider()

            inspectorSectionTitle("Preserved On Apply")
            valueLine("Lesson metadata", "Unchanged")
            valueLine("Media files", "Unchanged")
            valueLine("Transcripts and captions", "Unchanged")
            valueLine("Markers and tracks", "Unchanged")
        }
    }

    func editorExportInspector(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.jobHistory.isEmpty {
                editorJobQueueInspector
                Divider()
            }

            inspectorSectionTitle("Render Settings")
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
            .onChange(of: model.renderFileType) { _, fileType in
                if fileType != .mov, model.renderCodec == .proRes {
                    model.renderCodec = .h264
                }
            }
            Picker("Resolution", selection: $model.renderResolution) {
                ForEach(RenderResolution.allCases) { resolution in
                    Text(resolution.title).tag(resolution)
                }
            }
            Picker("Frame rate", selection: $model.renderFrameRate) {
                ForEach(RenderFrameRate.allCases) { frameRate in
                    Text(frameRate.title).tag(frameRate)
                }
            }
            Picker("Codec", selection: $model.renderCodec) {
                ForEach(RenderCodec.allCases) { codec in
                    Text(codec.title).tag(codec)
                }
            }
            .onChange(of: model.renderCodec) { _, codec in
                if codec == .proRes {
                    model.renderFileType = .mov
                }
            }
            Toggle("Hardware acceleration", isOn: $model.renderHardwareAccelerationEnabled)
                .toggleStyle(.checkbox)
            Stepper("Concurrent exports: \(model.renderMaxConcurrentExports)", value: $model.renderMaxConcurrentExports, in: 1...8)
            Label("ProRes is available through Codec: ProRes with MOV output.", systemImage: "film")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Alpha channel and animated GIF export are unavailable until dedicated render pipelines are implemented.", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            inspectorSectionTitle("Local Render")
            TextField("Destination", text: $model.renderDestinationPath)
                .font(.system(.caption, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Choose...") { model.chooseRenderDestination() }
                Button("Check") { model.inspectRender(preferences.snapshot) }
                Button(model.isRendering ? "Rendering..." : "Export") { model.exportRender(preferences.snapshot) }
                    .disabled(!model.canStartEditorJob(.renderVideo))
            }

            Divider()
            inspectorSectionTitle("Local Share Package")
            TextField("Package folder", text: $model.sharePackageDestinationPath)
                .font(.system(.caption, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            TextField("Final video", text: $model.shareFinalVideoPath)
                .font(.system(.caption, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Folder...") { model.chooseSharePackageDestination() }
                Button("Video...") { model.chooseShareFinalVideo() }
                Button(model.isBuildingSharePackage ? "Packaging..." : "Build Package") { model.buildLocalSharePackage() }
                    .disabled(!model.canStartEditorJob(.sharePackage))
            }

            Divider()
            inspectorSectionTitle("Raw Assets")
            TextField("Extract folder", text: $model.rawAssetDestinationPath)
                .font(.system(.caption, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Folder...") { model.chooseRawAssetDestination() }
                Button(model.isExtractingRawAssets ? "Extracting..." : "Extract Raw Assets") { model.extractRawAssets() }
                    .disabled(!model.canStartEditorJob(.rawAssetExtract))
            }

            Divider()
            inspectorSectionTitle("Course Package")
            Button(model.isPackagingLearnHouse ? "Packaging..." : "Package LearnHouse") {
                model.packageLearnHouse(preferences.snapshot)
            }
            .disabled(!model.canStartEditorJob(.learnHousePackage) || manifest.media.screen == nil)

            Divider()
            inspectorSectionTitle("Publishing")
            Text("Publishing connectors are intentionally gated. Local render, share packages, raw asset extraction, and LearnHouse packages are the only active export actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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

    var validationIssuesList: some View {
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

    func inspectorSectionTitle(_ title: String) -> some View {
        LessonMeldInspectorSectionTitle(title: title)
    }

    func compactNumberField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func numericStringSlider(
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

    func colorPickerRow(_ title: String, selection: Binding<RGBAColor>) -> some View {
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
                .accessibilityLabel("\(title) \(accessibilityName(for: color))")
                .accessibilityValue(selection.wrappedValue == color ? "Selected" : "Not selected")
            }
        }
    }

    var canvasColorSwatches: [RGBAColor] {
        [.black, .white, .purple, .blue, .cyan, .green, .amber, .pink]
    }

    func accessibilityName(for color: RGBAColor) -> String {
        switch color {
        case .black: "black"
        case .white: "white"
        case .purple: "purple"
        case .blue: "blue"
        case .cyan: "cyan"
        case .green: "green"
        case .amber: "amber"
        case .pink: "pink"
        case .red: "red"
        case .yellow: "yellow"
        default: "color"
        }
    }

    func valueLine(_ label: String, _ value: String) -> some View {
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

}
