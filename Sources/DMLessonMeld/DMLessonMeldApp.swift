import AppKit
import DMLessonMeldCore
import DMLessonMeldSupport
import SwiftUI

@main
struct DMLessonMeldApp: App {
    @NSApplicationDelegateAdaptor(LessonMeldAppDelegate.self) private var appDelegate
    @StateObject private var appRouter = LessonMeldAppRouter()
    @StateObject private var annotationOverlay = AnnotationOverlayCoordinator()
    @StateObject private var preferences: AppPreferencesController
    @StateObject private var quickRecorder: QuickRecorderModel
    private let renderedUIRegression: RenderedUIRegressionLaunchConfiguration?
    private let appDefaults: UserDefaults

    init() {
        #if DEBUG
        let renderedUIRegression = ProcessInfo.processInfo.environment["DM_LESSONMELD_ENABLE_UI_REGRESSION"] == "1"
            ? RenderedUIRegressionLaunchConfiguration.parse(arguments: ProcessInfo.processInfo.arguments)
            : nil
        #else
        let renderedUIRegression: RenderedUIRegressionLaunchConfiguration? = nil
        #endif
        self.renderedUIRegression = renderedUIRegression
        let defaults: UserDefaults
        if let renderedUIRegression {
            let suiteName = "io.digitalmeld.dm-lessonmeld.ui-regression.\(renderedUIRegression.fixtureID).\(renderedUIRegression.appearance.rawValue)"
            defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
        } else {
            defaults = .standard
        }
        self.appDefaults = defaults
        let preferences = AppPreferencesController(defaults: defaults)
        if renderedUIRegression != nil {
            preferences.update { snapshot in
                snapshot.firstRunCompletedAt = Date(timeIntervalSince1970: 1_700_000_000)
                snapshot.general.showMainWindowAtLaunch = true
                snapshot.general.showAnnotationOverlayAtLaunch = false
            }
        }
        let quickRecorder = QuickRecorderModel()
        _preferences = StateObject(wrappedValue: preferences)
        _quickRecorder = StateObject(wrappedValue: quickRecorder)

        NSApplication.shared.setActivationPolicy(.regular)
        appDelegate.configure(
            quickRecorder: quickRecorder,
            preferences: preferences
        )
        LocalAppControlBridge.shared.configure(
            quickRecorder: quickRecorder,
            preferences: preferences
        )
    }

    var body: some Scene {
        Window(AppBrand.shortName, id: "main") {
            ProjectEditorView(
                appRouter: appRouter,
                preferences: preferences,
                annotationOverlay: annotationOverlay,
                quickRecorder: quickRecorder,
                fallbackAnnotationOverlayHandler: { preferences in
                    annotationOverlay.toggle(preferences: preferences, forceToolbarVisible: true)
                },
                renderedUIRegression: renderedUIRegression
            )
                .frame(
                    minWidth: AppUILayoutSurface.mainEditor.minimumSize.width,
                    idealWidth: UIRegressionFixtures.laptop.width,
                    minHeight: AppUILayoutSurface.mainEditor.minimumSize.height,
                    idealHeight: UIRegressionFixtures.laptop.height
                )
                .disablesWindowRestoration()
                .hidesWindowTitle()
                .handlesLessonMeldAppEvents(appRouter: appRouter)
                .defaultAppStorage(appDefaults)
                .preferredColorScheme(renderedUIRegressionColorScheme)
                .tint(renderedUIRegression == nil ? nil : Color(red: 0.68, green: 0.28, blue: 0.72))
                .onAppear {
                    annotationOverlay.openSettingsHandler = { section in
                        appRouter.openSettings(section)
                    }
                    quickRecorder.annotationOverlayToggleHandler = { preferences in
                        annotationOverlay.toggle(preferences: preferences, forceToolbarVisible: true)
                    }
                }
        }
        .defaultLaunchBehavior(mainWindowLaunchBehavior)
        .windowResizability(.contentMinSize)
        .commands {
            LessonMeldAppCommands(
                appRouter: appRouter,
                annotationOverlay: annotationOverlay,
                quickRecorder: quickRecorder,
                preferences: preferences
            )
        }

        MenuBarExtra {
            MenuBarStatusView(
                appRouter: appRouter,
                annotationOverlay: annotationOverlay,
                preferences: preferences,
                quickRecorder: quickRecorder
            )
        } label: {
            Label(AppBrand.displayName, systemImage: "record.circle")
        }
        .menuBarExtraStyle(.menu)

        Window(AppBrand.settingsTitle, id: "settings") {
            LessonMeldSettingsView(appRouter: appRouter, preferences: preferences)
                .disablesWindowRestoration()
                .handlesLessonMeldAppEvents(appRouter: appRouter)
        }
        .windowResizability(.contentMinSize)

        Window(AppBrand.aboutTitle, id: "about") {
            AboutLessonMeldView()
                .disablesWindowRestoration()
        }
        .windowResizability(.contentSize)

        Window(AppBrand.commandPaletteTitle, id: "command-palette") {
            CommandPaletteWindowContent(
                appRouter: appRouter,
                annotationOverlay: annotationOverlay,
                preferences: preferences,
                quickRecorder: quickRecorder
            )
                .disablesWindowRestoration()
                .handlesLessonMeldAppEvents(appRouter: appRouter)
        }
        .windowResizability(.contentMinSize)

        Window(AppBrand.onboardingTitle, id: "onboarding") {
            OnboardingWindowContent(appRouter: appRouter, preferences: preferences)
                .disablesWindowRestoration()
                .handlesLessonMeldAppEvents(appRouter: appRouter)
        }
        .windowResizability(.contentMinSize)
    }

    private var mainWindowLaunchBehavior: SceneLaunchBehavior {
        switch MainWindowLaunchPolicy.action(
            showMainWindowAtLaunch: preferences.snapshot.general.showMainWindowAtLaunch
        ) {
        case .present:
            .presented
        case .suppress:
            .suppressed
        }
    }

    private var renderedUIRegressionColorScheme: ColorScheme? {
        switch renderedUIRegression?.appearance {
        case .light: .light
        case .dark: .dark
        case nil: nil
        }
    }
}

private struct LessonMeldAppEventBridge: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appRouter: LessonMeldAppRouter

    func body(content: Content) -> some View {
        content.onReceive(appRouter.$settingsRequest.compactMap(\.self)) { _ in
            openWindow(id: "settings")
            NSApplication.shared.activate()
        }
    }
}

private extension View {
    func handlesLessonMeldAppEvents(appRouter: LessonMeldAppRouter) -> some View {
        modifier(LessonMeldAppEventBridge(appRouter: appRouter))
    }
}

private struct LessonMeldAppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appRouter: LessonMeldAppRouter
    @ObservedObject var annotationOverlay: AnnotationOverlayCoordinator
    @ObservedObject var quickRecorder: QuickRecorderModel
    @ObservedObject var preferences: AppPreferencesController

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(AppBrand.aboutTitle) {
                openWindow(id: "about")
                NSApplication.shared.activate()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button(commandTitle(.settings)) {
                runCommand(.settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button(commandTitle(.newProject)) {
                runCommand(.newProject)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(commandTitle(.openProject)) {
                runCommand(.openProject)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(commandTitle(.importVideo)) {
                runCommand(.importVideo)
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button(commandTitle(.saveEdits)) {
                runCommand(.saveEdits)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!command(.saveEdits).isEnabled)
        }

        CommandGroup(after: .saveItem) {
            Button(commandTitle(.revealProject)) {
                runCommand(.revealProject)
            }
            .keyboardShortcut("r", modifiers: [.shift, .command])
            .disabled(!command(.revealProject).isEnabled)

            Button(commandTitle(.exportVideo)) {
                runCommand(.exportVideo)
            }
            .keyboardShortcut("e", modifiers: [.shift, .command])
            .disabled(!command(.exportVideo).isEnabled)
        }

        CommandMenu("Tools") {
            Button(commandTitle(.newRecording)) {
                runCommand(.newRecording)
            }
            .keyboardShortcut(.return, modifiers: [.option, .command])
            .disabled(!command(.newRecording).isEnabled)

            Button(commandTitle(.recordingControls)) {
                runCommand(.recordingControls)
            }
            .keyboardShortcut("r", modifiers: [.option, .command])

            Button(commandTitle(.pauseRecording)) {
                runCommand(.pauseRecording)
            }
            .disabled(!command(.pauseRecording).isEnabled)

            Button(commandTitle(.stopRecording)) {
                runCommand(.stopRecording)
            }
            .keyboardShortcut(.escape)
            .disabled(!command(.stopRecording).isEnabled)

            Button(commandTitle(.toggleAnnotationOverlay)) {
                runCommand(.toggleAnnotationOverlay)
            }
            .keyboardShortcut("a", modifiers: [.option, .command])

            Divider()

            Button(commandTitle(.showMainWindow)) {
                runCommand(.showMainWindow)
            }
            .keyboardShortcut("0", modifiers: .command)

            Button(commandTitle(.onboarding)) {
                runCommand(.onboarding)
            }
            .keyboardShortcut("p", modifiers: [.option, .command])

            Button(commandTitle(.commandPalette)) {
                runCommand(.commandPalette)
            }
            .keyboardShortcut("k", modifiers: .command)
        }
    }

    private var commandContext: LessonMeldCommandContext {
        LessonMeldCommandContext(
            preferences: preferences.snapshot,
            project: appRouter.projectCommandState,
            recorder: LessonMeldRecorderCommandState(
                isRecording: quickRecorder.isRecording,
                isPaused: quickRecorder.isPaused,
                isStopping: quickRecorder.isStopping
            ),
            isAnnotationPresented: annotationOverlay.isPresented
        )
    }

    private func command(_ id: LessonMeldAppCommandID) -> LessonMeldAppCommand {
        LessonMeldCommandRegistry.command(id, context: commandContext) { commandID in
            perform(commandID)
        }
    }

    private func commandTitle(_ id: LessonMeldAppCommandID) -> String {
        command(id).title
    }

    private func runCommand(_ id: LessonMeldAppCommandID) {
        command(id).action()
    }

    private func perform(_ id: LessonMeldAppCommandID) {
        switch id {
        case .showMainWindow:
            openWindow(id: "main")
            NSApplication.shared.activate()
        case .newProject:
            openWindow(id: "main")
            appRouter.runProjectCommand(.newProject)
            NSApplication.shared.activate()
        case .openProject:
            openWindow(id: "main")
            appRouter.runProjectCommand(.openProject)
            NSApplication.shared.activate()
        case .importVideo:
            openWindow(id: "main")
            appRouter.runProjectCommand(.importVideo)
            NSApplication.shared.activate()
        case .revealProject:
            appRouter.runProjectCommand(.revealProject)
        case .saveEdits:
            appRouter.runProjectCommand(.saveEdits)
        case .exportVideo:
            appRouter.runProjectCommand(.exportVideo)
        case .newRecording, .recordingControls:
            quickRecorder.presentControlBar(preferences: preferences)
            NSApplication.shared.activate()
        case .pauseRecording:
            quickRecorder.togglePause()
        case .stopRecording:
            quickRecorder.stopRecording()
        case .toggleAnnotationOverlay:
            annotationOverlay.toggle(preferences: preferences.snapshot, forceToolbarVisible: true)
            NSApplication.shared.activate()
        case .settings:
            appRouter.openSettings()
        case .onboarding:
            openWindow(id: "onboarding")
            NSApplication.shared.activate()
        case .commandPalette:
            openWindow(id: "command-palette")
            NSApplication.shared.activate()
        }
    }
}

private struct CommandPaletteWindowContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appRouter: LessonMeldAppRouter
    @ObservedObject var annotationOverlay: AnnotationOverlayCoordinator
    @ObservedObject var preferences: AppPreferencesController
    @ObservedObject var quickRecorder: QuickRecorderModel

    var body: some View {
        CommandPaletteView(commands: commands.map(CommandPaletteCommand.init(command:)))
    }

    private var commands: [LessonMeldAppCommand] {
        LessonMeldCommandRegistry.commands(context: commandContext) { commandID in
            perform(commandID)
        }
    }

    private var commandContext: LessonMeldCommandContext {
        LessonMeldCommandContext(
            preferences: preferences.snapshot,
            project: appRouter.projectCommandState,
            recorder: LessonMeldRecorderCommandState(
                isRecording: quickRecorder.isRecording,
                isPaused: quickRecorder.isPaused,
                isStopping: quickRecorder.isStopping
            ),
            isAnnotationPresented: annotationOverlay.isPresented
        )
    }

    private func perform(_ id: LessonMeldAppCommandID) {
        switch id {
        case .showMainWindow:
            openWindow(id: "main")
            NSApplication.shared.activate()
        case .newProject:
            openWindow(id: "main")
            appRouter.runProjectCommand(.newProject)
            NSApplication.shared.activate()
        case .openProject:
            openWindow(id: "main")
            appRouter.runProjectCommand(.openProject)
            NSApplication.shared.activate()
        case .importVideo:
            openWindow(id: "main")
            appRouter.runProjectCommand(.importVideo)
            NSApplication.shared.activate()
        case .revealProject:
            appRouter.runProjectCommand(.revealProject)
        case .saveEdits:
            appRouter.runProjectCommand(.saveEdits)
        case .exportVideo:
            appRouter.runProjectCommand(.exportVideo)
        case .newRecording, .recordingControls:
            quickRecorder.presentControlBar(preferences: preferences)
            NSApplication.shared.activate()
        case .pauseRecording:
            quickRecorder.togglePause()
        case .stopRecording:
            quickRecorder.stopRecording()
        case .toggleAnnotationOverlay:
            annotationOverlay.toggle(preferences: preferences.snapshot, forceToolbarVisible: true)
            NSApplication.shared.activate()
        case .settings:
            appRouter.openSettings()
        case .onboarding:
            openWindow(id: "onboarding")
            NSApplication.shared.activate()
        case .commandPalette:
            openWindow(id: "command-palette")
            NSApplication.shared.activate()
        }
    }
}

private struct OnboardingWindowContent: View {
    @ObservedObject var appRouter: LessonMeldAppRouter
    @ObservedObject var preferences: AppPreferencesController

    var body: some View {
        OnboardingView(preferences: preferences) {
            appRouter.openSettings(.capture)
        }
    }
}

private struct MenuBarStatusView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appRouter: LessonMeldAppRouter
    @ObservedObject var annotationOverlay: AnnotationOverlayCoordinator
    @ObservedObject var preferences: AppPreferencesController
    @ObservedObject var quickRecorder: QuickRecorderModel

    private let diagnostics = AppDiagnostics.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppBrand.displayName)
                .font(.headline)
            Text(diagnostics.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button(commandTitle(primaryRecordingCommandID)) {
                runCommand(primaryRecordingCommandID)
            }
            .keyboardShortcut("r", modifiers: [.option, .command])

            if quickRecorder.isRecording {
                Button(commandTitle(.pauseRecording)) {
                    runCommand(.pauseRecording)
                }

                Button(commandTitle(.stopRecording)) {
                    runCommand(.stopRecording)
                }
                .keyboardShortcut(.escape)

                Divider()
            }

            Button(commandTitle(.showMainWindow)) {
                runCommand(.showMainWindow)
            }

            Button(commandTitle(.importVideo)) {
                runCommand(.importVideo)
            }

            Button(commandTitle(.onboarding)) {
                runCommand(.onboarding)
            }
            .keyboardShortcut("p", modifiers: [.option, .command])

            Button(commandTitle(.settings)) {
                runCommand(.settings)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button(commandTitle(.commandPalette)) {
                runCommand(.commandPalette)
            }
            .keyboardShortcut("k", modifiers: .command)

            Button(commandTitle(.toggleAnnotationOverlay)) {
                runCommand(.toggleAnnotationOverlay)
            }
            .keyboardShortcut("a", modifiers: [.option, .command])

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
    }

    private var primaryRecordingCommandID: LessonMeldAppCommandID {
        quickRecorder.isRecording ? .recordingControls : .newRecording
    }

    private var commandContext: LessonMeldCommandContext {
        LessonMeldCommandContext(
            preferences: preferences.snapshot,
            project: appRouter.projectCommandState,
            recorder: LessonMeldRecorderCommandState(
                isRecording: quickRecorder.isRecording,
                isPaused: quickRecorder.isPaused,
                isStopping: quickRecorder.isStopping
            ),
            isAnnotationPresented: annotationOverlay.isPresented
        )
    }

    private func command(_ id: LessonMeldAppCommandID) -> LessonMeldAppCommand {
        LessonMeldCommandRegistry.command(id, context: commandContext) { commandID in
            perform(commandID)
        }
    }

    private func commandTitle(_ id: LessonMeldAppCommandID) -> String {
        command(id).title
    }

    private func runCommand(_ id: LessonMeldAppCommandID) {
        command(id).action()
    }

    private func perform(_ id: LessonMeldAppCommandID) {
        switch id {
        case .showMainWindow:
            openWindow(id: "main")
            NSApplication.shared.activate()
        case .newProject:
            openWindow(id: "main")
            appRouter.runProjectCommand(.newProject)
            NSApplication.shared.activate()
        case .openProject:
            openWindow(id: "main")
            appRouter.runProjectCommand(.openProject)
            NSApplication.shared.activate()
        case .importVideo:
            openWindow(id: "main")
            appRouter.runProjectCommand(.importVideo)
            NSApplication.shared.activate()
        case .revealProject:
            appRouter.runProjectCommand(.revealProject)
        case .saveEdits:
            appRouter.runProjectCommand(.saveEdits)
        case .exportVideo:
            appRouter.runProjectCommand(.exportVideo)
        case .newRecording, .recordingControls:
            quickRecorder.presentControlBar(preferences: preferences)
            NSApplication.shared.activate()
        case .pauseRecording:
            quickRecorder.togglePause()
        case .stopRecording:
            quickRecorder.stopRecording()
        case .toggleAnnotationOverlay:
            annotationOverlay.toggle(preferences: preferences.snapshot, forceToolbarVisible: true)
            NSApplication.shared.activate()
        case .settings:
            appRouter.openSettings()
        case .onboarding:
            openWindow(id: "onboarding")
            NSApplication.shared.activate()
        case .commandPalette:
            openWindow(id: "command-palette")
            NSApplication.shared.activate()
        }
    }
}
