import DMLessonMeldSupport
import Testing

@Suite("Application termination policy")
struct ApplicationTerminationPolicyTests {
    @Test("Idle apps can terminate immediately")
    func idleAppTerminatesImmediately() {
        #expect(ApplicationTerminationPolicy.action(
            isRecording: false,
            isStopping: false
        ) == .terminateNow)
    }

    @Test("Active recordings require confirmation before stopping")
    func activeRecordingRequiresConfirmation() {
        #expect(ApplicationTerminationPolicy.action(
            isRecording: true,
            isStopping: false
        ) == .confirmStopAndQuit)
    }

    @Test("Recordings already stopping defer termination until cleanup")
    func stoppingRecordingWaitsForCleanup() {
        #expect(ApplicationTerminationPolicy.action(
            isRecording: true,
            isStopping: true
        ) == .waitForCleanup)
        #expect(ApplicationTerminationPolicy.action(
            isRecording: false,
            isStopping: true
        ) == .waitForCleanup)
    }

    @Test("Shutdown is clean only after all recording activity ends")
    func cleanShutdownRequiresIdleRecorder() {
        #expect(ApplicationTerminationPolicy.isCleanupComplete(
            isRecording: false,
            isStopping: false
        ))
        #expect(!ApplicationTerminationPolicy.isCleanupComplete(
            isRecording: true,
            isStopping: false
        ))
        #expect(!ApplicationTerminationPolicy.isCleanupComplete(
            isRecording: false,
            isStopping: true
        ))
    }
}
