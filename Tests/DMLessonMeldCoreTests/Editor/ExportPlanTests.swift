import DMLessonMeldCore
import Foundation
import Testing

@Suite("Editor export plans")
struct ExportPlanTests {
    @Test("Builds a consumable export plan from a valid job")
    func buildsExportPlan() throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mov")
        let destinationURL = URL(fileURLWithPath: "/tmp/output.mp4")
        let editDecisionList = EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: sourceURL,
            sourceDurationSeconds: 60,
            trimRange: EditTimeRange(startSeconds: 5, durationSeconds: 30),
            zoomRegions: [
                ZoomRegion(id: "zoom-1", range: EditTimeRange(startSeconds: 10, durationSeconds: 4), scale: 1.5)
            ],
            markers: [
                TimelineMarker(id: "chapter-1", kind: .chapter, timeSeconds: 5, title: "Intro"),
                TimelineMarker(id: "retake-1", kind: .retake, timeSeconds: 12, title: "Clean take"),
                TimelineMarker(id: "note-1", kind: .note, timeSeconds: 18, title: "Mention docs")
            ]
        )
        let job = ExportJob(
            id: "export-1",
            editDecisionList: editDecisionList,
            destinationURL: destinationURL,
            preset: ExportPreset(id: "mp4-high")
        )

        let plan = try job.makePlan()

        #expect(plan.jobID == "export-1")
        #expect(plan.sourceMediaURL == sourceURL)
        #expect(plan.destinationURL == destinationURL)
        #expect(plan.sourceTimeRange == EditTimeRange(startSeconds: 5, durationSeconds: 30))
        #expect(plan.zoomRegions.map(\.id) == ["zoom-1"])
        #expect(plan.chapterMarkers.map(\.id) == ["chapter-1"])
        #expect(plan.retakeMarkers.map(\.id) == ["retake-1"])
        #expect(plan.validationIssues == [])
    }

    @Test("Rejects export plans with model validation errors")
    func rejectsInvalidPlans() {
        let editDecisionList = EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: URL(fileURLWithPath: "/tmp/source.mov"),
            sourceDurationSeconds: 10,
            trimRange: EditTimeRange(startSeconds: 9, durationSeconds: 5)
        )
        let job = ExportJob(
            id: "export-1",
            editDecisionList: editDecisionList,
            destinationURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            preset: ExportPreset(id: "mp4-high")
        )

        #expect(throws: EditValidationError.self) {
            try job.makePlan()
        }
    }

    @Test("Requires source duration when no trim range is present")
    func requiresSourceDurationForUntrimmedPlan() {
        let editDecisionList = EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: URL(fileURLWithPath: "/tmp/source.mov")
        )
        let job = ExportJob(
            id: "export-1",
            editDecisionList: editDecisionList,
            destinationURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            preset: ExportPreset(id: "mp4-high")
        )

        #expect(throws: ExportPlanError.self) {
            try job.makePlan()
        }
    }
}
