public enum ApplicationTerminationAction: Equatable, Sendable {
    case terminateNow
    case confirmStopAndQuit
    case waitForCleanup
}

public enum ApplicationTerminationPolicy {
    public static func action(
        isRecording: Bool,
        isStopping: Bool
    ) -> ApplicationTerminationAction {
        if isStopping {
            return .waitForCleanup
        }
        if isRecording {
            return .confirmStopAndQuit
        }
        return .terminateNow
    }

    public static func isCleanupComplete(
        isRecording: Bool,
        isStopping: Bool
    ) -> Bool {
        !isRecording && !isStopping
    }
}
