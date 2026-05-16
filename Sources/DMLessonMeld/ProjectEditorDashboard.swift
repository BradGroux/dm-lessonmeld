import AppKit
import DMLessonMeldCore
import SwiftUI

extension ProjectEditorView {
    func projectDashboard(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            projectHeader(summary: summary, manifest: manifest)
            lessonOverviewPanel(summary: summary, manifest: manifest)
            recordPanel
            projectAssetsPanel(summary: summary, manifest: manifest)
            lessonMarkersPanel(manifest: manifest)
            metadataPanel
            annotationProjectPanel(manifest: manifest)
            technicalDetailsPanel(summary: summary, manifest: manifest)
        }
    }

    func projectHeader(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
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
                if model.hasUnsavedChanges {
                    statusPill("Unsaved", systemImage: "circle.dotted", tint: .orange)
                        .help(model.dirtySummary)
                }
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

                Button {
                    model.revealProject()
                } label: {
                    Label("Reveal", systemImage: "arrow.up.forward.app")
                }
                .disabled(model.projectURL == nil)
            }
        }
    }

    func lessonOverviewPanel(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
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

    func nextStepCard(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
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
                                confirmProjectTransition("import a video") {
                                    model.importVideoForEditing(preferences.snapshot)
                                }
                            } label: {
                                Label("Import Video", systemImage: "film.badge.plus")
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
                                Label("Check Export", systemImage: "checkmark.seal")
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

    func readinessCard(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
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
                    "Edit Video",
                    status: reviewStatus(manifest),
                    detail: reviewDetail(manifest),
                    systemImage: "film",
                    tint: manifest.media.screen == nil ? .secondary : .blue
                )
                readinessLine(
                    "Export/Package",
                    status: exportStatus(summary, manifest: manifest),
                    detail: exportDetail(summary, manifest: manifest),
                    systemImage: "square.and.arrow.up",
                    tint: exportTint(summary, manifest: manifest)
                )
            }
        }
    }

    func statusPill(_ title: String, systemImage: String, tint: Color) -> some View {
        LessonMeldStatusPill(title: title, systemImage: systemImage, tint: tint)
    }

    func readinessLine(_ title: String, status: String, detail: String, systemImage: String, tint: Color) -> some View {
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

    func overviewStatus(
        summary: ProjectBundleSummary,
        manifest: ProjectManifest
    ) -> (title: String, detail: String, systemImage: String, tint: Color) {
        if manifest.media.screen == nil {
            return (
                "Record or import video",
                "This bundle has lesson structure, but no source video yet. Record a take or import an existing video to start editing.",
                "record.circle",
                .orange
            )
        }

        if hasBlockingIssues(summary) {
            return (
                "Fix project issues",
                "The video exists, but the bundle has a blocking issue before it can export cleanly.",
                "xmark.octagon",
                .red
            )
        }

        if !summary.issues.isEmpty {
            return (
                "Check warnings",
                "The video can be edited, but there are warnings worth checking before export.",
                "exclamationmark.triangle",
                .orange
            )
        }

        if model.cutRows.isEmpty && model.zoomRows.isEmpty && model.annotationItemCount == 0 {
            return (
                "Edit the video",
                "Preview the take, trim dead air, add cuts, zooms, overlays, captions, and annotations where the lesson needs polish.",
                "play.rectangle",
                .blue
            )
        }

        return (
            "Ready to export/package",
            "The lesson has media and edits. Export a video or package the lesson for LearnHouse.",
            "checkmark.seal.fill",
            .green
        )
    }

    func projectSubtitle(_ manifest: ProjectManifest) -> String {
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

        return "Local lesson bundle ready for recording, editing, export, and packaging."
    }

    func hasBlockingIssues(_ summary: ProjectBundleSummary) -> Bool {
        summary.issues.contains { $0.severity == .error }
    }

    func hasAudio(_ manifest: ProjectManifest) -> Bool {
        manifest.media.microphoneAudio != nil || manifest.media.systemAudio != nil || manifest.media.hasEmbeddedSystemAudio
    }

    func audioStatus(_ manifest: ProjectManifest) -> String {
        let hasSystemAudio = manifest.media.systemAudio != nil || manifest.media.hasEmbeddedSystemAudio
        if manifest.media.microphoneAudio != nil, hasSystemAudio {
            return "Mic + System"
        }
        if manifest.media.microphoneAudio != nil {
            return "Mic"
        }
        if hasSystemAudio {
            return "System"
        }
        return "Optional"
    }

    func audioDetail(_ manifest: ProjectManifest) -> String {
        var files = [manifest.media.microphoneAudio?.relativePath, manifest.media.systemAudio?.relativePath].compactMap { $0 }
        if manifest.media.hasEmbeddedSystemAudio {
            files.append("screen.mp4 (embedded system audio)")
        }
        return files.isEmpty ? "No voice or system audio has been captured yet." : files.joined(separator: " + ")
    }

    func reviewStatus(_ manifest: ProjectManifest) -> String {
        guard manifest.media.screen != nil else { return "Waiting" }
        if model.cutRows.isEmpty && model.zoomRows.isEmpty && model.annotationItemCount == 0 {
            return "Ready"
        }
        return "Edited"
    }

    func reviewDetail(_ manifest: ProjectManifest) -> String {
        guard manifest.media.screen != nil else { return "Record or import video first, then edit the take." }

        let pieces = [
            countLabel(model.cutRows.filter(\.isEnabled).count, singular: "cut"),
            countLabel(model.zoomRows.filter(\.isEnabled).count, singular: "zoom"),
            countLabel(model.annotationItemCount, singular: "annotation")
        ].filter { !$0.hasPrefix("0 ") }

        return pieces.isEmpty ? "Preview, trim, cut retakes, add zooms, overlays, captions, and annotations." : pieces.joined(separator: ", ")
    }

    func exportStatus(_ summary: ProjectBundleSummary, manifest: ProjectManifest) -> String {
        if manifest.media.screen == nil { return "Waiting" }
        if hasBlockingIssues(summary) { return "Blocked" }
        if !summary.issues.isEmpty { return "Check" }
        return "Ready"
    }

    func exportDetail(_ summary: ProjectBundleSummary, manifest: ProjectManifest) -> String {
        if manifest.media.screen == nil {
            return "Export unlocks after recording or importing video."
        }
        if hasBlockingIssues(summary) {
            return "Resolve bundle errors before exporting."
        }
        if !summary.issues.isEmpty {
            return "Warnings are visible in technical details."
        }
        return "Video export and LearnHouse packaging are available."
    }

    func exportTint(_ summary: ProjectBundleSummary, manifest: ProjectManifest) -> Color {
        if manifest.media.screen == nil { return .gray }
        if hasBlockingIssues(summary) { return .red }
        if !summary.issues.isEmpty { return .orange }
        return .green
    }

    func countLabel(_ count: Int, singular: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
    }

    func openAnnotationOverlayFromEditor() {
        let storeURL = model.projectURL == nil ? nil : model.prepareAnnotationSidecarForOverlay()
        annotationOverlay.open(preferences: preferences.snapshot, annotationStoreURL: storeURL, forceToolbarVisible: true)
    }

    var firstRunDashboard: some View {
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

    var recoveryNotice: some View {
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

    var startLessonPanel: some View {
        EditorPanel(title: "Start a Lesson", subtitle: "Record into a local lesson project, or import an existing video and edit it immediately.") {
            HStack(spacing: 10) {
                Button {
                    quickRecorder.presentControlBar(preferences: preferences)
                } label: {
                    Label(quickRecorder.isRecording ? "Show Recorder" : "Record Lesson", systemImage: quickRecorder.isRecording ? "slider.horizontal.3" : "record.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    confirmProjectTransition("import a video") {
                        model.importVideoForEditing(preferences.snapshot)
                    }
                } label: {
                    Label("Import Video", systemImage: "film.badge.plus")
                }

                Button {
                    confirmProjectTransition("create a new project") {
                        model.newProject(preferences.snapshot)
                    }
                } label: {
                    Label("New Project", systemImage: "doc.badge.plus")
                }

                Button {
                    confirmProjectTransition("open another project") {
                        model.openProject()
                    }
                } label: {
                    Label("Open Project", systemImage: "folder")
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
                        confirmProjectTransition("open the last recorded lesson") {
                            model.loadProject(URL(fileURLWithPath: projectPath))
                        }
                    } label: {
                        Label("Edit Last Lesson", systemImage: "film")
                    }
                    Text(URL(fileURLWithPath: projectPath).lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("Import Video creates a local lesson project from an MP4 or MOV and opens the editor for preview, cuts, zooms, trims, annotations, and export.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var workflowPanel: some View {
        EditorPanel(title: "Record, Edit, Export", subtitle: "The normal path for a curriculum lesson.") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(LessonWorkflowStage.allCases) { stage in
                    workflowRow(stage.title, stage.detail, systemImage: stage.systemImage) {
                        runWorkflowStage(stage)
                    }
                }
            }
        }
    }

    var appToolsPanel: some View {
        EditorPanel(title: "App Tools", subtitle: "Setup, preferences, commands, and live annotation are always local.") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(quickRecorder.permissionPreflight.items) { item in
                    permissionRow(item)
                }

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

    var appToolButtons: some View {
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

    func workflowRow(_ title: String, _ detail: String, systemImage: String, action: @escaping () -> Void) -> some View {
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

    func permissionRow(_ item: PermissionPreflightItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.isGranted ? "checkmark.circle.fill" : item.id.systemImage)
                .foregroundStyle(item.isGranted ? Color.green : (item.isBlocking ? Color.orange : Color.secondary))
            Text(item.id.shortTitle)
                .font(.subheadline.weight(.semibold))
            Text(item.need.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(item.statusTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.isGranted ? Color.green : (item.isBlocking ? Color.orange : Color.secondary))
        }
    }

    var emptyState: some View {
        EditorPanel(title: "Create or Open a Lesson Project", subtitle: "The editor works directly against local lesson bundles.") {
            HStack {
                Button {
                    confirmProjectTransition("import a video") {
                        model.importVideoForEditing(preferences.snapshot)
                    }
                } label: {
                    Label("Import Video", systemImage: "film.badge.plus")
                }

                Button {
                    confirmProjectTransition("create a new project") {
                        model.newProject(preferences.snapshot)
                    }
                } label: {
                    Label("New Project", systemImage: "doc.badge.plus")
                }

                Button {
                    confirmProjectTransition("open another project") {
                        model.openProject()
                    }
                } label: {
                    Label("Open Project", systemImage: "folder")
                }
            }
            Text("Importing a video creates a local lesson bundle with the media ready for preview, cuts, zooms, trims, annotations, and export.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var recorderEntryPanel: some View {
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

    var recordPanel: some View {
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
                        confirmProjectTransition("open the last recorded lesson") {
                            model.loadProject(URL(fileURLWithPath: projectPath))
                        }
                    } label: {
                        Label("Edit Last Lesson", systemImage: "film")
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

    func projectSummary(_ summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
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

    func lessonMarkersPanel(manifest: ProjectManifest) -> some View {
        EditorPanel(title: "Markers", subtitle: "Plan chapters before recording, flag moments while recording, or clean up the lesson outline while editing.") {
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
                Text("Markers are hidden for free-form editing. Existing markers stay in the project and exports can still use them.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func markerKindLabel(_ kind: ProjectTimelineMarkerKind) -> String {
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

    var metadataPanel: some View {
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

    func annotationProjectPanel(manifest: ProjectManifest) -> some View {
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

    func annotationSaveStatus(_ manifest: ProjectManifest) -> String {
        manifest.media.annotations == nil ? "Not saved yet" : model.annotationSidecarStatus
    }

    func projectAssetsPanel(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        let groups = projectAssetGroups(summary: summary, manifest: manifest)

        return EditorPanel(
            title: "Project Assets",
            subtitle: "The .dmlm item is the editable lesson project. Source media, edit sidecars, and rendered exports are separate files."
        ) {
            assetBrowserSummary(summary: summary, manifest: manifest)

            ForEach(groups) { group in
                assetGroupView(group)
            }
        }
    }

    func editorAssetsInspector(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        let groups = projectAssetGroups(summary: summary, manifest: manifest)

        return VStack(alignment: .leading, spacing: 14) {
            assetBrowserSummary(summary: summary, manifest: manifest)

            ForEach(groups) { group in
                assetGroupView(group)
            }
        }
    }

    func assetBrowserSummary(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            valueLine("Editable project", model.projectURL?.lastPathComponent ?? "No project open")
            valueLine("Project package", model.projectURL?.path ?? "Not created yet")
            valueLine("Source video", manifest.media.screen?.relativePath ?? "Missing")
            valueLine("Rendered output", renderDestinationPathLabel)

            if !summary.issues.isEmpty {
                Divider()
                Label("\(countLabel(summary.issues.count, singular: "validation issue"))", systemImage: hasBlockingIssues(summary) ? "xmark.octagon" : "exclamationmark.triangle")
                    .foregroundStyle(hasBlockingIssues(summary) ? .red : .orange)
            }
        }
        .font(.subheadline)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LessonMeldDesign.rowFill, in: RoundedRectangle(cornerRadius: LessonMeldDesign.Radius.card, style: .continuous))
    }

    var renderDestinationPathLabel: String {
        let trimmed = model.renderDestinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Choose an export destination" }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    func assetGroupView(_ group: ProjectAssetGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(group.title, systemImage: group.systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(group.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(group.items) { item in
                    assetRow(item)
                }
            }
        }
    }

    func assetRow(_ item: ProjectAssetItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(item.statusTint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    assetStatusBadge(item.status, tint: item.statusTint)
                }

                Text(item.detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                ForEach(item.issues.indices, id: \.self) { index in
                    let issue = item.issues[index]
                    Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let byteCount = item.byteCount {
                    Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Button {
                        openAsset(item)
                    } label: {
                        Label("Open", systemImage: "play.rectangle")
                    }
                    .disabled(!item.canOpen || !assetExists(item))

                    Button {
                        revealAsset(item)
                    } label: {
                        Label("Reveal", systemImage: "arrow.up.forward.app")
                    }
                    .disabled(item.url == nil)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: LessonMeldDesign.Radius.card, style: .continuous))
    }

    func assetStatusBadge(_ status: String, tint: Color) -> some View {
        Text(status)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }

    func projectAssetGroups(summary: ProjectBundleSummary, manifest: ProjectManifest) -> [ProjectAssetGroup] {
        guard let projectURL = model.projectURL else { return [] }

        return [
            ProjectAssetGroup(
                id: "project",
                title: "Lesson Project",
                subtitle: "Editable package and manifest",
                systemImage: "shippingbox",
                items: [
                    projectBundleItem(projectURL: projectURL),
                    projectManifestItem(projectURL: projectURL, summary: summary)
                ]
            ),
            ProjectAssetGroup(
                id: "source-media",
                title: "Source Media",
                subtitle: "Original captured or imported video",
                systemImage: "film",
                items: sourceMediaItems(projectURL: projectURL, summary: summary, manifest: manifest)
            ),
            ProjectAssetGroup(
                id: "audio",
                title: "Audio",
                subtitle: "Voice and system tracks",
                systemImage: "waveform",
                items: audioAssetItems(projectURL: projectURL, summary: summary, manifest: manifest)
            ),
            ProjectAssetGroup(
                id: "edit-sidecars",
                title: "Edit Sidecars",
                subtitle: "Timeline, style, overlay, annotation, cursor, and caption data",
                systemImage: "slider.horizontal.3",
                items: editSidecarItems(projectURL: projectURL, summary: summary, manifest: manifest)
            ),
            ProjectAssetGroup(
                id: "outputs",
                title: "Exports",
                subtitle: "Rendered videos and package destinations",
                systemImage: "square.and.arrow.up",
                items: exportAssetItems()
            )
        ]
    }

    func sourceMediaItems(projectURL: URL, summary: ProjectBundleSummary, manifest: ProjectManifest) -> [ProjectAssetItem] {
        var items: [ProjectAssetItem] = [
            manifest.media.screen.map {
                assetItem(file: $0, title: "Primary screen video", projectURL: projectURL, summary: summary)
            } ?? missingAssetItem(
                id: "source-screen-missing",
                title: "Primary screen video",
                detail: "Record or import a video to create the editable source media.",
                systemImage: "display",
                status: "Missing",
                statusTint: .orange
            )
        ]

        items.append(
            manifest.media.webcam.map {
                assetItem(file: $0, title: "Webcam video", projectURL: projectURL, summary: summary)
            } ?? missingAssetItem(
                id: "source-webcam-optional",
                title: "Webcam video",
                detail: "Optional presenter camera track.",
                systemImage: "video",
                status: "Optional",
                statusTint: .secondary
            )
        )

        if let thumbnail = manifest.media.thumbnail {
            items.append(assetItem(file: thumbnail, title: "Thumbnail", projectURL: projectURL, summary: summary))
        }

        return items
    }

    func audioAssetItems(projectURL: URL, summary: ProjectBundleSummary, manifest: ProjectManifest) -> [ProjectAssetItem] {
        [
            manifest.media.microphoneAudio.map {
                assetItem(file: $0, title: "Microphone audio", projectURL: projectURL, summary: summary)
            } ?? missingAssetItem(
                id: "audio-mic-optional",
                title: "Microphone audio",
                detail: "Optional voice sidecar.",
                systemImage: "waveform",
                status: "Optional",
                statusTint: .secondary
            ),
            manifest.media.systemAudio.map {
                assetItem(file: $0, title: "System audio", projectURL: projectURL, summary: summary)
            } ?? missingAssetItem(
                id: "audio-system-optional",
                title: "System audio",
                detail: "Optional app/system sound sidecar.",
                systemImage: "speaker.wave.2",
                status: "Optional",
                statusTint: .secondary
            )
        ]
    }

    func editSidecarItems(projectURL: URL, summary: ProjectBundleSummary, manifest: ProjectManifest) -> [ProjectAssetItem] {
        var items = [
            knownProjectFileItem(
                fileName: EditorSettingsFile.defaultFileName,
                title: "Editor settings",
                systemImage: "slider.horizontal.3",
                projectURL: projectURL,
                summary: summary
            ),
            knownProjectFileItem(
                fileName: EditDecisionListFile.defaultFileName,
                title: "Timeline edit decisions",
                systemImage: "timeline.selection",
                projectURL: projectURL,
                summary: summary
            )
        ]

        if let cursorMetadata = manifest.media.cursorMetadata {
            items.append(assetItem(file: cursorMetadata, title: "Cursor and input metadata", projectURL: projectURL, summary: summary))
        }
        if let overlays = manifest.media.overlays {
            items.append(assetItem(file: overlays, title: "Timed overlays", projectURL: projectURL, summary: summary))
        } else {
            items.append(knownProjectFileItem(fileName: OverlayStoreFile.defaultFileName, title: "Timed overlays", systemImage: "square.on.square", projectURL: projectURL, summary: summary))
        }
        if let annotations = manifest.media.annotations {
            items.append(assetItem(file: annotations, title: "Annotations", projectURL: projectURL, summary: summary))
        }

        items.append(contentsOf: manifest.media.captions.map {
            assetItem(file: $0, title: assetTitle(for: $0.role), projectURL: projectURL, summary: summary)
        })
        items.append(contentsOf: manifest.media.transcripts.map {
            assetItem(file: $0, title: assetTitle(for: $0.role), projectURL: projectURL, summary: summary)
        })
        items.append(contentsOf: manifest.exportPresets.map { presetID in
            ProjectAssetItem(
                id: "preset-\(presetID)",
                title: "Export preset",
                detail: presetID,
                systemImage: "wand.and.stars",
                status: "Referenced",
                statusTint: .blue,
                byteCount: nil,
                url: nil,
                canOpen: false,
                issues: []
            )
        })
        items.append(contentsOf: manifest.media.attachments.map {
            assetItem(file: $0, title: "Attachment", projectURL: projectURL, summary: summary)
        })

        return items
    }

    func exportAssetItems() -> [ProjectAssetItem] {
        [
            configuredOutputItem(id: "render-output", title: "Rendered video", path: model.renderDestinationPath, systemImage: "film.stack"),
            configuredOutputItem(id: "trim-output", title: "Trim export", path: model.trimDestinationPath, systemImage: "scissors"),
            configuredOutputItem(id: "share-package-output", title: "Local share packages", path: model.sharePackageDestinationPath, systemImage: "shippingbox"),
            configuredOutputItem(id: "raw-assets-output", title: "Raw asset extraction", path: model.rawAssetDestinationPath, systemImage: "folder")
        ]
    }

    func projectBundleItem(projectURL: URL) -> ProjectAssetItem {
        ProjectAssetItem(
            id: "project-bundle",
            title: "Editable lesson project (.dmlm)",
            detail: projectURL.path,
            systemImage: "shippingbox",
            status: FileManager.default.fileExists(atPath: projectURL.path) ? "Project" : "Missing",
            statusTint: FileManager.default.fileExists(atPath: projectURL.path) ? .blue : .red,
            byteCount: nil,
            url: projectURL,
            canOpen: false,
            issues: []
        )
    }

    func projectManifestItem(projectURL: URL, summary: ProjectBundleSummary) -> ProjectAssetItem {
        let url = ProjectBundle.manifestURL(in: projectURL)
        return fileURLAssetItem(
            id: "project-manifest",
            title: "Project manifest",
            detail: ProjectBundle.manifestFileName,
            systemImage: "doc.text",
            url: url,
            expected: true,
            issues: issues(for: ProjectBundle.manifestFileName, summary: summary)
        )
    }

    func assetItem(file: ProjectFile, title: String, projectURL: URL, summary: ProjectBundleSummary) -> ProjectAssetItem {
        let url = ProjectBundle.fileURL(for: file, in: projectURL)
        return fileURLAssetItem(
            id: "\(file.role.rawValue)-\(file.relativePath)",
            title: title,
            detail: file.relativePath,
            systemImage: icon(for: file.role),
            url: url,
            expected: true,
            fallbackByteCount: file.byteCount,
            issues: issues(for: file.relativePath, summary: summary)
        )
    }

    func knownProjectFileItem(fileName: String, title: String, systemImage: String, projectURL: URL, summary: ProjectBundleSummary) -> ProjectAssetItem {
        fileURLAssetItem(
            id: "known-\(fileName)",
            title: title,
            detail: fileName,
            systemImage: systemImage,
            url: projectURL.appendingPathComponent(fileName),
            expected: false,
            issues: issues(for: fileName, summary: summary)
        )
    }

    func configuredOutputItem(id: String, title: String, path: String, systemImage: String) -> ProjectAssetItem {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return missingAssetItem(id: id, title: title, detail: "No destination selected.", systemImage: systemImage, status: "Not set", statusTint: .secondary)
        }

        let url = URL(fileURLWithPath: trimmed)
        let exists = FileManager.default.fileExists(atPath: url.path)
        return ProjectAssetItem(
            id: id,
            title: title,
            detail: url.path,
            systemImage: systemImage,
            status: exists ? "Exists" : "Configured",
            statusTint: exists ? .green : .blue,
            byteCount: byteCount(for: url, fallback: nil),
            url: url,
            canOpen: exists,
            issues: []
        )
    }

    func fileURLAssetItem(
        id: String,
        title: String,
        detail: String,
        systemImage: String,
        url: URL,
        expected: Bool,
        fallbackByteCount: Int64? = nil,
        issues: [ProjectValidationIssue]
    ) -> ProjectAssetItem {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let hasError = issues.contains { $0.severity == .error }
        let status: String
        let tint: Color

        if hasError {
            status = "Issue"
            tint = .red
        } else if !issues.isEmpty {
            status = "Warning"
            tint = .orange
        } else if exists {
            status = "Ready"
            tint = .green
        } else if expected {
            status = "Missing"
            tint = .red
        } else {
            status = "Not created"
            tint = .secondary
        }

        return ProjectAssetItem(
            id: id,
            title: title,
            detail: detail,
            systemImage: systemImage,
            status: status,
            statusTint: tint,
            byteCount: byteCount(for: url, fallback: fallbackByteCount),
            url: url,
            canOpen: exists,
            issues: issues
        )
    }

    func missingAssetItem(id: String, title: String, detail: String, systemImage: String, status: String, statusTint: Color) -> ProjectAssetItem {
        ProjectAssetItem(
            id: id,
            title: title,
            detail: detail,
            systemImage: systemImage,
            status: status,
            statusTint: statusTint,
            byteCount: nil,
            url: nil,
            canOpen: false,
            issues: []
        )
    }

    func issues(for relativePath: String, summary: ProjectBundleSummary) -> [ProjectValidationIssue] {
        summary.issues.filter { issue in
            issue.path == relativePath || issue.path == "./\(relativePath)"
        }
    }

    func byteCount(for url: URL, fallback: Int64?) -> Int64? {
        if let fallback { return fallback }
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    func assetExists(_ item: ProjectAssetItem) -> Bool {
        guard let url = item.url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func openAsset(_ item: ProjectAssetItem) {
        guard let url = item.url, item.canOpen, FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    func revealAsset(_ item: ProjectAssetItem) {
        guard let url = item.url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        let parent = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) {
            NSWorkspace.shared.activateFileViewerSelecting([parent])
        }
    }

    func markerPanel(manifest: ProjectManifest) -> some View {
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

    func technicalDetailsPanel(summary: ProjectBundleSummary, manifest: ProjectManifest) -> some View {
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
                                Label(assetTitle(for: file.role), systemImage: icon(for: file.role))
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

    func technicalSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    func valueRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    func issueRow(_ severity: String, _ message: String, path: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(severity.capitalized, systemImage: severity == "error" ? "xmark.octagon" : "exclamationmark.triangle")
                .foregroundStyle(severity == "error" ? .red : .orange)
                .frame(width: 120, alignment: .leading)
            Text(path.map { "\($0): \(message)" } ?? message)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func icon(for role: ProjectFileRole) -> String {
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

    func assetTitle(for role: ProjectFileRole) -> String {
        switch role {
        case .screenVideo: "Primary screen video"
        case .webcamVideo: "Webcam video"
        case .microphoneAudio: "Microphone audio"
        case .systemAudio: "System audio"
        case .cursorMetadata: "Cursor and input metadata"
        case .annotations: "Annotations"
        case .overlays: "Timed overlays"
        case .captions: "Captions"
        case .transcript: "Transcript"
        case .thumbnail: "Thumbnail"
        case .manifest: "Project manifest"
        case .attachment: "Attachment"
        }
    }

    func formatSeconds(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, remainder)
    }

    func secondsValue(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let seconds = Double(trimmed), seconds.isFinite else { return nil }
        return max(0, seconds)
    }
}
