import DMLessonMeldCore
import Testing

@Suite("Editor workspace layout")
struct EditorWorkspaceLayoutTests {
    @Test("Keeps inspector visible when there is room")
    func keepsInspectorVisible() {
        let layout = EditorWorkspaceLayout.resolve(
            containerWidth: 1400,
            containerHeight: 900,
            preferredInspectorWidth: 420,
            inspectorVisible: true,
            timelineVisible: true
        )

        #expect(layout.showsInspector)
        #expect(layout.inspectorWidth == 420)
        #expect(layout.stageWidth == 979)
        #expect(layout.showsTimeline)
        #expect(layout.timelineHeight == EditorWorkspaceLayout.defaultTimelineHeight)
    }

    @Test("Hides inspector before starving the stage")
    func hidesInspectorBeforeStageStarves() {
        let layout = EditorWorkspaceLayout.resolve(
            containerWidth: 820,
            containerHeight: 760,
            preferredInspectorWidth: 420,
            inspectorVisible: true,
            timelineVisible: true
        )

        #expect(!layout.showsInspector)
        #expect(layout.inspectorWidth == 0)
        #expect(layout.stageWidth == 820)
        #expect(layout.showsTimeline)
    }

    @Test("Hides timeline before starving preview height")
    func hidesTimelineBeforeStageHeightStarves() {
        let layout = EditorWorkspaceLayout.resolve(
            containerWidth: 1280,
            containerHeight: 420,
            preferredInspectorWidth: 420,
            inspectorVisible: true,
            timelineVisible: true
        )

        #expect(layout.showsInspector)
        #expect(!layout.showsTimeline)
        #expect(layout.timelineHeight == 0)
        #expect(layout.stageHeight >= EditorWorkspaceLayout.minimumStageHeight)
    }
}
