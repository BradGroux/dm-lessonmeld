import Foundation

public struct RenderValidationOptions: Codable, Equatable, Sendable {
    public var checkFileExistence: Bool
    public var checkDestinationDoesNotExist: Bool

    public init(checkFileExistence: Bool = false, checkDestinationDoesNotExist: Bool = false) {
        self.checkFileExistence = checkFileExistence
        self.checkDestinationDoesNotExist = checkDestinationDoesNotExist
    }

    public static let export = RenderValidationOptions(
        checkFileExistence: true,
        checkDestinationDoesNotExist: true
    )
}

public struct RenderValidationIssue: Codable, Equatable, Sendable {
    public var severity: Severity
    public var message: String
    public var path: String?

    public init(severity: Severity, message: String, path: String? = nil) {
        self.severity = severity
        self.message = message
        self.path = path
    }

    public enum Severity: String, Codable, Sendable {
        case warning
        case error
    }
}

public struct RenderValidationError: Error, Equatable, LocalizedError, Sendable {
    public var issues: [RenderValidationIssue]

    public init(issues: [RenderValidationIssue]) {
        self.issues = issues
    }

    public var errorDescription: String? {
        issues.map(\.message).joined(separator: " ")
    }
}

public enum RenderPlanValidator {
    public static func validate(
        _ plan: RenderPlan,
        options: RenderValidationOptions = RenderValidationOptions(),
        fileManager: FileManager = .default
    ) -> [RenderValidationIssue] {
        var issues: [RenderValidationIssue] = []

        if plan.screenVideo.relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Screen video path is required."
            ))
        }

        if !plan.destinationURL.isFileURL {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Render destination must be a local file URL.",
                path: plan.destinationURL.path
            ))
        }

        let expectedExtension = plan.preset.fileType.fileExtension
        if plan.destinationURL.pathExtension.lowercased() != expectedExtension {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Render destination extension must match \(expectedExtension).",
                path: plan.destinationURL.path
            ))
        }

        if plan.webcamOverlay != nil {
            validatePictureInPicture(plan.webcamOverlay!.placement, issues: &issues)
        }

        validateZoomRegions(plan.zoomRegions, issues: &issues)
        if let annotationSource = plan.annotationSource {
            validateAnnotations(annotationSource, issues: &issues, fileManager: fileManager)
        }

        if options.checkFileExistence {
            for source in plan.requiredMediaSources {
                if !fileManager.fileExists(atPath: source.url.path) {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "\(source.role.rawValue) file is missing.",
                        path: source.relativePath
                    ))
                }
            }
        }

        if options.checkDestinationDoesNotExist, fileManager.fileExists(atPath: plan.destinationURL.path) {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Render destination already exists.",
                path: plan.destinationURL.path
            ))
        }

        return issues
    }

    private static func validatePictureInPicture(
        _ placement: PictureInPicturePlacement,
        issues: inout [RenderValidationIssue]
    ) {
        if placement.widthRatio <= 0 || placement.widthRatio >= 1 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Picture-in-picture width ratio must be greater than 0 and less than 1."
            ))
        }

        if placement.marginRatio < 0 || placement.marginRatio >= 0.5 {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Picture-in-picture margin ratio must be greater than or equal to 0 and less than 0.5."
            ))
        }
    }

    private static func validateZoomRegions(
        _ zoomRegions: [ZoomRegion],
        issues: inout [RenderValidationIssue]
    ) {
        for (index, region) in zoomRegions.enumerated() {
            let path = "zoomRegions[\(index)]"
            if !region.range.startSeconds.isFinite ||
                !region.range.durationSeconds.isFinite ||
                region.range.startSeconds < 0 ||
                region.range.durationSeconds <= 0 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Zoom region range must be finite and positive.",
                    path: "\(path).range"
                ))
            }

            if !region.scale.isFinite || region.scale <= 1 || region.scale > 6 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Zoom scale must be finite, greater than 1, and no more than 6.",
                    path: "\(path).scale"
                ))
            }

            if region.focusRect.width <= 0 ||
                region.focusRect.height <= 0 ||
                region.focusRect.x + region.focusRect.width > 1 ||
                region.focusRect.y + region.focusRect.height > 1 {
                issues.append(RenderValidationIssue(
                    severity: .error,
                    message: "Zoom focus rect must have positive size and stay inside the normalized frame.",
                    path: "\(path).focusRect"
                ))
            }
        }
    }

    private static func validateAnnotations(
        _ source: RenderMediaSource,
        issues: inout [RenderValidationIssue],
        fileManager: FileManager
    ) {
        guard fileManager.fileExists(atPath: source.url.path) else { return }
        do {
            let data = try Data(contentsOf: source.url)
            let store = try DMLessonJSON.decoder().decode(AnnotationStore.self, from: data)
            for (index, annotation) in store.annotations.enumerated() {
                let path = "annotations[\(index)]"
                if let timeRange = annotation.timeRange, !timeRange.isValid {
                    issues.append(RenderValidationIssue(
                        severity: .error,
                        message: "Annotation time range must be finite, non-negative, and end after start.",
                        path: "\(path).timeRange"
                    ))
                }

                switch annotation.coordinateSpace {
                case .normalizedCapture:
                    let points = annotation.normalizedPoints ?? []
                    if points.isEmpty {
                        issues.append(RenderValidationIssue(
                            severity: .error,
                            message: "Normalized annotations must include normalized points.",
                            path: "\(path).normalizedPoints"
                        ))
                    }
                    if points.contains(where: { !$0.isValid }) {
                        issues.append(RenderValidationIssue(
                            severity: .error,
                            message: "Normalized annotation points must stay inside the capture frame.",
                            path: "\(path).normalizedPoints"
                        ))
                    }
                case .legacyCanvasPoints:
                    issues.append(RenderValidationIssue(
                        severity: .warning,
                        message: "Legacy point annotations render in canvas coordinates; normalized capture coordinates are preferred.",
                        path: "\(path).points"
                    ))
                }
            }
        } catch {
            issues.append(RenderValidationIssue(
                severity: .error,
                message: "Annotation sidecar could not be decoded.",
                path: source.relativePath
            ))
        }
    }
}

extension RenderPlan {
    var requiredMediaSources: [RenderMediaSource] {
        var sources = [screenVideo]
        if let webcamOverlay {
            sources.append(webcamOverlay.source)
        }
        sources.append(contentsOf: audioSources)
        if let cursorSource {
            sources.append(cursorSource)
        }
        if let annotationSource {
            sources.append(annotationSource)
        }
        if let captionSource {
            sources.append(captionSource)
        }
        return sources
    }
}
