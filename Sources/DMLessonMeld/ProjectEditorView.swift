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
            ScrollView {
                projectDashboard(summary: summary, manifest: manifest)
                    .contentPadding(top: 44)
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
}

private struct ProjectVideoPlayer: NSViewRepresentable {
    var player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
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

private struct EditableCutRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var reason: String
    var isEnabled: Bool
}

private struct EditableZoomRow: Identifiable, Equatable {
    var id: String
    var startSeconds: String
    var endSeconds: String
    var scale: String
    var centerX: String
    var centerY: String
    var size: String
    var isEnabled: Bool
}

private struct EditableMarkerRow: Identifiable, Equatable {
    var id: String
    var kind: ProjectTimelineMarkerKind
    var timeSeconds: String
    var title: String
    var notes: String
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
    @Published var zoomRows: [EditableZoomRow] = []
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
                isEnabled: true
            )
        )
    }

    func removeZoom(id: String) {
        zoomRows.removeAll { $0.id == id }
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
        var plan = try RenderPlan.make(
            manifest: manifest,
            projectURL: projectURL,
            destinationURL: destinationURL,
            preset: RenderPreset(fileType: renderFileType, quality: renderQuality),
            editDecisionList: editDecisionList
        )
        if plan.webcamOverlay != nil, manifest.capture == nil {
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
            zoomRows = []
            editValidationIssues = []
            setError("Could not load edit decisions: \(error.localizedDescription)")
        }
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
                isEnabled: row.isEnabled
            )
        }

        let existing = lastEditDecisionList ?? defaultEditDecisionList(projectURL: projectURL, manifest: manifest)
        return EditDecisionList(
            id: existing.id,
            sourceMediaURL: manifest.media.screen.map { ProjectBundle.fileURL(for: $0, in: projectURL) },
            sourceDurationSeconds: duration,
            trimRange: trimRange,
            cuts: cuts,
            speedRegions: existing.speedRegions,
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

    private func parseUnitInterval(_ value: String, label: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), number >= 0, number <= 1 else {
            throw ProjectEditorError.invalidNumber("\(label) must be between 0 and 1.")
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
