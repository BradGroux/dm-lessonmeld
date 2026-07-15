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
        (name: "narrow", width: 960.0, height: 680.0, showsInspector: false, showsTimeline: true),
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

    @Test("Timeline toolbar presentations preserve every action exactly once")
    func timelineToolbarPresentationsPreserveEveryActionExactlyOnce() {
        for presentation in TimelineToolbarPresentation.allCases {
            let direct = presentation.directActions
            let overflow = presentation.overflowActions

            #expect(Set(direct).isDisjoint(with: Set(overflow)))
            #expect(Set(direct + overflow) == Set(TimelineToolbarAction.allCases))
            #expect(direct.count + overflow.count == TimelineToolbarAction.allCases.count)
        }
    }

    @Test("Compact timeline toolbar keeps precision actions direct and names every command")
    func compactTimelineToolbarKeepsPrecisionActionsDirectAndNamesEveryCommand() {
        let compact = TimelineToolbarPresentation.compact

        #expect(compact.directActions == [.backOneSecond, .forwardOneSecond, .cut, .zoom, .delete, .save])
        #expect(!compact.overflowActions.isEmpty)
        #expect(Set(TimelineToolbarAction.allCases.map(\.title)).count == TimelineToolbarAction.allCases.count)
        #expect(TimelineToolbarAction.delete.title == "Delete")
    }

    @Test("Narrow video editor fixture matches runtime minimum and guards timeline controls")
    func narrowVideoEditorFixtureMatchesRuntimeMinimumAndGuardsTimelineControls() throws {
        let scenario = try #require(UIRegressionFixtures.scenarios.first { $0.id == "video-editor-narrow" })

        #expect(scenario.viewport == AppUILayoutSurface.videoEditor.minimumSize)
        #expect(scenario.requiredPrimaryControls.contains("Video timeline"))
        #expect(scenario.requiredPrimaryControls.contains("Cut"))
        #expect(scenario.requiredPrimaryControls.contains("More timeline actions"))
        #expect(scenario.requiredPrimaryControls.contains("Timeline scale"))
    }

    @Test("Rendered UI launch arguments require an explicit fixture and artifact directory")
    func renderedUILaunchArgumentsRequireFixtureAndArtifactDirectory() throws {
        let configuration = try #require(RenderedUIRegressionLaunchConfiguration.parse(arguments: [
            "DMLessonMeld",
            "--ui-regression-fixture", "video-editor-overlays",
            "--ui-regression-output", "/tmp/ui-artifacts",
            "--ui-regression-appearance", "dark"
        ]))

        #expect(configuration.fixtureID == "video-editor-overlays")
        #expect(configuration.outputDirectory == "/tmp/ui-artifacts")
        #expect(configuration.appearance == .dark)
        #expect(RenderedUIRegressionLaunchConfiguration.parse(arguments: [
            "DMLessonMeld",
            "--ui-regression-fixture", "video-editor-overlays"
        ]) == nil)
    }

    @Test("Rendered UI audit catches missing, clipped, mislabeled, and overlapping controls")
    func renderedUIAuditCatchesStructuralRegressions() {
        let window = UILayoutRect(x: 0, y: 0, width: 960, height: 680)
        let elements = [
            RenderedUIElement(label: "Video preview", role: "group", frame: UILayoutRect(x: 250, y: 0, width: 510, height: 480)),
            RenderedUIElement(label: "Timeline", role: "group", frame: UILayoutRect(x: 250, y: 480, width: 710, height: 200)),
            RenderedUIElement(label: "Cut", role: "button", frame: UILayoutRect(x: 300, y: 500, width: 44, height: 28)),
            RenderedUIElement(label: "Timeline scale", role: "slider", frame: UILayoutRect(x: 880, y: 500, width: 96, height: 28)),
            RenderedUIElement(label: "Detached action", role: "button", frame: UILayoutRect(x: 300, y: 300, width: 90, height: 28))
        ]

        let findings = RenderedUIAudit.findings(
            elements: elements,
            windowFrame: window,
            requiredLabels: ["Cut", "More timeline actions", "Timeline scale", "Detached action"],
            paneLabels: ["Video preview", "Timeline"],
            ownerLabels: [
                "Cut": "Timeline",
                "Timeline scale": "Timeline",
                "Detached action": "Timeline"
            ]
        )

        #expect(findings.contains { $0.kind == .missing && $0.label == "More timeline actions" })
        #expect(findings.contains { $0.kind == .clipped && $0.label == "Timeline scale" })
        #expect(findings.contains { $0.kind == .clipped && $0.label == "Detached action" })
        #expect(!findings.contains { $0.kind == .overlap })

        let missingPaneFindings = RenderedUIAudit.findings(
            elements: elements,
            windowFrame: window,
            requiredLabels: [],
            paneLabels: ["Missing pane"]
        )
        #expect(missingPaneFindings.contains { $0.kind == .missing && $0.label == "Missing pane" })

        let overlapping = elements + [
            RenderedUIElement(label: "Editor panel", role: "group", frame: UILayoutRect(x: 700, y: 0, width: 260, height: 520))
        ]
        let overlapFindings = RenderedUIAudit.findings(
            elements: overlapping,
            windowFrame: window,
            requiredLabels: [],
            paneLabels: ["Video preview", "Timeline", "Editor panel"]
        )
        #expect(overlapFindings.contains { $0.kind == .overlap })
    }

    @Test("Rendered UI screenshot fingerprints tolerate small variance and reject structural change")
    func renderedUIScreenshotFingerprintsDetectStructuralChange() throws {
        let baseline = RenderedUIScreenshotFingerprint(
            columns: 2,
            rows: 2,
            luminance: [0.10, 0.20, 0.30, 0.40]
        )
        let close = RenderedUIScreenshotFingerprint(
            columns: 2,
            rows: 2,
            luminance: [0.11, 0.19, 0.31, 0.39]
        )
        let changed = RenderedUIScreenshotFingerprint(
            columns: 2,
            rows: 2,
            luminance: [0.70, 0.80, 0.90, 1.00]
        )

        #expect(try #require(baseline.meanAbsoluteDifference(from: close)) < 0.02)
        #expect(try #require(baseline.meanAbsoluteDifference(from: changed)) > 0.40)
        #expect(baseline.meanAbsoluteDifference(from: RenderedUIScreenshotFingerprint(columns: 1, rows: 1, luminance: [0.1])) == nil)
    }
}
