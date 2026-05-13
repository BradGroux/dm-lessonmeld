import Foundation

public struct ExportJob: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var editDecisionList: EditDecisionList
    public var destinationURL: URL
    public var preset: ExportPreset
    public var createdAt: Date
    public var status: ExportJobStatus

    public init(
        id: String,
        editDecisionList: EditDecisionList,
        destinationURL: URL,
        preset: ExportPreset,
        createdAt: Date = Date(),
        status: ExportJobStatus = .pending
    ) {
        self.id = id
        self.editDecisionList = editDecisionList
        self.destinationURL = destinationURL
        self.preset = preset
        self.createdAt = createdAt
        self.status = status
    }

    public func makePlan() throws -> ExportPlan {
        try ExportPlan(job: self)
    }
}

public enum ExportJobStatus: String, Codable, Sendable {
    case pending
    case planned
    case running
    case completed
    case failed
    case cancelled
}

public struct ExportPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var fileType: ExportFileType
    public var quality: ExportQuality
    public var includesChapterSidecar: Bool
    public var includesRetakeReport: Bool

    public init(
        id: String,
        fileType: ExportFileType = .mp4,
        quality: ExportQuality = .highest,
        includesChapterSidecar: Bool = true,
        includesRetakeReport: Bool = true
    ) {
        self.id = id
        self.fileType = fileType
        self.quality = quality
        self.includesChapterSidecar = includesChapterSidecar
        self.includesRetakeReport = includesRetakeReport
    }
}

public enum ExportFileType: String, Codable, CaseIterable, Sendable {
    case mp4
    case mov
}

public enum ExportQuality: String, Codable, CaseIterable, Sendable {
    case passthrough
    case medium
    case highest
}

public struct ExportPlan: Codable, Equatable, Sendable {
    public var jobID: String
    public var sourceMediaURL: URL
    public var destinationURL: URL
    public var sourceTimeRange: EditTimeRange
    public var cuts: [TimelineCut]
    public var speedRegions: [SpeedRegion]
    public var zoomRegions: [ZoomRegion]
    public var chapterMarkers: [TimelineMarker]
    public var retakeMarkers: [TimelineMarker]
    public var preset: ExportPreset
    public var validationIssues: [EditValidationIssue]

    public init(
        jobID: String,
        sourceMediaURL: URL,
        destinationURL: URL,
        sourceTimeRange: EditTimeRange,
        cuts: [TimelineCut] = [],
        speedRegions: [SpeedRegion] = [],
        zoomRegions: [ZoomRegion] = [],
        chapterMarkers: [TimelineMarker] = [],
        retakeMarkers: [TimelineMarker] = [],
        preset: ExportPreset,
        validationIssues: [EditValidationIssue] = []
    ) {
        self.jobID = jobID
        self.sourceMediaURL = sourceMediaURL
        self.destinationURL = destinationURL
        self.sourceTimeRange = sourceTimeRange
        self.cuts = cuts
        self.speedRegions = speedRegions
        self.zoomRegions = zoomRegions
        self.chapterMarkers = chapterMarkers
        self.retakeMarkers = retakeMarkers
        self.preset = preset
        self.validationIssues = validationIssues
    }

    public init(job: ExportJob) throws {
        let issues = job.editDecisionList.validate()
        let errors = issues.filter { $0.severity == .error }
        if !errors.isEmpty {
            throw EditValidationError(issues: issues)
        }

        guard let sourceMediaURL = job.editDecisionList.sourceMediaURL else {
            throw ExportPlanError.missingSourceMedia
        }

        guard let sourceTimeRange = job.editDecisionList.effectiveSourceRange else {
            throw ExportPlanError.missingSourceDuration
        }

        self.init(
            jobID: job.id,
            sourceMediaURL: sourceMediaURL,
            destinationURL: job.destinationURL,
            sourceTimeRange: sourceTimeRange,
            cuts: job.editDecisionList.enabledCuts,
            speedRegions: job.editDecisionList.speedRegions,
            zoomRegions: job.editDecisionList.enabledZoomRegions,
            chapterMarkers: job.editDecisionList.markers.filter { $0.kind == .chapter },
            retakeMarkers: job.editDecisionList.markers.filter { $0.kind == .retake },
            preset: job.preset,
            validationIssues: issues
        )
    }
}

public enum ExportPlanError: Error, Equatable, Sendable {
    case missingSourceMedia
    case missingSourceDuration
}
