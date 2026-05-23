import Foundation

public struct LearnHousePackageManifest: Codable, Equatable, Sendable {
    public var schema: String
    public var schemaVersion: Int
    public var generatedAt: Date
    public var generator: LearnHousePackageGenerator
    public var course: LearnHouseCourseMetadata
    public var lesson: LearnHouseLessonMetadata
    public var artifacts: LearnHouseArtifacts
    public var learnHouse: LearnHouseImportMetadata
    public var chapters: [LearnHouseChapter]
    public var checksumPath: String?
    public var sourceProject: String
    public var files: [LearnHousePackageFile]
    public var notes: [String]

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case generator
        case course
        case lesson
        case artifacts
        case learnHouse = "learn_house"
        case chapters
        case checksumPath = "checksum_path"
        case sourceProject = "source_project"
        case files
        case notes
    }

    public init(
        schema: String = "io.digitalmeld.dm-lessonmeld.learnhouse-package",
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        generator: LearnHousePackageGenerator = LearnHousePackageGenerator(),
        course: LearnHouseCourseMetadata,
        lesson: LearnHouseLessonMetadata,
        artifacts: LearnHouseArtifacts,
        learnHouse: LearnHouseImportMetadata,
        chapters: [LearnHouseChapter],
        checksumPath: String?,
        sourceProject: String,
        files: [LearnHousePackageFile],
        notes: [String] = []
    ) {
        self.schema = schema
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.generator = generator
        self.course = course
        self.lesson = lesson
        self.artifacts = artifacts
        self.learnHouse = learnHouse
        self.chapters = chapters
        self.checksumPath = checksumPath
        self.sourceProject = sourceProject
        self.files = files
        self.notes = notes
    }
}

public struct LearnHousePackageGenerator: Codable, Equatable, Sendable {
    public var name: String
    public var version: String

    public init(name: String = "dm-lessonmeld", version: String = "0.0.1") {
        self.name = name
        self.version = version
    }
}

public struct LearnHouseCourseMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var description: String?
    public var instructor: String?
    public var tags: [String]
    public var license: String?
    public var language: String

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case instructor
        case tags
        case license
        case language
    }

    public init(
        title: String,
        description: String? = nil,
        instructor: String? = nil,
        tags: [String] = [],
        license: String? = nil,
        language: String = "en"
    ) {
        self.title = title
        self.description = description
        self.instructor = instructor
        self.tags = tags
        self.license = license
        self.language = language
    }
}

public struct LearnHouseLessonMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var description: String?
    public var durationSeconds: Double?
    public var chapter: String?
    public var learningObjectives: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case durationSeconds = "duration_seconds"
        case chapter
        case learningObjectives = "learning_objectives"
    }

    public init(
        title: String,
        description: String? = nil,
        durationSeconds: Double? = nil,
        chapter: String? = nil,
        learningObjectives: [String] = []
    ) {
        self.title = title
        self.description = description
        self.durationSeconds = durationSeconds
        self.chapter = chapter
        self.learningObjectives = learningObjectives
    }
}

public struct LearnHouseArtifacts: Codable, Equatable, Sendable {
    public var video: LearnHouseArtifact?
    public var thumbnail: LearnHouseArtifact?
    public var captions: [LearnHouseArtifact]
    public var transcripts: [LearnHouseArtifact]

    enum CodingKeys: String, CodingKey {
        case video
        case thumbnail
        case captions
        case transcripts
    }

    public init(
        video: LearnHouseArtifact?,
        thumbnail: LearnHouseArtifact?,
        captions: [LearnHouseArtifact] = [],
        transcripts: [LearnHouseArtifact] = []
    ) {
        self.video = video
        self.thumbnail = thumbnail
        self.captions = captions
        self.transcripts = transcripts
    }
}

public struct LearnHouseArtifact: Codable, Equatable, Sendable {
    public var path: String
    public var mimeType: String?
    public var format: String?
    public var language: String?

    enum CodingKeys: String, CodingKey {
        case path
        case mimeType = "mime_type"
        case format
        case language
    }

    public init(path: String, mimeType: String? = nil, format: String? = nil, language: String? = nil) {
        self.path = path
        self.mimeType = mimeType
        self.format = format
        self.language = language
    }
}

public struct LearnHouseImportMetadata: Codable, Equatable, Sendable {
    public var packageFormat: String
    public var importMode: String
    public var courseUUID: String
    public var defaultActivityType: String
    public var defaultActivitySubType: String
    public var publishDefault: Bool

    enum CodingKeys: String, CodingKey {
        case packageFormat = "package_format"
        case importMode = "import_mode"
        case courseUUID = "course_uuid"
        case defaultActivityType = "default_activity_type"
        case defaultActivitySubType = "default_activity_subtype"
        case publishDefault = "publish_default"
    }

    public init(
        packageFormat: String = "learnhouse-course-export",
        importMode: String = "zip",
        courseUUID: String,
        defaultActivityType: String = "TYPE_VIDEO",
        defaultActivitySubType: String = "SUBTYPE_VIDEO_HOSTED",
        publishDefault: Bool = false
    ) {
        self.packageFormat = packageFormat
        self.importMode = importMode
        self.courseUUID = courseUUID
        self.defaultActivityType = defaultActivityType
        self.defaultActivitySubType = defaultActivitySubType
        self.publishDefault = publishDefault
    }
}

public struct LearnHouseChapter: Codable, Equatable, Sendable {
    public var title: String
    public var description: String?
    public var order: Int
    public var activities: [LearnHouseActivity]

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case order
        case activities
    }

    public init(title: String, description: String? = nil, order: Int, activities: [LearnHouseActivity]) {
        self.title = title
        self.description = description
        self.order = order
        self.activities = activities
    }
}

public struct LearnHouseActivity: Codable, Equatable, Sendable {
    public var title: String
    public var type: String
    public var sourceArtifact: String
    public var order: Int
    public var details: LearnHouseActivityDetails

    enum CodingKeys: String, CodingKey {
        case title
        case type
        case sourceArtifact = "source_artifact"
        case order
        case details
    }

    public init(
        title: String,
        type: String = "video",
        sourceArtifact: String = "video",
        order: Int,
        details: LearnHouseActivityDetails = LearnHouseActivityDetails()
    ) {
        self.title = title
        self.type = type
        self.sourceArtifact = sourceArtifact
        self.order = order
        self.details = details
    }
}

public struct LearnHouseActivityDetails: Codable, Equatable, Sendable {
    public var startTime: Double
    public var endTime: Double?
    public var autoplay: Bool
    public var muted: Bool

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case autoplay
        case muted
    }

    public init(startTime: Double = 0, endTime: Double? = nil, autoplay: Bool = false, muted: Bool = false) {
        self.startTime = startTime
        self.endTime = endTime
        self.autoplay = autoplay
        self.muted = muted
    }
}

public struct LearnHousePackageFile: Codable, Equatable, Sendable {
    public var role: ProjectFileRole
    public var relativePath: String
    public var sha256: String?
    public var byteCount: Int64?

    enum CodingKeys: String, CodingKey {
        case role
        case relativePath = "relative_path"
        case sha256
        case byteCount = "byte_count"
    }

    public init(role: ProjectFileRole, relativePath: String, sha256: String? = nil, byteCount: Int64? = nil) {
        self.role = role
        self.relativePath = relativePath
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public struct LearnHousePackageResult: Codable, Equatable, Sendable {
    public var packagePath: String
    public var archivePath: String?
    public var manifest: LearnHousePackageManifest

    enum CodingKeys: String, CodingKey {
        case packagePath = "package_path"
        case archivePath = "archive_path"
        case manifest
    }

    public init(packagePath: String, archivePath: String? = nil, manifest: LearnHousePackageManifest) {
        self.packagePath = packagePath
        self.archivePath = archivePath
        self.manifest = manifest
    }
}

public enum LearnHousePackageError: Error, LocalizedError {
    case missingPrimaryVideo
    case missingArchiveTool(String)
    case archiveSourceNotDirectory(String)
    case archiveFailed(status: Int32, output: String)
    case unsafeDestination(String)
    case unsafeSource(String)

    public var errorDescription: String? {
        switch self {
        case .missingPrimaryVideo:
            "LearnHouse packages require a primary screen video in the project manifest."
        case .missingArchiveTool(let path):
            "LearnHouse archive creation requires the built-in ditto tool at \(path)."
        case .archiveSourceNotDirectory(let path):
            "LearnHouse archive source is not a directory: \(path)."
        case .archiveFailed(let status, let output):
            "LearnHouse archive creation failed with status \(status): \(output)"
        case .unsafeDestination(let path):
            "LearnHouse package destination is not safe: \(path)"
        case .unsafeSource(let path):
            "LearnHouse package source is not safe: \(path)"
        }
    }
}

public struct LearnHouseArchiveBuilder {
    public var dittoPath: String

    public init(dittoPath: String = "/usr/bin/ditto") {
        self.dittoPath = dittoPath
    }

    @discardableResult
    public func buildArchive(packageDirectory: URL, archiveURL requestedArchiveURL: URL? = nil) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: packageDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LearnHousePackageError.archiveSourceNotDirectory(packageDirectory.path)
        }
        guard FileManager.default.isExecutableFile(atPath: dittoPath) else {
            throw LearnHousePackageError.missingArchiveTool(dittoPath)
        }

        let archiveURL = requestedArchiveURL ?? packageDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("\(packageDirectory.lastPathComponent).zip")
        try FileManager.default.createDirectory(
            at: archiveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: dittoPath)
        process.currentDirectoryURL = packageDirectory.deletingLastPathComponent()
        process.arguments = [
            "-c",
            "-k",
            "--keepParent",
            packageDirectory.lastPathComponent,
            archiveURL.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw LearnHousePackageError.archiveFailed(status: process.terminationStatus, output: output)
        }

        return archiveURL
    }
}

public struct LearnHousePackageBuilder {
    public var archiveBuilder: LearnHouseArchiveBuilder

    public init(archiveBuilder: LearnHouseArchiveBuilder = LearnHouseArchiveBuilder()) {
        self.archiveBuilder = archiveBuilder
    }

    public func buildPackage(projectURL: URL, outputDirectory: URL, archive: Bool = false) throws -> LearnHousePackageResult {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        guard manifest.media.screen != nil else {
            throw LearnHousePackageError.missingPrimaryVideo
        }

        let packageName = slug(manifest.metadata.lessonTitle)
        let packageURL = outputDirectory.appendingPathComponent("\(packageName).learnhouse", isDirectory: true)
        let assetsURL = packageURL.appendingPathComponent("assets", isDirectory: true)

        try ensureSafeDirectory(packageURL, within: outputDirectory)
        try ensureSafeDirectory(assetsURL, within: packageURL)
        try writeProjectManifest(manifest, packageURL: packageURL)

        let packagedFiles = try copyPackageFiles(
            files: manifest.media.allFiles,
            projectURL: projectURL,
            assetsURL: assetsURL
        )

        let checksumPath = try writeChecksums(files: packagedFiles, packageURL: packageURL)
        let courseUUID = stableID(prefix: "course", value: manifest.metadata.courseTitle ?? manifest.metadata.lessonTitle)
        let chapterTitle = manifest.metadata.moduleTitle ?? "Lessons"
        let activityTitle = manifest.metadata.lessonTitle
        try writeLearnHouseNativeLayer(
            manifest: manifest,
            packageURL: packageURL,
            courseUUID: courseUUID,
            chapterTitle: chapterTitle,
            activityTitle: activityTitle,
            packagedFiles: packagedFiles
        )

        let packageManifest = LearnHousePackageManifest(
            course: LearnHouseCourseMetadata(
                title: manifest.metadata.courseTitle ?? manifest.metadata.lessonTitle,
                description: manifest.metadata.summary,
                instructor: manifest.metadata.instructor,
                tags: manifest.metadata.tags,
                license: manifest.metadata.license
            ),
            lesson: LearnHouseLessonMetadata(
                title: manifest.metadata.lessonTitle,
                description: manifest.metadata.summary,
                chapter: manifest.metadata.moduleTitle
            ),
            artifacts: artifacts(from: packagedFiles),
            learnHouse: LearnHouseImportMetadata(courseUUID: courseUUID),
            chapters: [
                LearnHouseChapter(
                    title: chapterTitle,
                    order: 1,
                    activities: [
                        LearnHouseActivity(title: activityTitle, order: 1)
                    ]
                )
            ],
            checksumPath: checksumPath,
            sourceProject: projectURL.lastPathComponent,
            files: packagedFiles,
            notes: [
                "Upload the primary video to LearnHouse, then attach transcript/caption sidecars where supported.",
                "This package is local-only and contains no credentials."
            ]
        )

        let data = try DMLessonJSON.encoder().encode(packageManifest)
        try data.write(
            to: packageURL.appendingPathComponent("learnhouse-package.json"),
            options: [.atomic]
        )
        try data.write(to: packageURL.appendingPathComponent("manifest.json"), options: [.atomic])

        let archiveURL = archive ? try archiveBuilder.buildArchive(packageDirectory: packageURL) : nil
        return LearnHousePackageResult(
            packagePath: packageURL.path,
            archivePath: archiveURL?.path,
            manifest: packageManifest
        )
    }

    public func buildArchive(projectURL: URL, outputDirectory: URL) throws -> LearnHousePackageResult {
        try buildPackage(projectURL: projectURL, outputDirectory: outputDirectory, archive: true)
    }

    private func writeProjectManifest(_ manifest: ProjectManifest, packageURL: URL) throws {
        let data = try DMLessonJSON.encoder().encode(manifest)
        try ensureSafeDirectory(packageURL, within: packageURL.deletingLastPathComponent())
        try data.write(to: packageURL.appendingPathComponent("project-manifest.json"), options: [.atomic])
    }

    private func copyPackageFiles(files: [ProjectFile], projectURL: URL, assetsURL: URL) throws -> [LearnHousePackageFile] {
        try files.compactMap { file in
            let sourceURL = try ProjectBundle.projectLocalFileURL(for: file, in: projectURL)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                return nil
            }

            let destinationRelativePath = "assets/\(file.relativePath)"
            let destinationURL = assetsURL.appendingPathComponent(file.relativePath)
            guard !isSymbolicLink(sourceURL) else {
                throw LearnHousePackageError.unsafeSource(sourceURL.path)
            }
            try validatePackageRelativePath(destinationRelativePath)
            try ensureSafeDirectory(destinationURL.deletingLastPathComponent(), within: assetsURL)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                guard !isSymbolicLink(destinationURL) else {
                    throw LearnHousePackageError.unsafeDestination(destinationURL.path)
                }
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            return LearnHousePackageFile(
                role: file.role,
                relativePath: destinationRelativePath,
                sha256: try sha256Hex(for: destinationURL),
                byteCount: try byteCount(for: destinationURL)
            )
        }
    }

    private func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let lowered = value.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(lowered).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "lesson-package" : collapsed
    }

    private func sha256Hex(for url: URL) throws -> String {
        try FileChecksum.sha256Hex(for: url)
    }

    private func byteCount(for url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func artifacts(from files: [LearnHousePackageFile]) -> LearnHouseArtifacts {
        let video = files.first { $0.role == .screenVideo }.map {
            LearnHouseArtifact(path: $0.relativePath, mimeType: mimeType(for: $0.relativePath), format: fileExtension(for: $0.relativePath))
        }
        let thumbnail = files.first { $0.role == .thumbnail }.map {
            LearnHouseArtifact(path: $0.relativePath, mimeType: mimeType(for: $0.relativePath), format: fileExtension(for: $0.relativePath))
        }
        let captions = files.filter { $0.role == .captions }.map {
            LearnHouseArtifact(path: $0.relativePath, mimeType: mimeType(for: $0.relativePath), format: fileExtension(for: $0.relativePath), language: "en")
        }
        let transcripts = files.filter { $0.role == .transcript }.map {
            LearnHouseArtifact(path: $0.relativePath, mimeType: mimeType(for: $0.relativePath), format: fileExtension(for: $0.relativePath), language: "en")
        }

        return LearnHouseArtifacts(video: video, thumbnail: thumbnail, captions: captions, transcripts: transcripts)
    }

    private func writeChecksums(files: [LearnHousePackageFile], packageURL: URL) throws -> String? {
        guard !files.isEmpty else { return nil }
        let lines = try files.compactMap { file -> String? in
            guard let sha256 = file.sha256 else { return nil }
            try validatePackageRelativePath(file.relativePath)
            return "\(sha256)  \(file.relativePath)"
        }.joined(separator: "\n")
        let relativePath = "assets/checksums.sha256"
        try ensureSafeDirectory(packageURL.appendingPathComponent("assets", isDirectory: true), within: packageURL)
        try "\(lines)\n".write(
            to: packageURL.appendingPathComponent(relativePath),
            atomically: true,
            encoding: .utf8
        )
        return relativePath
    }

    private func writeLearnHouseNativeLayer(
        manifest: ProjectManifest,
        packageURL: URL,
        courseUUID: String,
        chapterTitle: String,
        activityTitle: String,
        packagedFiles: [LearnHousePackageFile]
    ) throws {
        let chapterUUID = stableID(prefix: "chapter", value: chapterTitle)
        let activityUUID = stableID(prefix: "activity", value: activityTitle)
        let learnHouseRoot = packageURL.appendingPathComponent("learnhouse", isDirectory: true)
        let courseURL = learnHouseRoot.appendingPathComponent("courses/\(courseUUID)", isDirectory: true)
        let thumbnailURL = courseURL.appendingPathComponent("thumbnails", isDirectory: true)
        let chapterURL = courseURL.appendingPathComponent("chapters/\(chapterUUID)", isDirectory: true)
        let activityURL = chapterURL.appendingPathComponent("activities/\(activityUUID)", isDirectory: true)
        let videoURL = activityURL.appendingPathComponent("files/video", isDirectory: true)

        try ensureSafeDirectory(thumbnailURL, within: packageURL)
        try ensureSafeDirectory(videoURL, within: packageURL)

        let nativeManifest: [String: String] = [
            "format": "learnhouse-course-export",
            "generator": "dm-lessonmeld"
        ]
        try writeJSONObject(nativeManifest, to: learnHouseRoot.appendingPathComponent("manifest.json"))

        let courseJSON: [String: AnyCodableValue] = [
            "uuid": .string(courseUUID),
            "name": .string(manifest.metadata.courseTitle ?? manifest.metadata.lessonTitle),
            "description": .optionalString(manifest.metadata.summary),
            "chapters": .array([.string(chapterUUID)])
        ]
        try writeJSONObject(courseJSON, to: courseURL.appendingPathComponent("course.json"))

        let chapterJSON: [String: AnyCodableValue] = [
            "uuid": .string(chapterUUID),
            "name": .string(chapterTitle),
            "activities": .array([.string(activityUUID)])
        ]
        try FileManager.default.createDirectory(at: chapterURL, withIntermediateDirectories: true)
        try writeJSONObject(chapterJSON, to: chapterURL.appendingPathComponent("chapter.json"))

        let activityJSON: [String: AnyCodableValue] = [
            "uuid": .string(activityUUID),
            "name": .string(activityTitle),
            "type": .string("TYPE_VIDEO"),
            "subtype": .string("SUBTYPE_VIDEO_HOSTED"),
            "details": .dictionary([
                "autoplay": .bool(false),
                "muted": .bool(false)
            ])
        ]
        try writeJSONObject(activityJSON, to: activityURL.appendingPathComponent("activity.json"))

        if let video = packagedFiles.first(where: { $0.role == .screenVideo }) {
            let source = packageURL.appendingPathComponent(video.relativePath)
            let destination = videoURL.appendingPathComponent(source.lastPathComponent)
            try ensureSafeDirectory(destination.deletingLastPathComponent(), within: packageURL)
            if FileManager.default.fileExists(atPath: destination.path) {
                guard !isSymbolicLink(destination) else {
                    throw LearnHousePackageError.unsafeDestination(destination.path)
                }
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }

        if let thumbnail = packagedFiles.first(where: { $0.role == .thumbnail }) {
            let source = packageURL.appendingPathComponent(thumbnail.relativePath)
            let destination = thumbnailURL.appendingPathComponent(source.lastPathComponent)
            try ensureSafeDirectory(destination.deletingLastPathComponent(), within: packageURL)
            if FileManager.default.fileExists(atPath: destination.path) {
                guard !isSymbolicLink(destination) else {
                    throw LearnHousePackageError.unsafeDestination(destination.path)
                }
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func writeJSONObject<T: Encodable>(_ object: T, to url: URL) throws {
        let data = try DMLessonJSON.encoder().encode(object)
        try ensureSafeDirectory(url.deletingLastPathComponent(), within: url.deletingLastPathComponent().deletingLastPathComponent())
        try data.write(to: url, options: [.atomic])
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func validatePackageRelativePath(_ path: String) throws {
        guard !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw LearnHousePackageError.unsafeSource(path)
        }
    }

    private func ensureSafeDirectory(_ directoryURL: URL, within rootURL: URL) throws {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var current = root
        let rootPath = root.standardizedFileURL.path
        let targetPath = directoryURL.standardizedFileURL.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            throw LearnHousePackageError.unsafeDestination(directoryURL.path)
        }
        let relativePath = targetPath == rootPath ? "" : String(targetPath.dropFirst(rootPath.count + 1))
        for component in relativePath.split(separator: "/").map(String.init) where !component.isEmpty {
            current.appendPathComponent(component, isDirectory: true)
            if isSymbolicLink(current) {
                throw LearnHousePackageError.unsafeDestination(current.path)
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    throw LearnHousePackageError.unsafeDestination(current.path)
                }
                let resolved = current.resolvingSymlinksInPath()
                guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
                    throw LearnHousePackageError.unsafeDestination(current.path)
                }
            } else {
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
    }

    private func stableID(prefix: String, value: String) -> String {
        "\(prefix)-\(slug(value))"
    }

    private func fileExtension(for path: String) -> String? {
        URL(fileURLWithPath: path).pathExtension.nilIfEmpty
    }

    private func mimeType(for path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "mp4": "video/mp4"
        case "webm": "video/webm"
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "vtt": "text/vtt"
        case "srt": "application/x-subrip"
        case "md": "text/markdown"
        case "txt": "text/plain"
        case "json": "application/json"
        default: nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum AnyCodableValue: Encodable, Equatable {
    case string(String)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case optionalString(String?)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .optionalString(let value):
            try container.encode(value)
        }
    }
}
