import AppKit
import AVFoundation
import AVKit
import DMLessonMeldCore
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
                    if let outputPath = latestJob.outputPath {
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

    func editorAudioInspector(manifest: ProjectManifest) -> some View {
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
            Toggle("Hardware acceleration", isOn: $model.renderHardwareAccelerationEnabled)
                .toggleStyle(.checkbox)
            Stepper("Concurrent exports: \(model.renderMaxConcurrentExports)", value: $model.renderMaxConcurrentExports, in: 1...8)
            Toggle("Alpha channel", isOn: $model.renderAlphaChannelEnabled)
                .toggleStyle(.checkbox)
            Toggle("Animated GIF", isOn: $model.renderAnimatedGIFEnabled)
                .toggleStyle(.checkbox)
            Toggle("ProRes", isOn: $model.renderProResEnabled)
                .toggleStyle(.checkbox)

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

    func mediaTimelineEditor(manifest: ProjectManifest) -> some View {
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
                .keyboardShortcut("b", modifiers: [.option])
                Button {
                    model.addZoomAtPlayhead()
                    persistTimelineEditChanges(for: .moveZoom)
                    editorInspectorTab = .zooms
                } label: {
                    Label("Zoom", systemImage: "plus.magnifyingglass")
                }
                .keyboardShortcut("z", modifiers: [.option])
                Button {
                    model.addAudioVolumeRegionAtPlayhead()
                    persistTimelineEditChanges(for: .moveAudioVolume)
                    editorInspectorTab = .audio
                } label: {
                    Label("Volume", systemImage: "speaker.wave.2")
                }
                .keyboardShortcut("v", modifiers: [.option])
                Button {
                    model.addSpeedRegionAtPlayhead(rate: 2)
                    persistTimelineEditChanges(for: .moveSpeed)
                    editorInspectorTab = .audio
                } label: {
                    Label("Speed", systemImage: "speedometer")
                }
                .keyboardShortcut("s", modifiers: [.option])
                Button {
                    model.addOverlayAtPlayhead(kind: .text)
                    persistTimelineEditChanges(for: .moveOverlay)
                    editorInspectorTab = .overlays
                } label: {
                    Label("Overlay", systemImage: "textformat")
                }
                .keyboardShortcut("t", modifiers: [.option])
                Button {
                    model.addCaptionAtPlayhead()
                    persistTimelineEditChanges(for: .moveCaption)
                    editorInspectorTab = .captions
                } label: {
                    Label("Caption", systemImage: "captions.bubble")
                }
                .keyboardShortcut("c", modifiers: [.option])
                Button {
                    model.addCursorHiddenRangeAtPlayhead()
                    persistTimelineEditChanges(for: .moveCursorHide)
                    editorInspectorTab = .cursor
                } label: {
                    Label("Hide Cursor", systemImage: "cursorarrow.slash")
                }
                .keyboardShortcut("h", modifiers: [.option])
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
                    .accessibilityLabel("Timeline scale")
                    .accessibilityValue(String(format: "%.1fx", timelineZoom))
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
        .focusable()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video timeline")
        .accessibilityHint("Use Left and Right Arrow to move the playhead. Use Delete to remove the selected timeline item.")
        .onMoveCommand { direction in
            switch direction {
            case .left:
                model.stepPlayhead(by: -1)
            case .right:
                model.stepPlayhead(by: 1)
            default:
                break
            }
        }
        .onDeleteCommand {
            deleteSelectedTimelineItem()
        }
    }

    var editorTimelineDuration: Double {
        max(model.previewDurationSeconds, secondsValue(model.sourceDurationSeconds) ?? 0, 1)
    }

    func timelineRuler(width: CGFloat, duration: Double) -> some View {
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

    func timelineLane<Content: View>(
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) timeline lane")
        .accessibilityHint("Contains editable \(title.lowercased()) regions.")
    }

    func clipTimelineContent(width: CGFloat, duration: Double) -> some View {
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
                .accessibilityLabel("Trim start handle")
                .accessibilityValue(formatSeconds(trimStart))
                .accessibilityHint("Drag to set trim start, or press Option I to set it to the playhead.")
            trimHandle("Out")
                .offset(x: timelineX(trimEnd, width: width, duration: duration) - 5)
                .gesture(timelineDragGesture(action: .trimEnd, id: "trim-end", start: trimStart, end: trimEnd, width: width, duration: duration))
                .help("Drag to set trim end")
                .accessibilityLabel("Trim end handle")
                .accessibilityValue(formatSeconds(trimEnd))
                .accessibilityHint("Drag to set trim end, or press Option O to set it to the playhead.")
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

    func cutTimelineContent(width: CGFloat, duration: Double) -> some View {
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

    func audioTimelineContent(width: CGFloat, duration: Double) -> some View {
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

    func speedTimelineContent(width: CGFloat, duration: Double) -> some View {
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

    func zoomTimelineContent(width: CGFloat, duration: Double) -> some View {
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

    func overlayTimelineContent(width: CGFloat, duration: Double) -> some View {
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

    func captionTimelineContent(width: CGFloat, duration: Double) -> some View {
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

    func cameraTimelineContent(width: CGFloat, duration: Double) -> some View {
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

    func cursorTimelineContent(width: CGFloat, duration: Double) -> some View {
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

    func markerTimelineContent(width: CGFloat, duration: Double) -> some View {
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(marker.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Timeline marker" : marker.title)
                    .accessibilityValue("\(formatSeconds(seconds))\(selectedTimelineItem == .marker(marker.id) ? ", Selected" : "")")
                    .accessibilityHint("Select to edit this marker. Use the context menu to jump, duplicate, or remove it.")
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

    func timelineBlock(
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) timeline item")
            .accessibilityValue(timelineItemAccessibilityValue(start: start, end: end, isEnabled: isEnabled, isSelected: isSelected))
            .accessibilityHint("Select to edit. Use the context menu for jump, enable, duplicate, or remove actions where available.")
    }

    func playheadLine(width: CGFloat, duration: Double) -> some View {
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

    func trimHandle(_ title: String) -> some View {
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

    func timelineResizeHandle() -> some View {
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
            .accessibilityLabel("Resize timeline item")
            .accessibilityHint("Drag horizontally to adjust this item's start or end time.")
    }

    func timelineItemAccessibilityValue(start: Double, end: Double, isEnabled: Bool, isSelected: Bool) -> String {
        var parts = [
            "\(formatSeconds(start)) to \(formatSeconds(end))",
            isEnabled ? "Enabled" : "Disabled"
        ]
        if isSelected {
            parts.append("Selected")
        }
        return parts.joined(separator: ", ")
    }

    func timelineDragGesture(
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

    func applyTimelineDrag(_ drag: TimelineDragState, delta: Double, duration: Double) {
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

    func persistTimelineEditChanges(for action: TimelineDragAction) {
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

    func deleteSelectedTimelineItem() {
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

    func timelineX(_ seconds: Double, width: CGFloat, duration: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        let trackWidth = max(0, width - timelineTrackInset)
        return timelineTrackInset + min(max(0, CGFloat(seconds / duration) * trackWidth), trackWidth)
    }

    func timelineSeconds(_ x: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        let trackWidth = max(1, width - timelineTrackInset)
        let trackX = min(max(0, x - timelineTrackInset), trackWidth)
        return Double(trackX / trackWidth) * duration
    }

    func timelineDeltaSeconds(_ translation: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        let trackWidth = max(1, width - timelineTrackInset)
        return Double(translation / trackWidth) * duration
    }

    var timelineTrackInset: CGFloat { 76 }

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

    @ViewBuilder var canvasPreviewBackground: some View {
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

    @ViewBuilder var zoomFocusOverlay: some View {
        if let zoomID = selectedZoomID,
           let zoom = model.zoomRow(id: zoomID),
           let centerX = secondsValue(zoom.centerX),
           let centerY = secondsValue(zoom.centerY),
           let size = secondsValue(zoom.size) {
            GeometryReader { proxy in
                let contentFrame = previewContentFrame(in: proxy.size)
                let boxWidth = max(40, contentFrame.width * CGFloat(size))
                let boxHeight = max(40, contentFrame.height * CGFloat(size))
                let focusPoint = EditorNormalizedGeometry.topDownPoint(x: centerX, y: centerY, in: contentFrame)
                let positionX = min(max(focusPoint.x, contentFrame.minX + boxWidth / 2), contentFrame.maxX - boxWidth / 2)
                let positionY = min(max(focusPoint.y, contentFrame.minY + boxHeight / 2), contentFrame.maxY - boxHeight / 2)
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .frame(width: boxWidth, height: boxHeight)
                    .position(x: positionX, y: positionY)
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
                                let x = Double((value.location.x - contentFrame.minX) / max(contentFrame.width, 1))
                                let y = Double((value.location.y - contentFrame.minY) / max(contentFrame.height, 1))
                                model.updateZoomFocus(
                                    id: zoomID,
                                    centerX: x,
                                    centerY: y
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

    @ViewBuilder var overlayPreviewOverlay: some View {
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
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(overlay.kind.title) overlay")
                            .accessibilityValue("Starts \(overlay.startSeconds), ends \(overlay.endSeconds)\(selectedTimelineItem == .overlay(overlay.id) ? ", selected" : "")")
                            .accessibilityHint("Select to edit this overlay. Drag to move it, or use inspector fields for keyboard editing.")
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

    @ViewBuilder var captionPreviewOverlay: some View {
        if model.captionBurnInEnabled, let caption = model.activeCaption(at: model.currentTimeSeconds) {
            GeometryReader { proxy in
                let contentFrame = previewContentFrame(in: proxy.size)
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
                        .frame(maxWidth: min(760, max(contentFrame.width - 64, 1)))
                        .padding(.horizontal, 32)
                        .padding(.vertical, max(18, CGFloat((secondsValue(model.captionSafeMargin) ?? 0.07) * Double(contentFrame.height))))
                        .onTapGesture {
                            selectedTimelineItem = .caption(caption.id)
                            editorInspectorTab = .captions
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Caption overlay")
                        .accessibilityValue(caption.text)
                        .accessibilityHint("Select to edit this caption in the Captions panel.")
                    if model.captionPlacement == .top {
                        Spacer()
                    }
                    if model.captionPlacement == .middle {
                        Spacer()
                    }
                }
                .frame(width: contentFrame.width, height: contentFrame.height)
                .position(x: contentFrame.midX, y: contentFrame.midY)
            }
            .allowsHitTesting(true)
        }
    }

    @ViewBuilder func overlayPreview(_ overlay: EditableOverlayRow) -> some View {
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

    func overlayResizeHandle() -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.black.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .accessibilityLabel("Resize overlay")
            .accessibilityHint("Drag to resize the selected overlay. Use Width and Height fields in the inspector for keyboard editing.")
    }

    @ViewBuilder func highlightPreview(_ overlay: EditableOverlayRow) -> some View {
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

    func overlayPreviewFrame(_ overlay: EditableOverlayRow, in contentFrame: CGRect) -> CGRect {
        let x = CGFloat(secondsValue(overlay.x) ?? 0)
        let y = CGFloat(secondsValue(overlay.y) ?? 0)
        let width = CGFloat(secondsValue(overlay.width) ?? 0.2)
        let height = CGFloat(secondsValue(overlay.height) ?? 0.15)
        return EditorNormalizedGeometry.topDownFrame(
            for: NormalizedEditRect(
                x: Double(x),
                y: Double(y),
                width: Double(width),
                height: Double(height)
            ),
            in: contentFrame,
            minimumSize: CGSize(width: 20, height: 20)
        )
    }

    @ViewBuilder var cursorPreviewOverlay: some View {
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

    @ViewBuilder func cursorPointerPreview(style: EditorCursorPointerStyle) -> some View {
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

    func previewContentFrame(in size: CGSize) -> CGRect {
        EditorNormalizedGeometry.contentFrame(
            in: size,
            padding: model.canvasPreviewPadding,
            aspectRatio: model.canvasPreviewAspectRatio
        )
    }

    func previewPoint(_ point: NormalizedCapturePoint, in frame: CGRect) -> CGPoint {
        EditorNormalizedGeometry.flippedTopDownPoint(for: point, in: frame)
    }

    var selectedZoomID: String? {
        if case .zoom(let id) = selectedTimelineItem {
            return id
        }
        return nil
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
