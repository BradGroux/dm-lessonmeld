import AppKit
import AVFoundation
import AVKit
import DMLessonMeldCore
import SwiftUI
import UniformTypeIdentifiers

struct ProjectEditorView: View {
    @Environment(\.openWindow) var openWindow
    @ObservedObject var appRouter: LessonMeldAppRouter
    @ObservedObject var preferences: AppPreferencesController
    @ObservedObject var annotationOverlay: AnnotationOverlayCoordinator
    @ObservedObject var quickRecorder: QuickRecorderModel
    let fallbackAnnotationOverlayHandler: (LessonMeldPreferences) -> Void
    @StateObject var model = ProjectEditorModel()
    @State var showRecoveryNotice = false
    @State var didShowRecoveryNoticeThisLaunch = false
    @State var showTechnicalDetails = false
    @State var showLessonMarkers = true
    @State var editorInspectorTab: EditorInspectorTab = .edits
    @State var timelineZoom = 1.0
    @State var activeTimelineDrag: TimelineDragState?
    @State var activeOverlayDrag: OverlayPreviewDragState?
    @State var activeOverlayResizeDrag: OverlayPreviewResizeDragState?
    @State var selectedTimelineItem: TimelineSelection?
    @AppStorage("LessonMeld.mediaEditor.inspectorVisible") var mediaEditorInspectorVisible = true
    @AppStorage("LessonMeld.mediaEditor.timelineVisible") var mediaEditorTimelineVisible = true
    @AppStorage("LessonMeld.mediaEditor.inspectorWidth") var mediaEditorInspectorWidth = 420.0

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
            quickRecorder.openProjectHandler = { projectURL in
                confirmProjectTransition("open the recorded lesson") {
                    model.loadProject(projectURL)
                }
            }
            quickRecorder.annotationOverlayHandler = { [annotationOverlay, weak model] preferences in
                let storeURL = model?.projectURL == nil ? nil : model?.prepareAnnotationSidecarForOverlay()
                annotationOverlay.open(preferences: preferences, annotationStoreURL: storeURL, forceToolbarVisible: true)
            }
            LocalAppControlBridge.shared.configure(quickRecorder: quickRecorder, preferences: preferences)
            ProjectOpenRouter.shared.registerConsumer { projectURL in
                confirmProjectTransition("open another project") {
                    model.loadProject(projectURL)
                }
            }
            syncProjectCommandState()
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
            model.closeProject()
            appRouter.updateProjectCommandState(.empty)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            quickRecorder.refreshPermissions(updateMessage: false)
        }
        .onReceive(appRouter.$importVideoRequest.compactMap(\.self)) { _ in
            confirmProjectTransition("import a video") {
                model.importVideoForEditing(preferences.snapshot)
            }
        }
        .onReceive(appRouter.$projectCommandRequest.compactMap(\.self)) { request in
            handleProjectCommand(request.command)
        }
        .onReceive(model.$projectURL) { _ in syncProjectCommandState() }
        .onReceive(model.$manifest) { _ in syncProjectCommandState() }
        .onReceive(model.$isRendering) { _ in syncProjectCommandState() }
        .onReceive(model.$dirtyAreas) { _ in syncProjectCommandState() }
        .onChange(of: model.metadataDirtyFingerprint) { _, _ in model.refreshDirtyState(.metadata) }
        .onChange(of: model.markerRows) { _, _ in model.refreshDirtyState(.markers) }
        .onChange(of: model.editDecisionDirtyFingerprint) { _, _ in model.refreshDirtyState(.editDecisions) }
        .onChange(of: model.editorSettingsDirtyFingerprint) { _, _ in model.refreshDirtyState(.editorSettings) }
        .onChange(of: model.overlayRows) { _, _ in model.refreshDirtyState(.overlays) }
        .onChange(of: model.captionDirtyFingerprint) { _, _ in model.refreshDirtyState(.captions) }
        .confirmsWindowClose(confirmWindowClose)
    }

    func applyLaunchPreferences() {
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

    func syncProjectCommandState() {
        appRouter.updateProjectCommandState(
            LessonMeldProjectCommandState(
                hasProject: model.projectURL != nil,
                hasScreenVideo: model.manifest?.media.screen != nil,
                isRendering: model.isRendering,
                hasUnsavedChanges: model.hasUnsavedChanges
            )
        )
    }

    func handleProjectCommand(_ command: LessonMeldProjectCommand) {
        switch command {
        case .newProject:
            confirmProjectTransition("create a new project") {
                model.newProject(preferences.snapshot)
            }
        case .openProject:
            confirmProjectTransition("open another project") {
                model.openProject()
            }
        case .importVideo:
            confirmProjectTransition("import a video") {
                model.importVideoForEditing(preferences.snapshot)
            }
        case .revealProject:
            model.revealProject()
        case .saveEdits:
            model.saveAllDirtyChanges()
        case .exportVideo:
            model.exportRender(preferences.snapshot)
        }
    }

    func confirmProjectTransition(_ actionName: String, proceed: () -> Void) {
        guard model.hasUnsavedChanges else {
            proceed()
            return
        }

        switch unsavedChangesAlert(actionName: actionName).runModal() {
        case .alertFirstButtonReturn:
            model.saveAllDirtyChanges()
            if !model.hasUnsavedChanges {
                proceed()
            }
        case .alertSecondButtonReturn:
            proceed()
        default:
            return
        }
    }

    func confirmWindowClose() -> Bool {
        guard model.hasUnsavedChanges else { return true }

        switch unsavedChangesAlert(actionName: "close this project").runModal() {
        case .alertFirstButtonReturn:
            model.saveAllDirtyChanges()
            return !model.hasUnsavedChanges
        case .alertSecondButtonReturn:
            model.clearAllDirtyChanges()
            return true
        default:
            return false
        }
    }

    func unsavedChangesAlert(actionName: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes before you \(actionName)?"
        alert.informativeText = "Unsaved areas: \(model.dirtySummary)."
        alert.addButton(withTitle: "Save and Continue")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    func confirmRevertUnsavedChanges() {
        guard model.hasUnsavedChanges else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard unsaved project changes?"
        alert.informativeText = "This reloads the current lesson bundle from disk. Unsaved areas: \(model.dirtySummary)."
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.discardUnsavedChanges()
    }

    @ViewBuilder var contentPane: some View {
        if model.projectURL != nil, let manifest = model.manifest, let summary = model.summary {
            if manifest.media.screen != nil {
                mediaEditorWorkspace(summary: summary, manifest: manifest)
                    .padding(.top, 20)
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

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LessonMeld")
                    .font(.title2.weight(.semibold))
                Text("Record, edit, export, and package your lessons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            sidebarSection("Workflow")

            ForEach(LessonWorkflowStage.allCases) { stage in
                workflowStageButton(stage)
            }

            Divider()

            sidebarSection("Project")

            Button {
                confirmProjectTransition("create a new project") {
                    model.newProject(preferences.snapshot)
                }
            } label: {
                LessonMeldSidebarItem(title: "New Project", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.plain)

            Button {
                confirmProjectTransition("open another project") {
                    model.openProject()
                }
            } label: {
                LessonMeldSidebarItem(title: "Open Project", systemImage: "folder")
            }
            .buttonStyle(.plain)

            Button {
                model.revealProject()
            } label: {
                LessonMeldSidebarItem(title: "Reveal Project", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)
            .disabled(model.projectURL == nil)

            Divider()

            sidebarSection("Tools")

            Button {
                if annotationOverlay.isPresented {
                    annotationOverlay.close()
                } else {
                    openAnnotationOverlayFromEditor()
                }
            } label: {
                LessonMeldSidebarItem(
                    title: annotationOverlay.isPresented ? "Close Annotation Tools" : "Annotate",
                    systemImage: "paintpalette",
                    isSelected: annotationOverlay.isPresented
                )
            }
            .buttonStyle(.plain)

            Divider()

            sidebarSection("App")

            Button {
                appRouter.openSettings()
            } label: {
                LessonMeldSidebarItem(title: "Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: "onboarding")
                NSApplication.shared.activate()
            } label: {
                LessonMeldSidebarItem(title: "Onboarding", systemImage: "checklist")
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: "command-palette")
                NSApplication.shared.activate()
            } label: {
                LessonMeldSidebarItem(title: "Command Palette", systemImage: "command")
            }
            .buttonStyle(.plain)

            Divider()

            if let projectURL = model.projectURL {
                Text(projectURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(8)
            } else {
                Text("Record a new lesson, import an existing video, or open a lesson bundle to edit video, export a final file, or package for LearnHouse.")
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

    func workflowStageButton(_ stage: LessonWorkflowStage) -> some View {
        Button {
            runWorkflowStage(stage)
        } label: {
            LessonMeldSidebarItem(
                title: sidebarTitle(for: stage),
                systemImage: stage.systemImage,
                isSelected: isWorkflowStageSelected(stage)
            )
        }
        .buttonStyle(.plain)
        .disabled(stage == .exportPackage && model.manifest?.media.screen == nil)
    }

    func sidebarTitle(for stage: LessonWorkflowStage) -> String {
        switch stage {
        case .record:
            quickRecorder.isRecording ? "Recording Controls" : stage.title
        default:
            stage.title
        }
    }

    func runWorkflowStage(_ stage: LessonWorkflowStage) {
        switch stage {
        case .record:
            quickRecorder.presentControlBar(preferences: preferences)
        case .editVideo:
            guard model.manifest?.media.screen == nil else {
                editorInspectorTab = .edits
                return
            }
            confirmProjectTransition("import a video") {
                model.importVideoForEditing(preferences.snapshot)
            }
        case .exportPackage:
            guard model.manifest?.media.screen != nil else { return }
            mediaEditorInspectorVisible = true
            editorInspectorTab = .export
        }
    }

    func isWorkflowStageSelected(_ stage: LessonWorkflowStage) -> Bool {
        switch stage {
        case .record:
            model.manifest?.media.screen == nil || quickRecorder.isRecording
        case .editVideo:
            model.manifest?.media.screen != nil && editorInspectorTab != .export
        case .exportPackage:
            model.manifest?.media.screen != nil && editorInspectorTab == .export
        }
    }

    func sidebarSection(_ title: String) -> some View {
        LessonMeldSectionTitle(title: title, topPadding: 6)
    }

}
