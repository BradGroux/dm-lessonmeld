import DMLessonMeldSupport
import Testing

@Suite("Project editor dirty state")
struct ProjectEditorDirtyStateTests {
    @Test("Typed snapshots cannot collide through delimiter text")
    func typedSnapshotsDoNotCollide() {
        let baseline: [ProjectDirtyArea: TestSnapshot] = [
            .metadata: .metadata(title: "A||B", course: "C"),
            .markers: .rows([TestRow(id: "marker|1", text: "A~~B")]),
            .overlays: .rows([TestRow(id: "overlay||1", text: "A|B")]),
            .captions: .rows([TestRow(id: "caption~~1", text: "A||B")])
        ]
        let changed: [ProjectDirtyArea: TestSnapshot] = [
            .metadata: .metadata(title: "A", course: "B||C"),
            .markers: .rows([TestRow(id: "marker", text: "1|A~~B")]),
            .overlays: .rows([TestRow(id: "overlay", text: "|1|A|B")]),
            .captions: .rows([TestRow(id: "caption", text: "~~1~~A||B")])
        ]
        var state = ProjectEditorDirtyState<TestSnapshot>()
        state.replaceCurrent(with: baseline)
        state.markAllSaved()

        state.replaceCurrent(with: changed)

        #expect(state.dirtyAreas == [.metadata, .markers, .overlays, .captions])
    }

    @Test("Mutate revert mark saved and multi-area transitions are explicit")
    func stateTransitions() {
        let baseline: [ProjectDirtyArea: TestSnapshot] = [
            .metadata: .metadata(title: "Lesson", course: "Course"),
            .editorSettings: .setting(automaticZoomEnabled: true)
        ]
        var state = ProjectEditorDirtyState<TestSnapshot>()
        state.replaceCurrent(with: baseline)
        state.markAllSaved()
        #expect(state.dirtyAreas.isEmpty)

        state.updateCurrent(.metadata(title: "Changed", course: "Course"), for: .metadata)
        #expect(state.dirtyAreas == [.metadata])

        state.updateCurrent(.setting(automaticZoomEnabled: false), for: .editorSettings)
        #expect(state.dirtyAreas == [.metadata, .editorSettings])

        state.updateCurrent(baseline[.metadata]!, for: .metadata)
        #expect(state.dirtyAreas == [.editorSettings])

        state.markSaved(.editorSettings)
        #expect(state.dirtyAreas.isEmpty)

        state.updateCurrent(.setting(automaticZoomEnabled: true), for: .editorSettings)
        #expect(state.dirtyAreas == [.editorSettings])

        state.reset()
        #expect(state.dirtyAreas.isEmpty)
    }

    @Test("Editor settings snapshot tracks automatic zoom")
    func editorSettingsSnapshotTracksAutomaticZoom() {
        let enabled = ProjectEditorSettingsDirtySnapshot(
            canvas: "canvas",
            automaticZoomEnabled: true,
            cursor: "cursor",
            camera: "camera",
            audio: "audio",
            export: "export"
        )
        var disabled = enabled
        disabled.automaticZoomEnabled = false

        #expect(enabled != disabled)
    }
}

private enum TestSnapshot: Equatable {
    case metadata(title: String, course: String)
    case rows([TestRow])
    case setting(automaticZoomEnabled: Bool)
}

private struct TestRow: Equatable {
    var id: String
    var text: String
}
