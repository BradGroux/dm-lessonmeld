import Foundation

public struct EditValidationIssue: Codable, Equatable, Sendable {
    public var severity: EditValidationSeverity
    public var code: EditValidationCode
    public var path: String
    public var message: String

    public init(
        severity: EditValidationSeverity,
        code: EditValidationCode,
        path: String,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.path = path
        self.message = message
    }
}

public enum EditValidationSeverity: String, Codable, Sendable {
    case warning
    case error
}

public enum EditValidationCode: String, Codable, Sendable {
    case invalidRange
    case rangeOutsideSource
    case duplicateIdentifier
    case overlappingCuts
    case overlappingZoomRegions
    case invalidPlaybackRate
    case invalidZoomScale
    case invalidFocusRect
    case markerOutsideSource
    case emptyMarkerTitle
    case missingSourceMedia
}

public struct EditValidationError: Error, Equatable, Sendable {
    public var issues: [EditValidationIssue]

    public init(issues: [EditValidationIssue]) {
        self.issues = issues
    }
}

public enum EditDecisionListValidator {
    public static func validate(_ editDecisionList: EditDecisionList) -> [EditValidationIssue] {
        var issues: [EditValidationIssue] = []

        if editDecisionList.sourceMediaURL == nil {
            issues.append(
                EditValidationIssue(
                    severity: .warning,
                    code: .missingSourceMedia,
                    path: "sourceMediaURL",
                    message: "No source media URL is attached to the edit decision list."
                )
            )
        }

        if let sourceDurationSeconds = editDecisionList.sourceDurationSeconds,
           !isValidDuration(sourceDurationSeconds) {
            issues.append(
                EditValidationIssue(
                    severity: .error,
                    code: .invalidRange,
                    path: "sourceDurationSeconds",
                    message: "Source duration must be finite and greater than zero."
                )
            )
        }

        if let trimRange = editDecisionList.trimRange {
            issues += validate(range: trimRange, path: "trimRange")
            issues += validateWithinSource(
                range: trimRange,
                sourceDurationSeconds: editDecisionList.sourceDurationSeconds,
                path: "trimRange"
            )
        }

        issues += validateUniqueIDs(
            editDecisionList.cuts.map(\.id),
            basePath: "cuts"
        )
        issues += validateUniqueIDs(
            editDecisionList.speedRegions.map(\.id),
            basePath: "speedRegions"
        )
        issues += validateUniqueIDs(
            editDecisionList.zoomRegions.map(\.id),
            basePath: "zoomRegions"
        )
        issues += validateUniqueIDs(
            editDecisionList.markers.map(\.id),
            basePath: "markers"
        )

        let enabledCuts = editDecisionList.enabledCuts.enumerated().map { index, cut in
            (index: index, cut: cut)
        }

        for (index, cut) in enabledCuts {
            let path = "cuts[\(index)].range"
            issues += validate(range: cut.range, path: path)
            issues += validateWithinActiveRange(
                range: cut.range,
                editDecisionList: editDecisionList,
                path: path
            )
        }

        for leftIndex in enabledCuts.indices {
            for rightIndex in enabledCuts.indices where rightIndex > leftIndex {
                let left = enabledCuts[leftIndex]
                let right = enabledCuts[rightIndex]
                if left.cut.range.overlaps(right.cut.range) {
                    issues.append(
                        EditValidationIssue(
                            severity: .error,
                            code: .overlappingCuts,
                            path: "cuts[\(right.index)].range",
                            message: "Enabled cuts must not overlap."
                        )
                    )
                }
            }
        }

        for (index, speedRegion) in editDecisionList.speedRegions.enumerated() {
            let path = "speedRegions[\(index)]"
            issues += validate(range: speedRegion.range, path: "\(path).range")
            issues += validateWithinActiveRange(
                range: speedRegion.range,
                editDecisionList: editDecisionList,
                path: "\(path).range"
            )

            if !speedRegion.playbackRate.isFinite || speedRegion.playbackRate <= 0 {
                issues.append(
                    EditValidationIssue(
                        severity: .error,
                        code: .invalidPlaybackRate,
                        path: "\(path).playbackRate",
                        message: "Playback rate must be finite and greater than zero."
                    )
                )
            }
        }

        let enabledZoomRegions = editDecisionList.enabledZoomRegions.enumerated().map { index, zoomRegion in
            (index: index, zoomRegion: zoomRegion)
        }

        for (index, zoomRegion) in enabledZoomRegions {
            let path = "zoomRegions[\(index)]"
            issues += validate(range: zoomRegion.range, path: "\(path).range")
            issues += validateWithinActiveRange(
                range: zoomRegion.range,
                editDecisionList: editDecisionList,
                path: "\(path).range"
            )

            if !zoomRegion.scale.isFinite || zoomRegion.scale <= 1 || zoomRegion.scale > 6 {
                issues.append(
                    EditValidationIssue(
                        severity: .error,
                        code: .invalidZoomScale,
                        path: "\(path).scale",
                        message: "Zoom scale must be finite, greater than 1, and no more than 6."
                    )
                )
            }

            if zoomRegion.focusRect.width <= 0 ||
                zoomRegion.focusRect.height <= 0 ||
                zoomRegion.focusRect.x + zoomRegion.focusRect.width > 1 ||
                zoomRegion.focusRect.y + zoomRegion.focusRect.height > 1 {
                issues.append(
                    EditValidationIssue(
                        severity: .error,
                        code: .invalidFocusRect,
                        path: "\(path).focusRect",
                        message: "Zoom focus rect must have positive size and stay inside the normalized frame."
                    )
                )
            }
        }

        for leftIndex in enabledZoomRegions.indices {
            for rightIndex in enabledZoomRegions.indices where rightIndex > leftIndex {
                let left = enabledZoomRegions[leftIndex]
                let right = enabledZoomRegions[rightIndex]
                if left.zoomRegion.range.overlaps(right.zoomRegion.range) {
                    issues.append(
                        EditValidationIssue(
                            severity: .error,
                            code: .overlappingZoomRegions,
                            path: "zoomRegions[\(right.index)].range",
                            message: "Enabled zoom regions must not overlap."
                        )
                    )
                }
            }
        }

        for (index, marker) in editDecisionList.markers.enumerated() {
            let path = "markers[\(index)]"
            if !marker.timeSeconds.isFinite || marker.timeSeconds < 0 {
                issues.append(
                    EditValidationIssue(
                        severity: .error,
                        code: .markerOutsideSource,
                        path: "\(path).timeSeconds",
                        message: "Marker time must be finite and non-negative."
                    )
                )
            }

            if let activeRange = editDecisionList.effectiveSourceRange,
               !activeRange.contains(marker.timeSeconds) {
                issues.append(
                    EditValidationIssue(
                        severity: .error,
                        code: .markerOutsideSource,
                        path: "\(path).timeSeconds",
                        message: "Marker time must be inside the active source range."
                    )
                )
            }

            if marker.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(
                    EditValidationIssue(
                        severity: .error,
                        code: .emptyMarkerTitle,
                        path: "\(path).title",
                        message: "Marker title cannot be empty."
                    )
                )
            }
        }

        return issues
    }

    private static func validate(range: EditTimeRange, path: String) -> [EditValidationIssue] {
        guard range.startSeconds.isFinite,
              range.durationSeconds.isFinite,
              range.startSeconds >= 0,
              range.durationSeconds > 0 else {
            return [
                EditValidationIssue(
                    severity: .error,
                    code: .invalidRange,
                    path: path,
                    message: "Range start must be finite and non-negative, and duration must be finite and greater than zero."
                )
            ]
        }

        return []
    }

    private static func validateWithinActiveRange(
        range: EditTimeRange,
        editDecisionList: EditDecisionList,
        path: String
    ) -> [EditValidationIssue] {
        guard validate(range: range, path: path).isEmpty else {
            return []
        }

        guard let activeRange = editDecisionList.effectiveSourceRange else {
            return []
        }

        if range.startSeconds < activeRange.startSeconds || range.endSeconds > activeRange.endSeconds {
            return [
                EditValidationIssue(
                    severity: .error,
                    code: .rangeOutsideSource,
                    path: path,
                    message: "Range must be inside the active source range."
                )
            ]
        }

        return []
    }

    private static func validateWithinSource(
        range: EditTimeRange,
        sourceDurationSeconds: Double?,
        path: String
    ) -> [EditValidationIssue] {
        guard validate(range: range, path: path).isEmpty else {
            return []
        }

        guard let sourceDurationSeconds, isValidDuration(sourceDurationSeconds) else {
            return []
        }

        if range.endSeconds > sourceDurationSeconds {
            return [
                EditValidationIssue(
                    severity: .error,
                    code: .rangeOutsideSource,
                    path: path,
                    message: "Range must end before the source duration."
                )
            ]
        }

        return []
    }

    private static func validateUniqueIDs(_ ids: [String], basePath: String) -> [EditValidationIssue] {
        var seen: Set<String> = []
        var issues: [EditValidationIssue] = []

        for (index, id) in ids.enumerated() {
            if !seen.insert(id).inserted {
                issues.append(
                    EditValidationIssue(
                        severity: .error,
                        code: .duplicateIdentifier,
                        path: "\(basePath)[\(index)].id",
                        message: "Identifiers must be unique within \(basePath)."
                    )
                )
            }
        }

        return issues
    }

    private static func isValidDuration(_ duration: Double) -> Bool {
        duration.isFinite && duration > 0
    }
}
