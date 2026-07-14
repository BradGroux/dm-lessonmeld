import AppKit
import Combine
import DMLessonMeldSupport

@MainActor
final class ApplicationTerminationCoordinator {
    private weak var quickRecorder: QuickRecorderModel?
    private weak var preferences: AppPreferencesController?
    private weak var pendingApplication: NSApplication?
    private var cleanupObserver: AnyCancellable?
    private var isAwaitingCleanup = false

    func configure(
        quickRecorder: QuickRecorderModel,
        preferences: AppPreferencesController
    ) {
        self.quickRecorder = quickRecorder
        self.preferences = preferences
    }

    func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        guard let quickRecorder else {
            return .terminateNow
        }
        if isAwaitingCleanup {
            return .terminateLater
        }

        switch ApplicationTerminationPolicy.action(
            isRecording: quickRecorder.isRecording,
            isStopping: quickRecorder.isStopping
        ) {
        case .terminateNow:
            preferences?.markCleanTermination()
            return .terminateNow
        case .confirmStopAndQuit:
            guard confirmStopAndQuit() else {
                return .terminateCancel
            }
            quickRecorder.stopRecording()
            waitForRecordingCleanup(quickRecorder, application: application)
            return .terminateLater
        case .waitForCleanup:
            waitForRecordingCleanup(quickRecorder, application: application)
            return .terminateLater
        }
    }

    private func confirmStopAndQuit() -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Stop Recording and Quit?"
        alert.informativeText = "LessonMeld needs to stop the active recording and finish writing its project before quitting. This can take a few seconds."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop Recording and Quit")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func waitForRecordingCleanup(
        _ quickRecorder: QuickRecorderModel,
        application: NSApplication
    ) {
        isAwaitingCleanup = true
        pendingApplication = application
        cleanupObserver = Publishers.CombineLatest(
            quickRecorder.$isRecording,
            quickRecorder.$isStopping
        )
        .filter { isRecording, isStopping in
            ApplicationTerminationPolicy.isCleanupComplete(
                isRecording: isRecording,
                isStopping: isStopping
            )
        }
        .prefix(1)
        .sink { [weak self] _ in
            self?.finishDeferredTermination()
        }
    }

    private func finishDeferredTermination() {
        guard isAwaitingCleanup else { return }
        preferences?.markCleanTermination()
        isAwaitingCleanup = false
        cleanupObserver = nil
        let application = pendingApplication
        pendingApplication = nil
        application?.reply(toApplicationShouldTerminate: true)
    }
}
