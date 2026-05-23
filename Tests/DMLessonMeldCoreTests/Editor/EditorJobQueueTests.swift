import DMLessonMeldCore
import Foundation
import Testing

@Suite("Editor job queue")
struct EditorJobQueueTests {
    @Test("Job records clamp progress and capture transitions")
    func recordsClampProgressAndCaptureTransitions() {
        let created = Date(timeIntervalSince1970: 100)
        let started = Date(timeIntervalSince1970: 110)
        let finished = Date(timeIntervalSince1970: 120)
        var record = EditorJobRecord(
            id: "job-1",
            kind: .renderVideo,
            projectPath: "/tmp/lesson.dmlm",
            progress: -0.5,
            createdAt: created
        )

        #expect(record.progress == 0)
        #expect(record.status == .queued)

        record.start(at: started)
        record.updateProgress(1.4, message: "Almost done.", at: started)
        record.complete(outputPath: "/tmp/output.mp4", at: finished)

        #expect(record.status == .completed)
        #expect(record.progress == 1)
        #expect(record.startedAt == started)
        #expect(record.finishedAt == finished)
        #expect(record.outputPath == "/tmp/output.mp4")
        #expect(record.log.count == 3)
    }

    @Test("Failed and cancelled jobs are retryable when kind supports retry")
    func failedAndCancelledJobsAreRetryable() {
        var failed = EditorJobRecord(kind: .rawAssetExtract)
        failed.start()
        failed.fail("Disk is full.")

        var cancelled = EditorJobRecord(kind: .renderVideo)
        cancelled.start()
        cancelled.cancel()

        #expect(failed.isRetryable)
        #expect(cancelled.isRetryable)
        #expect(!failed.isActive)
        #expect(!cancelled.isActive)
    }

    @Test("Conflict policy blocks exclusive jobs for the same project")
    func conflictPolicyBlocksExclusiveJobsForSameProject() {
        var active = EditorJobRecord(kind: .renderVideo, projectPath: "/tmp/project.dmlm")
        active.start()
        let records = [active]

        let conflict = EditorJobConflictPolicy.conflictingActiveJob(
            in: records,
            projectPath: "/tmp/project.dmlm",
            kind: .sharePackage
        )
        let frameCopyConflict = EditorJobConflictPolicy.conflictingActiveJob(
            in: records,
            projectPath: "/tmp/project.dmlm",
            kind: .frameCopy
        )
        let otherProjectConflict = EditorJobConflictPolicy.conflictingActiveJob(
            in: records,
            projectPath: "/tmp/other.dmlm",
            kind: .sharePackage
        )

        #expect(conflict?.id == active.id)
        #expect(frameCopyConflict == nil)
        #expect(otherProjectConflict == nil)
    }

    @Test("Long-running editor jobs support cancellation")
    func longRunningEditorJobsSupportCancellation() {
        let cancellableKinds: Set<EditorJobKind> = [
            .renderVideo,
            .trimExport,
            .editDecisionExport,
            .learnHousePackage,
            .rawAssetExtract,
            .sharePackage,
            .frameExport,
            .frameCopy
        ]

        for kind in EditorJobKind.allCases {
            #expect(kind.supportsCancellation == cancellableKinds.contains(kind))
        }
    }

    @Test("Cancellation policy selects active cancellable jobs for the current project")
    func cancellationPolicySelectsActiveCancellableJobsForCurrentProject() {
        let projectPath = "/tmp/project.dmlm"
        let cancellableKinds: [EditorJobKind] = [
            .renderVideo,
            .trimExport,
            .editDecisionExport,
            .learnHousePackage,
            .rawAssetExtract,
            .sharePackage,
            .frameExport,
            .frameCopy
        ]
        var records = cancellableKinds.map { kind in
            var record = EditorJobRecord(
                id: kind.rawValue,
                kind: kind,
                projectPath: projectPath
            )
            record.start()
            return record
        }
        var completed = EditorJobRecord(
            id: "completed-render",
            kind: .renderVideo,
            projectPath: projectPath
        )
        completed.start()
        completed.complete()
        records.append(completed)

        var otherProject = EditorJobRecord(
            id: "other-project",
            kind: .sharePackage,
            projectPath: "/tmp/other.dmlm"
        )
        otherProject.start()
        records.append(otherProject)

        var captionSidecars = EditorJobRecord(
            id: "caption-sidecars",
            kind: .captionSidecars,
            projectPath: projectPath
        )
        captionSidecars.start()
        records.append(captionSidecars)

        let selectedIDs = Set(EditorJobCancellationPolicy.cancellableActiveJobIDs(
            in: records,
            projectPath: projectPath
        ))

        #expect(selectedIDs == Set(cancellableKinds.map(\.rawValue)))
    }

    @Test("Job history persists recent records")
    func jobHistoryPersistsRecentRecords() throws {
        let temp = try TemporaryDirectory()
        let records = (0..<5).map { index in
            EditorJobRecord(
                id: "job-\(index)",
                kind: .renderVideo,
                projectPath: temp.url.path,
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        try EditorJobHistoryFile.save(records, toProject: temp.url, limit: 3)

        let loaded = try EditorJobHistoryFile.load(fromProject: temp.url)
        #expect(loaded.map(\.id) == ["job-0", "job-1", "job-2"])
    }

    @Test("Job history persistence redacts absolute paths")
    func jobHistoryPersistenceRedactsAbsolutePaths() throws {
        let temp = try TemporaryDirectory()
        let outputPath = temp.url.appendingPathComponent("Exports/final.mp4").path
        var record = EditorJobRecord(
            id: "job-1",
            kind: .renderVideo,
            projectPath: temp.url.path,
            outputPath: outputPath
        )
        record.complete(outputPath: outputPath, message: "Rendered video to \(outputPath).")

        try EditorJobHistoryFile.save([record], toProject: temp.url)

        let loaded = try #require(EditorJobHistoryFile.load(fromProject: temp.url).first)
        #expect(loaded.projectPath == temp.url.lastPathComponent)
        #expect(loaded.outputPath == "Exports/final.mp4")
        #expect(!loaded.log.joined(separator: "\n").contains(temp.url.path))
        #expect(loaded.outputDisplayPath == "Exports/final.mp4")
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
