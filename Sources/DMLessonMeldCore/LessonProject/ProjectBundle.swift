import Foundation

public enum ProjectBundleError: Error, LocalizedError {
    case manifestNotFound(URL)
    case invalidBundle(URL)

    public var errorDescription: String? {
        switch self {
        case .manifestNotFound(let url):
            "No project.json found at \(url.path)."
        case .invalidBundle(let url):
            "Project path is not a directory: \(url.path)."
        }
    }
}

public struct ProjectValidationIssue: Codable, Equatable, Sendable {
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

public struct ProjectBundleSummary: Codable, Equatable, Sendable {
    public var urlPath: String
    public var lessonTitle: String
    public var schemaVersion: Int
    public var fileCount: Int
    public var markerCount: Int
    public var issues: [ProjectValidationIssue]

    public init(
        urlPath: String,
        lessonTitle: String,
        schemaVersion: Int,
        fileCount: Int,
        markerCount: Int,
        issues: [ProjectValidationIssue]
    ) {
        self.urlPath = urlPath
        self.lessonTitle = lessonTitle
        self.schemaVersion = schemaVersion
        self.fileCount = fileCount
        self.markerCount = markerCount
        self.issues = issues
    }
}

public struct ProjectBundleRepairResult: Codable, Equatable, Sendable {
    public var projectURLPath: String
    public var wroteManifest: Bool
    public var manifest: ProjectManifest
    public var recoveredFiles: [ProjectFile]
    public var issues: [ProjectValidationIssue]

    public init(
        projectURLPath: String,
        wroteManifest: Bool,
        manifest: ProjectManifest,
        recoveredFiles: [ProjectFile],
        issues: [ProjectValidationIssue]
    ) {
        self.projectURLPath = projectURLPath
        self.wroteManifest = wroteManifest
        self.manifest = manifest
        self.recoveredFiles = recoveredFiles
        self.issues = issues
    }
}

public enum ProjectBundle {
    public static let manifestFileName = "project.json"

    public static func manifestURL(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(manifestFileName)
    }

    public static func loadManifest(at projectURL: URL) throws -> ProjectManifest {
        let manifestURL = manifestURL(in: projectURL)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ProjectBundleError.manifestNotFound(manifestURL)
        }

        let data = try Data(contentsOf: manifestURL)
        return try DMLessonJSON.decoder().decode(ProjectManifest.self, from: data)
    }

    public static func writeManifest(_ manifest: ProjectManifest, to projectURL: URL) throws {
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let data = try DMLessonJSON.encoder().encode(manifest)
        try data.write(to: manifestURL(in: projectURL), options: [.atomic])
    }

    public static func fileURL(for file: ProjectFile, in projectURL: URL) -> URL {
        let path = NSString(string: file.relativePath).expandingTildeInPath
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return projectURL.appendingPathComponent(file.relativePath)
    }

    public static func updateManifest(at projectURL: URL, _ update: (inout ProjectManifest) throws -> Void) throws -> ProjectManifest {
        var manifest = try loadManifest(at: projectURL)
        try update(&manifest)
        manifest.updatedAt = Date()
        try writeManifest(manifest, to: projectURL)
        return manifest
    }

    public static func inspect(at projectURL: URL) throws -> ProjectBundleSummary {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectBundleError.invalidBundle(projectURL)
        }

        let manifest = try loadManifest(at: projectURL)
        let issues = validate(manifest: manifest, projectURL: projectURL)

        return ProjectBundleSummary(
            urlPath: projectURL.path,
            lessonTitle: manifest.metadata.lessonTitle,
            schemaVersion: manifest.schemaVersion,
            fileCount: manifest.media.allFiles.count,
            markerCount: manifest.markers.count,
            issues: issues
        )
    }

    public static func repair(at projectURL: URL, lessonTitle: String? = nil) throws -> ProjectBundleRepairResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectBundleError.invalidBundle(projectURL)
        }

        if FileManager.default.fileExists(atPath: manifestURL(in: projectURL).path) {
            var manifest = try loadManifest(at: projectURL)
            let recoveredFiles = recoverableFiles(in: projectURL)
            let recoveredMedia = recoveredMedia(from: recoveredFiles)
            let didUpdate = mergeRecoveredMedia(recoveredMedia, into: &manifest)
            if didUpdate {
                try writeManifest(manifest, to: projectURL)
            }
            return ProjectBundleRepairResult(
                projectURLPath: projectURL.path,
                wroteManifest: didUpdate,
                manifest: manifest,
                recoveredFiles: recoveredFiles,
                issues: validate(manifest: manifest, projectURL: projectURL)
            )
        }

        let recoveredFiles = recoverableFiles(in: projectURL)
        let media = recoveredMedia(from: recoveredFiles)
        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: recoveredLessonTitle(projectURL: projectURL, override: lessonTitle)),
            media: media,
            tracks: recoveredTracks(from: media),
            exportPresets: ["learnhouse-1080p"]
        )
        try writeManifest(manifest, to: projectURL)

        return ProjectBundleRepairResult(
            projectURLPath: projectURL.path,
            wroteManifest: true,
            manifest: manifest,
            recoveredFiles: recoveredFiles,
            issues: validate(manifest: manifest, projectURL: projectURL)
        )
    }

    public static func validate(manifest: ProjectManifest, projectURL: URL) -> [ProjectValidationIssue] {
        var issues: [ProjectValidationIssue] = []

        if manifest.schemaVersion > ProjectManifest.currentSchemaVersion {
            issues.append(ProjectValidationIssue(
                severity: .warning,
                message: "Project schema is newer than this build supports."
            ))
        }

        if manifest.metadata.lessonTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ProjectValidationIssue(severity: .error, message: "Lesson title is required."))
        }

        for file in manifest.media.allFiles {
            let url = fileURL(for: file, in: projectURL)
            if !FileManager.default.fileExists(atPath: url.path) {
                issues.append(ProjectValidationIssue(
                    severity: .warning,
                    message: "Referenced file is missing.",
                    path: file.relativePath
                ))
            }
        }

        return issues
    }

    private static func recoverableFiles(in projectURL: URL) -> [ProjectFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [ProjectFile] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent != manifestFileName,
                  let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let role = recoveredRole(for: url, projectURL: projectURL) else {
                continue
            }
            files.append(ProjectFile(
                relativePath: relativePath(for: url, projectURL: projectURL),
                role: role,
                mimeType: mimeType(for: url),
                byteCount: byteCount(for: url)
            ))
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func recoveredRole(for url: URL, projectURL: URL) -> ProjectFileRole? {
        let fileName = url.deletingPathExtension().lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        let relativePath = relativePath(for: url, projectURL: projectURL).lowercased()

        if fileName.contains("screen") && ["mp4", "mov"].contains(ext) {
            return .screenVideo
        }
        if fileName.contains("webcam") && ["mp4", "mov"].contains(ext) {
            return .webcamVideo
        }
        if (fileName.contains("microphone") || fileName == "mic" || fileName.contains("mic-audio")) && ["m4a", "caf", "wav"].contains(ext) {
            return .microphoneAudio
        }
        if fileName.contains("system") && ["m4a", "caf", "wav"].contains(ext) {
            return .systemAudio
        }
        if relativePath.contains("cursor") && ext == "json" {
            return .cursorMetadata
        }
        if relativePath.contains("annotation") && ext == "json" {
            return .annotations
        }
        if relativePath.contains("caption") && ["json", "vtt", "srt"].contains(ext) {
            return .captions
        }
        if relativePath.contains("transcript") && ["json", "md", "txt"].contains(ext) {
            return .transcript
        }
        if fileName.contains("thumbnail") && ["png", "jpg", "jpeg"].contains(ext) {
            return .thumbnail
        }

        return nil
    }

    private static func recoveredMedia(from files: [ProjectFile]) -> ProjectMedia {
        ProjectMedia(
            screen: files.first { $0.role == .screenVideo },
            webcam: files.first { $0.role == .webcamVideo },
            microphoneAudio: files.first { $0.role == .microphoneAudio },
            systemAudio: files.first { $0.role == .systemAudio },
            cursorMetadata: files.first { $0.role == .cursorMetadata },
            annotations: files.first { $0.role == .annotations },
            captions: files.filter { $0.role == .captions },
            transcripts: files.filter { $0.role == .transcript },
            thumbnail: files.first { $0.role == .thumbnail },
            attachments: []
        )
    }

    @discardableResult
    private static func mergeRecoveredMedia(_ recovered: ProjectMedia, into manifest: inout ProjectManifest) -> Bool {
        var didUpdate = false

        func assignIfMissing(_ keyPath: WritableKeyPath<ProjectMedia, ProjectFile?>, _ value: ProjectFile?) {
            guard manifest.media[keyPath: keyPath] == nil, let value else { return }
            manifest.media[keyPath: keyPath] = value
            didUpdate = true
        }

        assignIfMissing(\.screen, recovered.screen)
        assignIfMissing(\.webcam, recovered.webcam)
        assignIfMissing(\.microphoneAudio, recovered.microphoneAudio)
        assignIfMissing(\.systemAudio, recovered.systemAudio)
        assignIfMissing(\.cursorMetadata, recovered.cursorMetadata)
        assignIfMissing(\.annotations, recovered.annotations)
        assignIfMissing(\.thumbnail, recovered.thumbnail)

        for caption in recovered.captions where !manifest.media.captions.contains(where: { $0.relativePath == caption.relativePath }) {
            manifest.media.captions.append(caption)
            didUpdate = true
        }
        for transcript in recovered.transcripts where !manifest.media.transcripts.contains(where: { $0.relativePath == transcript.relativePath }) {
            manifest.media.transcripts.append(transcript)
            didUpdate = true
        }

        for track in recoveredTracks(from: manifest.media) where !manifest.tracks.contains(where: { $0.id == track.id }) {
            manifest.tracks.append(track)
            didUpdate = true
        }

        if didUpdate {
            manifest.updatedAt = Date()
            if !manifest.exportPresets.contains("learnhouse-1080p") {
                manifest.exportPresets.append("learnhouse-1080p")
            }
        }
        return didUpdate
    }

    private static func recoveredTracks(from media: ProjectMedia) -> [TimelineTrack] {
        var tracks: [TimelineTrack] = []
        if media.screen != nil {
            tracks.append(TimelineTrack(id: "screen", kind: .screen, displayName: "Screen"))
        }
        if media.webcam != nil {
            tracks.append(TimelineTrack(id: "webcam", kind: .webcam, displayName: "Webcam"))
        }
        if media.microphoneAudio != nil {
            tracks.append(TimelineTrack(id: "microphone", kind: .microphone, displayName: "Microphone"))
        }
        if media.systemAudio != nil {
            tracks.append(TimelineTrack(id: "system-audio", kind: .systemAudio, displayName: "System Audio"))
        }
        if media.cursorMetadata != nil {
            tracks.append(TimelineTrack(id: "cursor", kind: .cursor, displayName: "Cursor and Input"))
        }
        if media.annotations != nil {
            tracks.append(TimelineTrack(id: "annotations", kind: .annotations, displayName: "Annotations"))
        }
        if !media.captions.isEmpty || !media.transcripts.isEmpty {
            tracks.append(TimelineTrack(id: "captions", kind: .captions, displayName: "Captions"))
        }
        return tracks
    }

    private static func recoveredLessonTitle(projectURL: URL, override: String?) -> String {
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        let title = projectURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Recovered Lesson" : title
    }

    private static func relativePath(for url: URL, projectURL: URL) -> String {
        let projectPath = projectURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(projectPath + "/") else {
            return filePath
        }
        return String(filePath.dropFirst(projectPath.count + 1))
    }

    private static func byteCount(for url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    private static func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mp4": "video/mp4"
        case "mov": "video/quicktime"
        case "m4a": "audio/mp4"
        case "caf": "audio/x-caf"
        case "wav": "audio/wav"
        case "json": "application/json"
        case "vtt": "text/vtt"
        case "srt": "application/x-subrip"
        case "md": "text/markdown"
        case "txt": "text/plain"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        default: nil
        }
    }
}
