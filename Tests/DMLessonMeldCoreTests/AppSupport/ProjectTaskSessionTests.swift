import DMLessonMeldSupport
import Testing

@Suite("Project task session")
struct ProjectTaskSessionTests {
    @Test("Current project generations accept their completions")
    @MainActor
    func currentGenerationAcceptsCompletion() {
        let session = ProjectTaskSession()
        let generation = session.capture()

        #expect(session.isCurrent(generation))
    }

    @Test("Delayed render completion cannot settle a new project's render")
    @MainActor
    func delayedRenderCompletionCannotSettleNewRender() async {
        let session = ProjectTaskSession()
        let gate = DelayedTaskGate()
        session.registerTask(id: "old-render")
        let oldCompletion = Task { @MainActor in
            await gate.wait()
            return session.isCurrentTask(id: "old-render")
        }

        session.invalidate()
        session.registerTask(id: "new-render")
        await gate.open()

        #expect(!(await oldCompletion.value))
        #expect(session.isCurrentTask(id: "new-render"))
    }

    @Test(
        "Delayed project work is stale after a project transition",
        arguments: ["render", "import", "preview-duration"]
    )
    @MainActor
    func delayedWorkIsStaleAfterTransition(_ operation: String) async {
        let session = ProjectTaskSession()
        let generation = session.capture()
        let gate = DelayedTaskGate()
        let completion = Task { @MainActor in
            await gate.wait()
            return (operation, session.isCurrent(generation))
        }

        let nextGeneration = session.invalidate()
        await gate.open()
        let result = await completion.value

        #expect(result.0 == operation)
        #expect(!result.1)
        #expect(session.isCurrent(nextGeneration))
        #expect(generation != nextGeneration)
    }
}

private actor DelayedTaskGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
