import AppKit
import DMLessonMeldCore
import Foundation

@MainActor
final class ProjectOpenRouter {
    static let shared = ProjectOpenRouter()

    private var pendingProjectURL: URL?

    private init() {}

    func publish(_ projectURL: URL) {
        pendingProjectURL = projectURL
        NotificationCenter.default.post(name: .lessonMeldOpenProject, object: projectURL)
    }

    func consumePendingProjectURL() -> URL? {
        defer { pendingProjectURL = nil }
        return pendingProjectURL
    }
}

final class LessonMeldAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        publishRuntimeStatus(
            isAppRunning: true,
            message: "Digital Meld LessonMeld is running."
        )
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

            // Finder/open-url events can arrive before SwiftUI has attached the main view listener.
            try? await Task.sleep(nanoseconds: 300_000_000)
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
