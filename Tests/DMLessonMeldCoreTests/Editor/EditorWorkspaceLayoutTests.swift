import DMLessonMeldCore
import Foundation
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

    @Test("Viewport snapshots keep editor panes from overlapping", arguments: [
        (name: "desktop", width: 1680.0, height: 980.0, showsInspector: true, showsTimeline: true),
        (name: "laptop", width: 1180.0, height: 760.0, showsInspector: true, showsTimeline: true),
        (name: "narrow", width: 960.0, height: 640.0, showsInspector: false, showsTimeline: true),
        (name: "short", width: 1180.0, height: 420.0, showsInspector: true, showsTimeline: false)
    ])
    func viewportSnapshotsKeepEditorPanesFromOverlapping(name: String, width: Double, height: Double, showsInspector: Bool, showsTimeline: Bool) {
        let snapshot = EditorWorkspaceLayoutSnapshot.resolve(
            containerWidth: width,
            containerHeight: height,
            inspectorVisible: true,
            timelineVisible: true
        )

        #expect(!snapshot.hasOverlap, "\(name) layout should not overlap")
        #expect((snapshot.inspector != nil) == showsInspector)
        #expect((snapshot.timeline != nil) == showsTimeline)
        #expect(snapshot.stage.width >= EditorWorkspaceLayout.minimumStageWidth || !showsInspector)
        #expect(snapshot.stage.height >= EditorWorkspaceLayout.minimumStageHeight)
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

    @Test("App UI smoke fixtures cover primary surfaces and editor overlay panels")
    func appUISmokeFixturesCoverPrimarySurfacesAndEditorOverlayPanels() {
        let scenarios = UIRegressionFixtures.scenarios
        let surfaces = Set(scenarios.map(\.surface))

        #expect(surfaces.isSuperset(of: Set(AppUILayoutSurface.allCases)))
        #expect(scenarios.contains { $0.exercisesOverlayInspector })
        #expect(scenarios.contains { $0.exercisesCaptionInspector })

        for scenario in scenarios {
            #expect(!scenario.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!scenario.requiredPrimaryControls.isEmpty, "\(scenario.id) should define visible primary controls")
            #expect(scenario.viewport.width >= scenario.surface.minimumSize.width)
            #expect(scenario.viewport.height >= scenario.surface.minimumSize.height)
        }
    }

    @Test("Recorder control bar stable width fits active and setup controls")
    func recorderControlBarStableWidthFitsActiveAndSetupControls() {
        let setupWidth = RecorderControlBarLayout.requiredContentWidth(items: 10, dividers: 4)
        let activeRecordingWidth = RecorderControlBarLayout.requiredContentWidth(items: 9, dividers: 4) + 168

        #expect(setupWidth <= RecorderControlBarLayout.stableContentWidth)
        #expect(activeRecordingWidth <= RecorderControlBarLayout.stableContentWidth)
        #expect(RecorderControlBarLayout.stableWindowMinimumSize.width == 640)
    }
}
