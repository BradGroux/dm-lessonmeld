import AppKit
import SwiftUI

@main
struct DMLessonMeldApp: App {
    @NSApplicationDelegateAdaptor(LessonMeldAppDelegate.self) private var appDelegate
    @StateObject private var appRouter = LessonMeldAppRouter()
    @StateObject private var annotationOverlay = AnnotationOverlayCoordinator()
    @StateObject private var preferences = AppPreferencesController()
    @StateObject private var quickRecorder = QuickRecorderModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window(AppBrand.shortName, id: "main") {
            ProjectEditorView(
                appRouter: appRouter,
                preferences: preferences,
                annotationOverlay: annotationOverlay,
                quickRecorder: quickRecorder,
                fallbackAnnotationOverlayHandler: { preferences in
                    annotationOverlay.open(preferences: preferences, forceToolbarVisible: true)
                }
            )
                .frame(minWidth: 960, idealWidth: 1180, minHeight: 680, idealHeight: 780)
                .disablesWindowRestoration()
                .hidesWindowTitle()
                .handlesLessonMeldAppEvents(appRouter: appRouter)
                .onAppear {
                    annotationOverlay.openSettingsHandler = { section in
                        appRouter.openSettings(section)
                    }
                    quickRecorder.annotationOverlayHandler = { preferences in
                        annotationOverlay.open(preferences: preferences, forceToolbarVisible: true)
                    }
                }
        }
        .defaultLaunchBehavior(.presented)
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

        Window(AppBrand.commandPaletteTitle, id: "command-palette") {
            CommandPaletteWindowContent(appRouter: appRouter, annotationOverlay: annotationOverlay, preferences: preferences)
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
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                appRouter.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Create Project from Video...") {
                openWindow(id: "main")
                appRouter.importVideoForEditing()
                NSApplication.shared.activate()
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        CommandMenu("Tools") {
            Button("New Recording...") {
                quickRecorder.presentControlBar(preferences: preferences)
                NSApplication.shared.activate()
            }
            .keyboardShortcut(.return, modifiers: [.option, .command])

            Button(quickRecorder.isRecording ? "Show Recording Controls" : "Open Recording Controls") {
                quickRecorder.presentControlBar(preferences: preferences)
                NSApplication.shared.activate()
            }
            .keyboardShortcut("r", modifiers: [.option, .command])

            Button(annotationOverlay.isPresented ? "Close Annotation Overlay" : "Open Annotation Overlay") {
                annotationOverlay.toggle(preferences: preferences.snapshot, forceToolbarVisible: true)
                NSApplication.shared.activate()
            }
            .keyboardShortcut("a", modifiers: [.option, .command])

            Divider()

            Button("Show Main Window") {
                openWindow(id: "main")
                NSApplication.shared.activate()
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("Open Editor...") {
                openWindow(id: "main")
                NSApplication.shared.activate()
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("Import Video for Editing...") {
                openWindow(id: "main")
                appRouter.importVideoForEditing()
                NSApplication.shared.activate()
            }

            Button("Onboarding...") {
                openWindow(id: "onboarding")
                NSApplication.shared.activate()
            }
            .keyboardShortcut("p", modifiers: [.option, .command])

            Button("Command Palette...") {
                openWindow(id: "command-palette")
                NSApplication.shared.activate()
            }
            .keyboardShortcut("k", modifiers: .command)
        }
    }
}

private struct CommandPaletteWindowContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appRouter: LessonMeldAppRouter
    @ObservedObject var annotationOverlay: AnnotationOverlayCoordinator
    @ObservedObject var preferences: AppPreferencesController

    var body: some View {
        CommandPaletteView(commands: [
            CommandPaletteCommand(
                id: "main",
                title: "Show Main Window",
                subtitle: "Open the recorder and project editor workspace.",
                systemImage: "rectangle.stack.badge.play",
                shortcut: nil,
                keywords: ["home", "record", "editor", "project"]
            ) {
                openWindow(id: "main")
                NSApplication.shared.activate()
            },
            CommandPaletteCommand(
                id: "settings",
                title: "Settings",
                subtitle: "Capture, annotation, export, privacy, diagnostics, and shortcuts.",
                systemImage: "gearshape",
                shortcut: preferences.snapshot.shortcuts[.showSettings],
                keywords: ["preferences", "config"]
            ) {
                appRouter.openSettings()
            },
            CommandPaletteCommand(
                id: "onboarding",
                title: "Onboarding",
                subtitle: "Review permissions and first-run teaching defaults.",
                systemImage: "checklist",
                shortcut: preferences.snapshot.shortcuts[.showOnboarding],
                keywords: ["permissions", "setup"]
            ) {
                openWindow(id: "onboarding")
                NSApplication.shared.activate()
            },
            CommandPaletteCommand(
                id: "annotations",
                title: annotationOverlay.isPresented ? "Close Annotation Overlay" : "Open Annotation Overlay",
                subtitle: "Toggle the live local drawing overlay.",
                systemImage: "pencil.tip",
                shortcut: preferences.snapshot.shortcuts[.openAnnotationOverlay],
                keywords: ["draw", "overlay", "annotate"]
            ) {
                annotationOverlay.toggle(preferences: preferences.snapshot, forceToolbarVisible: true)
            },
            CommandPaletteCommand(
                id: "import-video",
                title: "Create Project from Video",
                subtitle: "Import an existing MP4 or MOV and open it in the editor.",
                systemImage: "film",
                shortcut: nil,
                keywords: ["import", "video", "edit", "project", "mp4", "mov"]
            ) {
                openWindow(id: "main")
                appRouter.importVideoForEditing()
                NSApplication.shared.activate()
            },
            CommandPaletteCommand(
                id: "permissions",
                title: "Open Capture Permissions",
                subtitle: "Open onboarding for Screen Recording, Microphone, and Camera.",
                systemImage: "lock.shield",
                shortcut: nil,
                keywords: ["privacy", "camera", "microphone", "screen"]
            ) {
                openWindow(id: "onboarding")
                NSApplication.shared.activate()
            }
        ])
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

            Button(quickRecorder.isRecording ? "Show Recording Controls" : "New Recording...") {
                quickRecorder.presentControlBar(preferences: preferences)
                NSApplication.shared.activate()
            }
            .keyboardShortcut("r", modifiers: [.option, .command])

            if quickRecorder.isRecording {
                Button(quickRecorder.isPaused ? "Resume Recording" : "Pause Recording") {
                    quickRecorder.togglePause()
                }

                Button("Stop Recording") {
                    quickRecorder.stopRecording()
                }
                .keyboardShortcut(.escape)

                Divider()
            }

            Button("Show Main Window") {
                openWindow(id: "main")
                NSApplication.shared.activate()
            }

            Button("Import Video for Editing...") {
                openWindow(id: "main")
                appRouter.importVideoForEditing()
                NSApplication.shared.activate()
            }

            Button("Onboarding...") {
                openWindow(id: "onboarding")
                NSApplication.shared.activate()
            }
            .keyboardShortcut("p", modifiers: [.option, .command])

            Button("Settings...") {
                appRouter.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Editor...") {
                openWindow(id: "main")
                NSApplication.shared.activate()
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("Command Palette...") {
                openWindow(id: "command-palette")
                NSApplication.shared.activate()
            }
            .keyboardShortcut("k", modifiers: .command)

            Button(annotationOverlay.isPresented ? "Close Annotation Overlay" : "Open Annotation Overlay") {
                annotationOverlay.toggle(preferences: preferences.snapshot, forceToolbarVisible: true)
            }
            .keyboardShortcut("a", modifiers: [.option, .command])

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
    }
}
