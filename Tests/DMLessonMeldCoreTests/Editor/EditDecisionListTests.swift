import DMLessonMeldCore
import Foundation
import Testing

@Suite("Edit decision lists")
struct EditDecisionListTests {
    @Test("Validates trim, cuts, speed regions, zoom regions, and markers")
    func validatesUsableDecisionList() {
        let editDecisionList = EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: URL(fileURLWithPath: "/tmp/source.mov"),
            sourceDurationSeconds: 120,
            trimRange: EditTimeRange(startSeconds: 10, durationSeconds: 90),
            cuts: [
                TimelineCut(
                    id: "cut-1",
                    range: EditTimeRange(startSeconds: 20, durationSeconds: 5),
                    reason: "Retake"
                )
            ],
            speedRegions: [
                SpeedRegion(
                    id: "speed-1",
                    range: EditTimeRange(startSeconds: 50, durationSeconds: 10),
                    playbackRate: 1.25
                )
            ],
            zoomRegions: [
                ZoomRegion(
                    id: "zoom-1",
                    range: EditTimeRange(startSeconds: 35, durationSeconds: 5),
                    focusRect: NormalizedEditRect(x: 0.25, y: 0.2, width: 0.45, height: 0.45),
                    scale: 1.7
                )
            ],
            markers: [
                TimelineMarker(id: "chapter-1", kind: .chapter, timeSeconds: 10, title: "Intro"),
                TimelineMarker(id: "retake-1", kind: .retake, timeSeconds: 20, title: "Retake")
            ]
        )

        #expect(editDecisionList.validate() == [])
    }

    @Test("Reports invalid ranges and overlapping enabled cuts")
    func reportsInvalidRangesAndOverlappingCuts() {
        let editDecisionList = EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: URL(fileURLWithPath: "/tmp/source.mov"),
            sourceDurationSeconds: 30,
            trimRange: EditTimeRange(startSeconds: 5, durationSeconds: 20),
            cuts: [
                TimelineCut(id: "cut-1", range: EditTimeRange(startSeconds: 10, durationSeconds: 8)),
                TimelineCut(id: "cut-2", range: EditTimeRange(startSeconds: 12, durationSeconds: 3)),
                TimelineCut(id: "cut-3", range: EditTimeRange(startSeconds: 28, durationSeconds: 1))
            ],
            speedRegions: [
                SpeedRegion(id: "speed-1", range: EditTimeRange(startSeconds: 8, durationSeconds: 4), playbackRate: 0)
            ],
            zoomRegions: [
                ZoomRegion(id: "zoom-1", range: EditTimeRange(startSeconds: 12, durationSeconds: 4), focusRect: NormalizedEditRect(x: 0.8, y: 0.8, width: 0.4, height: 0.4), scale: 1),
                ZoomRegion(id: "zoom-2", range: EditTimeRange(startSeconds: 13, durationSeconds: 2), scale: 1.5)
            ],
            markers: [
                TimelineMarker(id: "marker-1", kind: .chapter, timeSeconds: 31, title: "")
            ]
        )

        let codes = editDecisionList.validate().map(\.code)

        #expect(codes.contains(.overlappingCuts))
        #expect(codes.contains(.overlappingZoomRegions))
        #expect(codes.contains(.rangeOutsideSource))
        #expect(codes.contains(.invalidPlaybackRate))
        #expect(codes.contains(.invalidZoomScale))
        #expect(codes.contains(.invalidFocusRect))
        #expect(codes.contains(.markerOutsideSource))
        #expect(codes.contains(.emptyMarkerTitle))
    }

    @Test("Ignores disabled cuts for overlap checks")
    func ignoresDisabledCutsForOverlapChecks() {
        let editDecisionList = EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: URL(fileURLWithPath: "/tmp/source.mov"),
            sourceDurationSeconds: 30,
            cuts: [
                TimelineCut(id: "cut-1", range: EditTimeRange(startSeconds: 5, durationSeconds: 10)),
                TimelineCut(id: "cut-2", range: EditTimeRange(startSeconds: 8, durationSeconds: 2), isEnabled: false)
            ]
        )

        #expect(!editDecisionList.validate().map(\.code).contains(.overlappingCuts))
    }

    @Test("Edit decision lists persist as project sidecars")
    func persistsProjectSidecar() throws {
        let temp = try TemporaryDirectory()
        let editDecisionList = EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: temp.url.appendingPathComponent("screen.mp4"),
            sourceDurationSeconds: 90,
            trimRange: EditTimeRange(startSeconds: 5, durationSeconds: 60),
            cuts: [
                TimelineCut(id: "cut-1", range: EditTimeRange(startSeconds: 20, durationSeconds: 4), reason: "Retake")
            ],
            zoomRegions: [
                ZoomRegion(
                    id: "zoom-1",
                    range: EditTimeRange(startSeconds: 12, durationSeconds: 3),
                    scale: 1.6,
                    focusMode: .clickMetadata,
                    easing: .instant
                )
            ]
        )

        try EditDecisionListFile.save(editDecisionList, toProject: temp.url)

        #expect(EditDecisionListFile.exists(in: temp.url))
        let loaded = try EditDecisionListFile.load(fromProject: temp.url)
        #expect(loaded == editDecisionList)
    }

    @Test("Timeline compiler removes enabled cuts from the active source range")
    func compilesRetainedRanges() {
        let retained = EditTimelineCompiler.retainedRanges(
            sourceRange: EditTimeRange(startSeconds: 10, endSeconds: 30),
            cuts: [
                TimelineCut(id: "before", range: EditTimeRange(startSeconds: 0, endSeconds: 4)),
                TimelineCut(id: "first", range: EditTimeRange(startSeconds: 12, endSeconds: 14)),
                TimelineCut(id: "disabled", range: EditTimeRange(startSeconds: 16, endSeconds: 18), isEnabled: false),
                TimelineCut(id: "second", range: EditTimeRange(startSeconds: 20, endSeconds: 25))
            ]
        )

        #expect(retained == [
            EditTimeRange(startSeconds: 10, endSeconds: 12),
            EditTimeRange(startSeconds: 14, endSeconds: 20),
            EditTimeRange(startSeconds: 25, endSeconds: 30)
        ])
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
