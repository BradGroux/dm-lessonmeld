import DMLessonMeldCore
import DMLessonMeldSupport
import Testing

@Suite("Quick recording duration policy")
struct QuickRecordingDurationPolicyTests {
    @Test("Manual-stop duration stays within the shared capture limit")
    func manualStopDurationIsValid() throws {
        let duration = QuickRecordingDurationPolicy.effectiveDurationSeconds(
            autoStopEnabled: false,
            configuredDurationSeconds: 300
        )

        #expect(duration == NumericInputValidation.maxRecordingDurationSeconds)
        #expect(try NumericInputValidation.recordingDuration(duration) == duration)
    }

    @Test("Auto-stop duration preserves the configured value")
    func autoStopDurationUsesConfiguration() {
        let duration = QuickRecordingDurationPolicy.effectiveDurationSeconds(
            autoStopEnabled: true,
            configuredDurationSeconds: 90
        )

        #expect(duration == 90)
    }
}
