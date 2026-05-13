import DMLessonMeldCore
import Testing

@Suite("Audio region validation")
struct AudioRegionTests {
    @Test("Accepts finite region inside total duration")
    func acceptsValidRegion() throws {
        let region = AudioRegion(startSeconds: 1.25, durationSeconds: 2.5, label: "intro")

        let validated = try region.validated(totalDurationSeconds: 4)

        #expect(validated.endSeconds == 3.75)
        #expect(validated.label == "intro")
    }

    @Test("Rejects invalid region times")
    func rejectsInvalidTimes() {
        #expect(throws: AudioRegionValidationError.negativeStart) {
            try AudioRegion(startSeconds: -0.1, durationSeconds: 1).validated()
        }
        #expect(throws: AudioRegionValidationError.nonPositiveDuration) {
            try AudioRegion(startSeconds: 0, durationSeconds: 0).validated()
        }
        #expect(throws: AudioRegionValidationError.exceedsTotalDuration) {
            try AudioRegion(startSeconds: 9, durationSeconds: 2).validated(totalDurationSeconds: 10)
        }
    }

    @Test("Detects overlapping regions")
    func detectsOverlap() {
        let first = AudioRegion(startSeconds: 2, durationSeconds: 3)
        let overlapping = AudioRegion(startSeconds: 4.5, durationSeconds: 2)
        let adjacent = AudioRegion(startSeconds: 5, durationSeconds: 1)

        #expect(first.overlaps(overlapping))
        #expect(first.overlaps(adjacent) == false)
    }
}
