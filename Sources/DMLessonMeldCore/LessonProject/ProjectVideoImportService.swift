import Foundation

public struct ProjectVideoImportRequest: Sendable {
    public var sourceURL: URL
    public var defaultProjectDirectory: String
    public var defaultTemplateID: String
    public var existingProjectURL: URL?
    public var existingManifest: ProjectManifest?

    public init(
        sourceURL: URL,
        defaultProjectDirectory: String,
        defaultTemplateID: String,
        existingProjectURL: URL? = nil,
        existingManifest: ProjectManifest? = nil
    ) {
        self.sourceURL = sourceURL
        self.defaultProjectDirectory = defaultProjectDirectory
        self.defaultTemplateID = defaultTemplateID
        self.existingProjectURL = existingProjectURL
        self.existingManifest = existingManifest
    }
}

public struct ProjectVideoImportResult: Codable, Equatable, Sendable {
    public var projectURL: URL
    public var manifest: ProjectManifest

    public init(projectURL: URL, manifest: ProjectManifest) {
        self.projectURL = projectURL
        self.manifest = manifest
    }
}

public enum ProjectVideoImportError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVideoType(String)
    case templateNotFound(String)
    case mediaCopyFailed(cleanupIncomplete: Bool)
    case manifestWriteFailed(cleanupIncomplete: Bool)
    case destinationChanged(cleanupIncomplete: Bool)
    case destinationCommitFailed(cleanupIncomplete: Bool)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVideoType(let fileName):
            "Choose an MP4 or MOV video file to import. Unsupported file: \(fileName)"
        case .templateNotFound(let id):
            "Lesson template was not found: \(id)"
        case .mediaCopyFailed(let cleanupIncomplete):
            "The video could not be copied. Confirm it is still available and that the project drive has free space.\(cleanupWarning(cleanupIncomplete))"
        case .manifestWriteFailed(let cleanupIncomplete):
            "The imported video could not be committed to the project manifest. The prior project state was preserved.\(cleanupWarning(cleanupIncomplete))"
        case .destinationChanged(let cleanupIncomplete):
            "The import destination changed before the project could be committed. Retry the import.\(cleanupWarning(cleanupIncomplete))"
        case .destinationCommitFailed(let cleanupIncomplete):
            "The imported project could not be finalized. Check the destination folder permissions and available space.\(cleanupWarning(cleanupIncomplete))"
        }
    }

    private func cleanupWarning(_ cleanupIncomplete: Bool) -> String {
        cleanupIncomplete
            ? " Temporary import files could not be fully removed; inspect the project folder before retrying."
            : ""
    }
}

struct ProjectVideoImportOperations: Sendable {
    var fileExists: @Sendable (URL) -> Bool
    var createDirectory: @Sendable (URL, Bool) throws -> Void
    var copyItem: @Sendable (URL, URL) throws -> Void
    var moveItem: @Sendable (URL, URL) throws -> Void
    var removeItem: @Sendable (URL) throws -> Void
    var writeManifest: @Sendable (ProjectManifest, URL) throws -> Void

    static let live = ProjectVideoImportOperations(
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        createDirectory: { url, withIntermediateDirectories in
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: withIntermediateDirectories
            )
        },
        copyItem: { try FileManager.default.copyItem(at: $0, to: $1) },
        moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
        removeItem: { try FileManager.default.removeItem(at: $0) },
        writeManifest: { try ProjectBundle.writeManifest($0, to: $1) }
    )
}

public enum ProjectVideoImportService {
    public static let supportedVideoExtensions: Set<String> = ["mp4", "mov"]

    public static func importVideo(_ request: ProjectVideoImportRequest) throws -> ProjectVideoImportResult {
        try importVideo(request, operations: .live)
    }

    static func importVideo(
        _ request: ProjectVideoImportRequest,
        operations: ProjectVideoImportOperations
    ) throws -> ProjectVideoImportResult {
        let sourceURL = request.sourceURL
        let sourceExtension = sourceURL.pathExtension.lowercased()
        guard supportedVideoExtensions.contains(sourceExtension) else {
            throw ProjectVideoImportError.unsupportedVideoType(sourceURL.lastPathComponent)
        }

        let shouldAttachToCurrentProject = request.existingProjectURL != nil && request.existingManifest?.media.screen == nil
        if shouldAttachToCurrentProject,
           let existingProjectURL = request.existingProjectURL,
           let existingManifest = request.existingManifest {
            return try attachVideo(
                sourceURL: sourceURL,
                sourceExtension: sourceExtension,
                projectURL: existingProjectURL,
                manifest: existingManifest,
                operations: operations
            )
        }

        guard let template = LessonTemplateLibrary.template(id: request.defaultTemplateID)
            ?? LessonTemplateLibrary.defaultTemplates.first else {
            throw ProjectVideoImportError.templateNotFound(request.defaultTemplateID)
        }
        return try importNewProject(
            sourceURL: sourceURL,
            sourceExtension: sourceExtension,
            defaultDirectory: expandedURL(request.defaultProjectDirectory),
            template: template,
            operations: operations
        )
    }

    private static func importNewProject(
        sourceURL: URL,
        sourceExtension: String,
        defaultDirectory: URL,
        template: LessonTemplate,
        operations: ProjectVideoImportOperations
    ) throws -> ProjectVideoImportResult {
        do {
            try operations.createDirectory(defaultDirectory, true)
        } catch {
            throw ProjectVideoImportError.destinationCommitFailed(cleanupIncomplete: false)
        }

        let destinationProjectURL = makeImportedVideoProjectURL(
            for: sourceURL,
            in: defaultDirectory,
            operations: operations
        )
        let stagingProjectURL = defaultDirectory.appendingPathComponent(
            ".dm-lessonmeld-import-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        do {
            try operations.createDirectory(stagingProjectURL, false)
        } catch {
            throw ProjectVideoImportError.destinationCommitFailed(cleanupIncomplete: false)
        }

        let mediaFileName = uniqueScreenMediaFileName(
            fileExtension: sourceExtension,
            in: stagingProjectURL,
            operations: operations
        )
        let stagedMediaURL = stagingProjectURL.appendingPathComponent(mediaFileName)
        do {
            try operations.copyItem(sourceURL, stagedMediaURL)
        } catch {
            throw ProjectVideoImportError.mediaCopyFailed(
                cleanupIncomplete: cleanupCreatedArtifacts([stagingProjectURL], operations: operations)
            )
        }

        let manifest = importedManifest(
            template.seedManifest(lessonTitle: lessonTitle(fromImportedVideo: sourceURL)),
            sourceURL: sourceURL,
            mediaURL: stagedMediaURL,
            projectURL: stagingProjectURL,
            sourceExtension: sourceExtension
        )
        do {
            try operations.writeManifest(manifest, stagingProjectURL)
            try validateStagedProject(at: stagingProjectURL)
        } catch {
            throw ProjectVideoImportError.manifestWriteFailed(
                cleanupIncomplete: cleanupCreatedArtifacts([stagingProjectURL], operations: operations)
            )
        }

        do {
            try operations.moveItem(stagingProjectURL, destinationProjectURL)
        } catch {
            let cleanupIncomplete = cleanupCreatedArtifacts([stagingProjectURL], operations: operations)
            if operations.fileExists(destinationProjectURL) {
                throw ProjectVideoImportError.destinationChanged(cleanupIncomplete: cleanupIncomplete)
            }
            throw ProjectVideoImportError.destinationCommitFailed(cleanupIncomplete: cleanupIncomplete)
        }

        return ProjectVideoImportResult(projectURL: destinationProjectURL, manifest: manifest)
    }

    private static func attachVideo(
        sourceURL: URL,
        sourceExtension: String,
        projectURL: URL,
        manifest: ProjectManifest,
        operations: ProjectVideoImportOperations
    ) throws -> ProjectVideoImportResult {
        let createdProjectDirectory = !operations.fileExists(projectURL)
        do {
            try operations.createDirectory(projectURL, true)
        } catch {
            throw ProjectVideoImportError.destinationCommitFailed(cleanupIncomplete: false)
        }

        let mediaFileName = uniqueScreenMediaFileName(
            fileExtension: sourceExtension,
            in: projectURL,
            operations: operations
        )
        let destinationMediaURL = projectURL.appendingPathComponent(mediaFileName)
        let stagingDirectoryURL = projectURL.appendingPathComponent(
            ".dm-lessonmeld-import-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        let directoryCleanup = createdProjectDirectory ? [projectURL] : []
        do {
            try operations.createDirectory(stagingDirectoryURL, false)
        } catch {
            throw ProjectVideoImportError.destinationCommitFailed(cleanupIncomplete: false)
        }
        let temporaryMediaURL = stagingDirectoryURL.appendingPathComponent(mediaFileName)

        do {
            try operations.copyItem(sourceURL, temporaryMediaURL)
        } catch {
            throw ProjectVideoImportError.mediaCopyFailed(
                cleanupIncomplete: cleanupCreatedArtifacts(
                    [stagingDirectoryURL] + directoryCleanup,
                    operations: operations
                )
            )
        }

        do {
            try operations.moveItem(temporaryMediaURL, destinationMediaURL)
        } catch {
            let destinationChanged = operations.fileExists(destinationMediaURL)
            let cleanupIncomplete = cleanupCreatedArtifacts(
                [stagingDirectoryURL] + (destinationChanged ? [] : directoryCleanup),
                operations: operations
            )
            if destinationChanged {
                throw ProjectVideoImportError.destinationChanged(cleanupIncomplete: cleanupIncomplete)
            }
            throw ProjectVideoImportError.destinationCommitFailed(cleanupIncomplete: cleanupIncomplete)
        }

        do {
            try operations.removeItem(stagingDirectoryURL)
        } catch {
            throw ProjectVideoImportError.destinationCommitFailed(
                cleanupIncomplete: cleanupCreatedArtifacts(
                    [destinationMediaURL, stagingDirectoryURL] + directoryCleanup,
                    operations: operations
                )
            )
        }

        let nextManifest = importedManifest(
            manifest,
            sourceURL: sourceURL,
            mediaURL: destinationMediaURL,
            projectURL: projectURL,
            sourceExtension: sourceExtension
        )
        do {
            try operations.writeManifest(nextManifest, projectURL)
        } catch {
            throw ProjectVideoImportError.manifestWriteFailed(
                cleanupIncomplete: cleanupCreatedArtifacts(
                    [destinationMediaURL] + directoryCleanup,
                    operations: operations
                )
            )
        }

        return ProjectVideoImportResult(projectURL: projectURL, manifest: nextManifest)
    }

    private static func importedManifest(
        _ manifest: ProjectManifest,
        sourceURL: URL,
        mediaURL: URL,
        projectURL: URL,
        sourceExtension: String
    ) -> ProjectManifest {
        var nextManifest = manifest

        nextManifest.media.screen = projectFile(
            for: mediaURL,
            role: .screenVideo,
            projectURL: projectURL,
            mimeType: videoMimeType(for: sourceExtension)
        )
        if !nextManifest.tracks.contains(where: { $0.id == "screen" || $0.kind == .screen }) {
            nextManifest.tracks.append(TimelineTrack(id: "screen", kind: .screen, displayName: "Screen"))
        }
        if nextManifest.metadata.lessonTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || nextManifest.metadata.lessonTitle == "Untitled Lesson" {
            nextManifest.metadata.lessonTitle = lessonTitle(fromImportedVideo: sourceURL)
        }
        if !nextManifest.exportPresets.contains("learnhouse-1080p") {
            nextManifest.exportPresets.append("learnhouse-1080p")
        }
        nextManifest.updatedAt = Date()
        return nextManifest
    }

    private static func expandedURL(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    private static func makeImportedVideoProjectURL(
        for sourceURL: URL,
        in root: URL,
        operations: ProjectVideoImportOperations
    ) -> URL {
        let baseName = fileSlug(lessonTitle(fromImportedVideo: sourceURL))
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let projectURL = root.appendingPathComponent("\(baseName)\(suffix).dmlm", isDirectory: true)
            if !operations.fileExists(projectURL) {
                return projectURL
            }
        }
        return root.appendingPathComponent("\(baseName)-\(UUID().uuidString.lowercased()).dmlm", isDirectory: true)
    }

    private static func uniqueScreenMediaFileName(
        fileExtension: String,
        in projectURL: URL,
        operations: ProjectVideoImportOperations
    ) -> String {
        let normalizedExtension = supportedVideoExtensions.contains(fileExtension.lowercased())
            ? fileExtension.lowercased()
            : "mp4"
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let fileName = "screen\(suffix).\(normalizedExtension)"
            if !operations.fileExists(projectURL.appendingPathComponent(fileName)) {
                return fileName
            }
        }
        return "screen-\(UUID().uuidString.lowercased()).\(normalizedExtension)"
    }

    private static func validateStagedProject(at projectURL: URL) throws {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let errors = ProjectBundle.validate(manifest: manifest, projectURL: projectURL)
            .filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw ProjectVideoImportError.manifestWriteFailed(cleanupIncomplete: false)
        }
    }

    private static func cleanupCreatedArtifacts(
        _ urls: [URL],
        operations: ProjectVideoImportOperations
    ) -> Bool {
        var cleanupIncomplete = false
        for url in urls where operations.fileExists(url) {
            do {
                try operations.removeItem(url)
            } catch {
                cleanupIncomplete = true
            }
        }
        return cleanupIncomplete
    }

    private static func projectFile(
        for url: URL,
        role: ProjectFileRole,
        projectURL: URL,
        mimeType: String? = nil
    ) -> ProjectFile {
        let projectPath = projectURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let relativePath: String
        if filePath.hasPrefix(projectPath + "/") {
            relativePath = String(filePath.dropFirst(projectPath.count + 1))
        } else {
            relativePath = filePath
        }
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? NSNumber)?.int64Value
        return ProjectFile(relativePath: relativePath, role: role, mimeType: mimeType, byteCount: byteCount)
    }

    private static func videoMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "mov": "video/quicktime"
        default: "video/mp4"
        }
    }

    private static func lessonTitle(fromImportedVideo url: URL) -> String {
        let title = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Imported Video" : title
    }

    private static func fileSlug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "lesson" : collapsed
    }
}
