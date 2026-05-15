import DMLessonMeldCore
import Foundation
import Testing

@Suite("Recording lifecycle")
struct RecordingLifecycleTests {
    @Test("Start pause resume and stop expose explicit states")
    func stateTransitions() {
        let start = Date(timeIntervalSince1970: 1_000)
        var lifecycle = RecordingLifecycleStateMachine()

        var snapshot = lifecycle.start(at: start)
        #expect(snapshot.phase == .recording)
        #expect(snapshot.isRecording)
        #expect(!snapshot.isPaused)
        #expect(!snapshot.isStopping)

        snapshot = lifecycle.pause(at: start.addingTimeInterval(10))
        #expect(snapshot.phase == .paused)
        #expect(snapshot.isRecording)
        #expect(snapshot.isPaused)
        #expect(snapshot.elapsedSeconds == 10)

        snapshot = lifecycle.resume(at: start.addingTimeInterval(15))
        #expect(snapshot.phase == .recording)
        #expect(snapshot.elapsedSeconds == 10)
        #expect(lifecycle.elapsed(at: start.addingTimeInterval(25)) == 20)

        snapshot = lifecycle.requestStop(at: start.addingTimeInterval(30))
        #expect(snapshot.phase == .stopping)
        #expect(snapshot.isRecording)
        #expect(snapshot.isStopping)
        #expect(snapshot.elapsedSeconds == 25)
    }

    @Test("Stop from pause keeps paused time out of elapsed duration")
    func stopFromPause() {
        let start = Date(timeIntervalSince1970: 2_000)
        var lifecycle = RecordingLifecycleStateMachine()

        _ = lifecycle.start(at: start)
        _ = lifecycle.pause(at: start.addingTimeInterval(10))
        let snapshot = lifecycle.requestStop(at: start.addingTimeInterval(40))

        #expect(snapshot.phase == .stopping)
        #expect(snapshot.elapsedSeconds == 10)
        #expect(lifecycle.elapsed(at: start.addingTimeInterval(90)) == 10)
    }

    @Test("Stopping elapsed time and timeout are explicit")
    func stopTimeoutState() {
        let start = Date(timeIntervalSince1970: 2_500)
        var lifecycle = RecordingLifecycleStateMachine()

        _ = lifecycle.start(at: start)
        _ = lifecycle.requestStop(at: start.addingTimeInterval(12))

        #expect(lifecycle.stoppingElapsed(at: start.addingTimeInterval(16)) == 4)
        #expect(!lifecycle.hasStopTimedOut(after: 10, at: start.addingTimeInterval(21)))
        #expect(lifecycle.hasStopTimedOut(after: 10, at: start.addingTimeInterval(22)))
    }

    @Test("Finish fail and reset leave inactive snapshots")
    func completionSnapshots() {
        let start = Date(timeIntervalSince1970: 3_000)
        var lifecycle = RecordingLifecycleStateMachine()

        _ = lifecycle.start(at: start)
        var snapshot = lifecycle.finish(at: start.addingTimeInterval(45))
        #expect(snapshot.phase == .finished)
        #expect(!snapshot.isRecording)
        #expect(snapshot.elapsedSeconds == 45)

        _ = lifecycle.start(at: start)
        snapshot = lifecycle.fail(at: start.addingTimeInterval(5))
        #expect(snapshot.phase == .failed)
        #expect(!snapshot.isRecording)
        #expect(snapshot.elapsedSeconds == 5)

        snapshot = lifecycle.reset(at: start.addingTimeInterval(90))
        #expect(snapshot.phase == .idle)
        #expect(!snapshot.isRecording)
        #expect(snapshot.elapsedSeconds == 0)
    }
}
