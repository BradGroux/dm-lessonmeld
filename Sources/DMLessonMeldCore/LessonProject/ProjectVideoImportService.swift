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

    public var errorDescription: String? {
        switch self {
        case .unsupportedVideoType(let fileName):
            "Choose an MP4 or MOV video file to import. Unsupported file: \(fileName)"
        case .templateNotFound(let id):
            "Lesson template was not found: \(id)"
        }
    }
}

public enum ProjectVideoImportService {
    public static let supportedVideoExtensions: Set<String> = ["mp4", "mov"]

    public static func importVideo(_ request: ProjectVideoImportRequest) throws -> ProjectVideoImportResult {
        let sourceURL = request.sourceURL
        let sourceExtension = sourceURL.pathExtension.lowercased()
        guard supportedVideoExtensions.contains(sourceExtension) else {
            throw ProjectVideoImportError.unsupportedVideoType(sourceURL.lastPathComponent)
        }

        let shouldAttachToCurrentProject = request.existingProjectURL != nil && request.existingManifest?.media.screen == nil
        let destinationProjectURL: URL
        var nextManifest: ProjectManifest

        if shouldAttachToCurrentProject,
           let existingProjectURL = request.existingProjectURL,
           let existingManifest = request.existingManifest {
            destinationProjectURL = existingProjectURL
            nextManifest = existingManifest
            try FileManager.default.createDirectory(at: destinationProjectURL, withIntermediateDirectories: true)
        } else {
            let defaultDirectory = expandedURL(request.defaultProjectDirectory)
            try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
            destinationProjectURL = try makeImportedVideoProjectURL(for: sourceURL, in: defaultDirectory)

            guard let template = LessonTemplateLibrary.template(id: request.defaultTemplateID)
                ?? LessonTemplateLibrary.defaultTemplates.first else {
                throw ProjectVideoImportError.templateNotFound(request.defaultTemplateID)
            }
            nextManifest = template.seedManifest(lessonTitle: lessonTitle(fromImportedVideo: sourceURL))
            try FileManager.default.createDirectory(at: destinationProjectURL, withIntermediateDirectories: true)
        }

        let mediaFileName = uniqueScreenMediaFileName(fileExtension: sourceExtension, in: destinationProjectURL)
        let destinationMediaURL = destinationProjectURL.appendingPathComponent(mediaFileName)
        let sourcePath = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
        let destinationPath = destinationMediaURL.resolvingSymlinksInPath().standardizedFileURL.path
        if sourcePath != destinationPath {
            try FileManager.default.copyItem(at: sourceURL, to: destinationMediaURL)
        }

        nextManifest.media.screen = projectFile(
            for: destinationMediaURL,
            role: .screenVideo,
            projectURL: destinationProjectURL,
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

        try ProjectBundle.writeManifest(nextManifest, to: destinationProjectURL)
        return ProjectVideoImportResult(projectURL: destinationProjectURL, manifest: nextManifest)
    }

    private static func expandedURL(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    private static func makeImportedVideoProjectURL(for sourceURL: URL, in root: URL) throws -> URL {
        let baseName = fileSlug(lessonTitle(fromImportedVideo: sourceURL))
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let projectURL = root.appendingPathComponent("\(baseName)\(suffix).dmlm", isDirectory: true)
            if !FileManager.default.fileExists(atPath: projectURL.path) {
                return projectURL
            }
        }
        return root.appendingPathComponent("\(baseName)-\(UUID().uuidString.lowercased()).dmlm", isDirectory: true)
    }

    private static func uniqueScreenMediaFileName(fileExtension: String, in projectURL: URL) -> String {
        let normalizedExtension = supportedVideoExtensions.contains(fileExtension.lowercased())
            ? fileExtension.lowercased()
            : "mp4"
        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
            let fileName = "screen\(suffix).\(normalizedExtension)"
            if !FileManager.default.fileExists(atPath: projectURL.appendingPathComponent(fileName).path) {
                return fileName
            }
        }
        return "screen-\(UUID().uuidString.lowercased()).\(normalizedExtension)"
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
