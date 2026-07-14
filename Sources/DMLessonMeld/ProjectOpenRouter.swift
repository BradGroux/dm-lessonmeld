import AppKit
import DMLessonMeldCore
import Foundation

@MainActor
final class ProjectOpenRouter {
    static let shared = ProjectOpenRouter()

    private var pendingProjectURLs: [URL] = []
    private var consumer: ((URL) -> Void)?

    private init() {}

    func registerConsumer(_ consumer: @escaping (URL) -> Void) {
        self.consumer = consumer
        drainPendingProjectURLs()
    }

    func unregisterConsumer() {
        consumer = nil
    }

    func publish(_ projectURL: URL) {
        guard let consumer else {
            pendingProjectURLs.append(projectURL)
            return
        }
        consumer(projectURL)
    }

    private func drainPendingProjectURLs() {
        guard let consumer else { return }
        let urls = pendingProjectURLs
        pendingProjectURLs.removeAll()
        for url in urls {
            consumer(url)
        }
    }
}

@MainActor
final class LessonMeldAppDelegate: NSObject, NSApplicationDelegate {
    private let terminationCoordinator = ApplicationTerminationCoordinator()

    func configure(
        quickRecorder: QuickRecorderModel,
        preferences: AppPreferencesController
    ) {
        terminationCoordinator.configure(
            quickRecorder: quickRecorder,
            preferences: preferences
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        publishRuntimeStatus(
            isAppRunning: true,
            message: "Digital Meld LessonMeld is running."
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationCoordinator.applicationShouldTerminate(sender)
    }

    func applicationWillTerminate(_ notification: Notification) {
        publishRuntimeStatus(
            isAppRunning: false,
            message: "Digital Meld LessonMeld has quit."
        )
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openProject(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(openProject)
    }

    private func openProject(_ url: URL) {
        Task { @MainActor in
            NSApplication.shared.activate(ignoringOtherApps: true)
            ProjectOpenRouter.shared.publish(url)
        }
    }

    private func publishRuntimeStatus(isAppRunning: Bool, message: String) {
        try? LocalAppControl.writeStatus(LocalAppControlStatus(
            isAppRunning: isAppRunning,
            isRecording: false,
            isPaused: false,
            isStopping: false,
            elapsedSeconds: 0,
            lastProjectPath: nil,
            message: message
        ))
    }
}
