import DMLessonMeldCore
import Foundation

@MainActor
final class LocalAppControlBridge {
    static let shared = LocalAppControlBridge()

    private var observer: NSObjectProtocol?
    private weak var quickRecorder: QuickRecorderModel?
    private weak var preferences: AppPreferencesController?

    private init() {}

    func configure(quickRecorder: QuickRecorderModel, preferences: AppPreferencesController) {
        self.quickRecorder = quickRecorder
        self.preferences = preferences
        _ = try? LocalAppControl.ensureControlToken()
        quickRecorder.publishStatus()

        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: LocalAppControl.notificationName,
            object: LocalAppControl.notificationObject,
            queue: .main
        ) { [weak self] notification in
            let command = LocalAppControl.authenticatedCommand(from: notification.userInfo)
            Task { @MainActor in
                self?.handle(command: command)
            }
        }
    }

    private func handle(command: LocalAppControlCommand?) {
        guard let command, let quickRecorder else {
            return
        }

        switch command.action {
        case .showControls:
            guard let preferences else { return }
            quickRecorder.presentControlBar(preferences: preferences)
        case .start:
            guard let preferences else { return }
            quickRecorder.presentControlBar(preferences: preferences)
            quickRecorder.startRecording(preferences.snapshot)
        case .pause:
            quickRecorder.pauseRecording()
        case .resume:
            quickRecorder.resumeRecording()
        case .togglePause:
            quickRecorder.togglePause()
        case .stop:
            quickRecorder.stopRecording()
        case .status:
            break
        }

        quickRecorder.publishStatus()
    }
}
