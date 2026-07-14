import DMLessonMeldCore
import Foundation

public enum QuickRecordingDurationPolicy {
    public static func effectiveDurationSeconds(
        autoStopEnabled: Bool,
        configuredDurationSeconds: Int
    ) -> TimeInterval {
        if autoStopEnabled {
            return TimeInterval(configuredDurationSeconds)
        }
        return NumericInputValidation.maxRecordingDurationSeconds
    }
}
