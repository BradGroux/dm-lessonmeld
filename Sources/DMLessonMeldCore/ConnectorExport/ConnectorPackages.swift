import Foundation

public enum ConnectorPackageKind: String, Codable, CaseIterable, Sendable {
    case commonCartridge = "common-cartridge"
    case scorm
    case xapi
    case videoHost = "video-host"
}

public struct ConnectorPackageFile: Codable, Equatable, Sendable {
    public var role: ProjectFileRole?
    public var relativePath: String
    public var sourceRelativePath: String?
    public var sha256: String
    public var byteCount: Int64

    enum CodingKeys: String, CodingKey {
        case role
        case relativePath = "relative_path"
        case sourceRelativePath = "source_relative_path"
        case sha256
        case byteCount = "byte_count"
    }

    public init(
        role: ProjectFileRole?,
        relativePath: String,
        sourceRelativePath: String?,
        sha256: String,
        byteCount: Int64
    ) {
        self.role = role
        self.relativePath = relativePath
        self.sourceRelativePath = sourceRelativePath
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public struct ConnectorPackageManifest: Codable, Equatable, Sendable {
    public var schema: String
    public var schemaVersion: Int
    public var kind: ConnectorPackageKind
    public var generatedAt: Date
    public var sourceProject: String
    public var lessonTitle: String
    public var courseTitle: String?
    public var moduleTitle: String?
    public var primaryLaunchPath: String
    public var checksumPath: String?
    public var files: [ConnectorPackageFile]
    public var notes: [String]

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case kind
        case generatedAt = "generated_at"
        case sourceProject = "source_project"
        case lessonTitle = "lesson_title"
        case courseTitle = "course_title"
        case moduleTitle = "module_title"
        case primaryLaunchPath = "primary_launch_path"
        case checksumPath = "checksum_path"
        case files
        case notes
    }

    public init(
        schema: String = "io.digitalmeld.dm-lessonmeld.connector-package",
        schemaVersion: Int = 1,
        kind: ConnectorPackageKind,
        generatedAt: Date = Date(),
        sourceProject: String,
        lessonTitle: String,
        courseTitle: String?,
        moduleTitle: String?,
        primaryLaunchPath: String,
        checksumPath: String?,
        files: [ConnectorPackageFile],
        notes: [String]
    ) {
        self.schema = schema
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.generatedAt = generatedAt
        self.sourceProject = sourceProject
        self.lessonTitle = lessonTitle
        self.courseTitle = courseTitle
        self.moduleTitle = moduleTitle
        self.primaryLaunchPath = primaryLaunchPath
        self.checksumPath = checksumPath
        self.files = files
        self.notes = notes
    }
}

public struct ConnectorPackageResult: Codable, Equatable, Sendable {
    public var packagePath: String
    public var archivePath: String?
    public var manifest: ConnectorPackageManifest

    enum CodingKeys: String, CodingKey {
        case packagePath = "package_path"
        case archivePath = "archive_path"
        case manifest
    }

    public init(packagePath: String, archivePath: String?, manifest: ConnectorPackageManifest) {
        self.packagePath = packagePath
        self.archivePath = archivePath
        self.manifest = manifest
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packagePath, forKey: .packagePath)
        if let archivePath {
            try container.encode(archivePath, forKey: .archivePath)
        } else {
            try container.encodeNil(forKey: .archivePath)
        }
        try container.encode(manifest, forKey: .manifest)
    }
}

public enum ConnectorPackageError: Error, Equatable, LocalizedError, Sendable {
    case missingPrimaryVideo
    case missingProjectAsset(String)
    case unsafeSource(String)
    case unsafeDestination(String)

    public var errorDescription: String? {
        switch self {
        case .missingPrimaryVideo:
            "Connector packages require a primary screen video in the project manifest."
        case .missingProjectAsset(let path):
            "Project asset is missing: \(path)"
        case .unsafeSource(let path):
            "Connector package source is not safe: \(path)"
        case .unsafeDestination(let path):
            "Connector package destination is not safe: \(path)"
        }
    }
}

public struct CommonCartridgePackageBuilder {
    public var archiveBuilder: LearnHouseArchiveBuilder

    public init(archiveBuilder: LearnHouseArchiveBuilder = LearnHouseArchiveBuilder()) {
        self.archiveBuilder = archiveBuilder
    }

    public func buildPackage(projectURL: URL, outputDirectory: URL, archive: Bool = true) throws -> ConnectorPackageResult {
        try ConnectorPackageWriter(projectURL: projectURL, outputDirectory: outputDirectory, archiveBuilder: archiveBuilder)
            .build(kind: .commonCartridge, directoryExtension: "common-cartridge", archiveExtension: "imscc", archive: archive) { context in
                try context.writeText(commonCartridgeManifest(context), to: "imsmanifest.xml")
                try context.writeText(lessonHTML(context: context, title: context.manifest.metadata.lessonTitle), to: "lesson/index.html")
            }
    }

    private func commonCartridgeManifest(_ context: ConnectorPackageContext) -> String {
        let files = context.files.map { #"      <file href="\#(xmlEscape($0.relativePath))"/>"# }.joined(separator: "\n")
        let title = xmlEscape(context.manifest.metadata.lessonTitle)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest identifier="dm-lessonmeld-\(xmlEscape(context.slug))" xmlns="http://www.imsglobal.org/xsd/imsccv1p3/imscp_v1p1" xmlns:lom="http://ltsc.ieee.org/xsd/imsccv1p3/LOM/resource">
          <metadata>
            <schema>IMS Common Cartridge</schema>
            <schemaversion>1.3</schemaversion>
            <lom:lom>
              <lom:general>
                <lom:title><lom:string language="en">\(title)</lom:string></lom:title>
              </lom:general>
            </lom:lom>
          </metadata>
          <organizations>
            <organization identifier="org-1">
              <title>\(title)</title>
              <item identifier="item-1" identifierref="resource-lesson">
                <title>\(title)</title>
              </item>
            </organization>
          </organizations>
          <resources>
            <resource identifier="resource-lesson" type="webcontent" href="lesson/index.html">
              <file href="lesson/index.html"/>
        \(files)
            </resource>
          </resources>
        </manifest>
        """
    }
}

public struct SCORMPackageBuilder {
    public var archiveBuilder: LearnHouseArchiveBuilder

    public init(archiveBuilder: LearnHouseArchiveBuilder = LearnHouseArchiveBuilder()) {
        self.archiveBuilder = archiveBuilder
    }

    public func buildPackage(projectURL: URL, outputDirectory: URL, archive: Bool = true) throws -> ConnectorPackageResult {
        try ConnectorPackageWriter(projectURL: projectURL, outputDirectory: outputDirectory, archiveBuilder: archiveBuilder)
            .build(kind: .scorm, directoryExtension: "scorm-package", archiveExtension: "scorm.zip", archive: archive) { context in
                try context.writeText(scormManifest(context), to: "imsmanifest.xml")
                try context.writeText(scormHTML(context: context), to: "scorm/index.html")
            }
    }

    private func scormManifest(_ context: ConnectorPackageContext) -> String {
        let title = xmlEscape(context.manifest.metadata.lessonTitle)
        let files = context.files.map { #"      <file href="\#(xmlEscape($0.relativePath))"/>"# }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest identifier="dm-lessonmeld-\(xmlEscape(context.slug))" version="1.2" xmlns="http://www.imsproject.org/xsd/imscp_rootv1p1p2" xmlns:adlcp="http://www.adlnet.org/xsd/adlcp_rootv1p2">
          <metadata>
            <schema>ADL SCORM</schema>
            <schemaversion>1.2</schemaversion>
          </metadata>
          <organizations default="org-1">
            <organization identifier="org-1">
              <title>\(title)</title>
              <item identifier="item-1" identifierref="resource-lesson">
                <title>\(title)</title>
              </item>
            </organization>
          </organizations>
          <resources>
            <resource identifier="resource-lesson" type="webcontent" adlcp:scormType="sco" href="scorm/index.html">
              <file href="scorm/index.html"/>
        \(files)
            </resource>
          </resources>
        </manifest>
        """
    }
}

public struct XAPIPackageBuilder {
    public var archiveBuilder: LearnHouseArchiveBuilder

    public init(archiveBuilder: LearnHouseArchiveBuilder = LearnHouseArchiveBuilder()) {
        self.archiveBuilder = archiveBuilder
    }

    public func buildPackage(projectURL: URL, outputDirectory: URL, archive: Bool = true) throws -> ConnectorPackageResult {
        try ConnectorPackageWriter(projectURL: projectURL, outputDirectory: outputDirectory, archiveBuilder: archiveBuilder)
            .build(kind: .xapi, directoryExtension: "xapi-package", archiveExtension: "xapi.zip", archive: archive) { context in
                try context.writeJSON(xapiActivity(context), to: "xapi/activity.json")
                try context.writeJSON(xapiFixtureStatements(context), to: "xapi/statements.fixture.json")
                try context.writeText(xapiHTML(context: context), to: "xapi/index.html")
            }
    }

    private func xapiActivity(_ context: ConnectorPackageContext) -> [String: AnyCodableConnectorValue] {
        [
            "id": .string("https://lessonmeld.local/activity/\(context.slug)"),
            "definition": .dictionary([
                "name": .dictionary(["en-US": .string(context.manifest.metadata.lessonTitle)]),
                "description": .dictionary(["en-US": .string(context.manifest.metadata.summary ?? "")]),
                "type": .string("http://adlnet.gov/expapi/activities/media")
            ]),
            "objectType": .string("Activity")
        ]
    }

    private func xapiFixtureStatements(_ context: ConnectorPackageContext) -> [[String: AnyCodableConnectorValue]] {
        let activityID = "https://lessonmeld.local/activity/\(context.slug)"
        return [
            statement(activityID: activityID, verbID: "http://adlnet.gov/expapi/verbs/launched", verb: "launched"),
            statement(activityID: activityID, verbID: "http://adlnet.gov/expapi/verbs/completed", verb: "completed")
        ]
    }

    private func statement(activityID: String, verbID: String, verb: String) -> [String: AnyCodableConnectorValue] {
        [
            "actor": .dictionary([
                "objectType": .string("Agent"),
                "name": .string("Example Learner"),
                "mbox": .string("mailto:learner@example.invalid")
            ]),
            "verb": .dictionary([
                "id": .string(verbID),
                "display": .dictionary(["en-US": .string(verb)])
            ]),
            "object": .dictionary([
                "id": .string(activityID),
                "objectType": .string("Activity")
            ])
        ]
    }
}

public struct VideoHostHandoffBuilder {
    public var archiveBuilder: LearnHouseArchiveBuilder

    public init(archiveBuilder: LearnHouseArchiveBuilder = LearnHouseArchiveBuilder()) {
        self.archiveBuilder = archiveBuilder
    }

    public func buildPackage(projectURL: URL, outputDirectory: URL, archive: Bool = false) throws -> ConnectorPackageResult {
        try ConnectorPackageWriter(projectURL: projectURL, outputDirectory: outputDirectory, archiveBuilder: archiveBuilder)
            .build(kind: .videoHost, directoryExtension: "video-handoff", archiveExtension: "video-handoff.zip", archive: archive) { context in
                let metadata = videoHostMetadata(context)
                try context.writeJSON(metadata, to: "video-host/metadata.json")
                try context.writeJSON(videoHostProfile(context, host: "youtube"), to: "video-host/youtube.json")
                try context.writeJSON(videoHostProfile(context, host: "vimeo"), to: "video-host/vimeo.json")
                try context.writeJSON(videoHostProfile(context, host: "kaltura"), to: "video-host/kaltura.json")
                try context.writeJSON(videoHostProfile(context, host: "panopto"), to: "video-host/panopto.json")
            }
    }

    private func videoHostMetadata(_ context: ConnectorPackageContext) -> [String: AnyCodableConnectorValue] {
        [
            "title": .string(context.manifest.metadata.lessonTitle),
            "description": .string(context.manifest.metadata.summary ?? ""),
            "tags": .array(context.manifest.metadata.tags.map { .string($0) }),
            "course_title": .optionalString(context.manifest.metadata.courseTitle),
            "module_title": .optionalString(context.manifest.metadata.moduleTitle),
            "primary_video": .optionalString(context.primaryVideoPath),
            "thumbnail": .optionalString(context.firstPath(role: .thumbnail)),
            "captions": .array(context.paths(role: .captions).map { .string($0) }),
            "transcripts": .array(context.paths(role: .transcript).map { .string($0) }),
            "chapters": .array(ChapterExporter.entries(from: context.manifest).map { chapter in
                .dictionary([
                    "title": .string(chapter.title),
                    "time_seconds": .double(chapter.timeSeconds),
                    "notes": .optionalString(chapter.notes)
                ])
            }),
            "privacy": .string("manual-upload")
        ]
    }

    private func videoHostProfile(_ context: ConnectorPackageContext, host: String) -> [String: AnyCodableConnectorValue] {
        [
            "host": .string(host),
            "title": .string(context.manifest.metadata.lessonTitle),
            "description": .string(description(context: context, host: host)),
            "tags": .array(context.manifest.metadata.tags.map { .string($0) }),
            "video_path": .optionalString(context.primaryVideoPath),
            "caption_paths": .array(context.paths(role: .captions).map { .string($0) }),
            "thumbnail_path": .optionalString(context.firstPath(role: .thumbnail)),
            "upload_mode": .string("manual")
        ]
    }

    private func description(context: ConnectorPackageContext, host: String) -> String {
        var lines = [context.manifest.metadata.summary ?? ""].filter { !$0.isEmpty }
        let chapters = ChapterExporter.entries(from: context.manifest)
        if !chapters.isEmpty {
            lines.append("")
            lines.append("Chapters")
            lines.append(contentsOf: chapters.map { "\(videoHostTimestamp($0.timeSeconds)) \(host == "youtube" ? $0.title : "- \($0.title)")" })
        }
        return lines.joined(separator: "\n")
    }
}

public struct ConnectorPackageContext {
    public var packageURL: URL
    public var slug: String
    public var manifest: ProjectManifest
    public var files: [ConnectorPackageFile]
    public var primaryLaunchPath: String

    public var primaryVideoPath: String? {
        firstPath(role: .screenVideo)
    }

    public func paths(role: ProjectFileRole) -> [String] {
        files.filter { $0.role == role }.map(\.relativePath)
    }

    public func firstPath(role: ProjectFileRole) -> String? {
        paths(role: role).first
    }

    public func writeText(_ text: String, to relativePath: String) throws {
        let url = packageURL.appendingPathComponent(relativePath)
        try ConnectorPackageUtilities.ensureSafeDirectory(url.deletingLastPathComponent(), within: packageURL)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    public func writeJSON<T: Encodable>(_ value: T, to relativePath: String) throws {
        let url = packageURL.appendingPathComponent(relativePath)
        try ConnectorPackageUtilities.ensureSafeDirectory(url.deletingLastPathComponent(), within: packageURL)
        try DMLessonJSON.encoder().encode(value).write(to: url, options: [.atomic])
    }
}

private struct ConnectorPackageWriter {
    var projectURL: URL
    var outputDirectory: URL
    var archiveBuilder: LearnHouseArchiveBuilder

    func build(
        kind: ConnectorPackageKind,
        directoryExtension: String,
        archiveExtension: String,
        archive: Bool,
        writeConnectorFiles: (ConnectorPackageContext) throws -> Void
    ) throws -> ConnectorPackageResult {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        guard manifest.media.screen != nil else {
            throw ConnectorPackageError.missingPrimaryVideo
        }

        let slug = ConnectorPackageUtilities.slug(manifest.metadata.lessonTitle)
        let packageURL = outputDirectory.appendingPathComponent("\(slug).\(directoryExtension)", isDirectory: true)
        let assetsURL = packageURL.appendingPathComponent("assets", isDirectory: true)
        try ConnectorPackageUtilities.ensureSafeDirectory(packageURL, within: outputDirectory)
        try ConnectorPackageUtilities.ensureSafeDirectory(assetsURL, within: packageURL)

        var files = try ConnectorPackageUtilities.copyProjectFiles(
            manifest.media.allFiles,
            projectURL: projectURL,
            destinationRoot: assetsURL,
            destinationPrefix: "assets",
            requireExisting: false
        )

        let primaryLaunchPath = primaryLaunchPath(for: kind)
        var context = ConnectorPackageContext(
            packageURL: packageURL,
            slug: slug,
            manifest: manifest,
            files: files,
            primaryLaunchPath: primaryLaunchPath
        )
        try writeConnectorFiles(context)

        files = try ConnectorPackageUtilities.scanPackageFiles(
            packageURL: packageURL,
            excluding: ["manifest.json", "connector-package.json", "checksums.sha256"]
        )
        context.files = files
        let checksumPath = try ConnectorPackageUtilities.writeChecksums(files: files, rootURL: packageURL, relativePath: "checksums.sha256")
        let packageManifest = ConnectorPackageManifest(
            kind: kind,
            sourceProject: projectURL.lastPathComponent,
            lessonTitle: manifest.metadata.lessonTitle,
            courseTitle: manifest.metadata.courseTitle,
            moduleTitle: manifest.metadata.moduleTitle,
            primaryLaunchPath: primaryLaunchPath,
            checksumPath: checksumPath,
            files: files,
            notes: notes(for: kind)
        )
        try context.writeJSON(packageManifest, to: "connector-package.json")
        try context.writeJSON(packageManifest, to: "manifest.json")

        let archiveURL = archive
            ? try archiveBuilder.buildArchive(
                packageDirectory: packageURL,
                archiveURL: outputDirectory.appendingPathComponent("\(slug).\(archiveExtension)")
            )
            : nil
        return ConnectorPackageResult(
            packagePath: packageURL.path,
            archivePath: archiveURL?.path,
            manifest: packageManifest
        )
    }

    private func primaryLaunchPath(for kind: ConnectorPackageKind) -> String {
        switch kind {
        case .commonCartridge:
            "lesson/index.html"
        case .scorm:
            "scorm/index.html"
        case .xapi:
            "xapi/index.html"
        case .videoHost:
            "video-host/metadata.json"
        }
    }

    private func notes(for kind: ConnectorPackageKind) -> [String] {
        switch kind {
        case .commonCartridge:
            [
                "Local Common Cartridge package. Import into an LMS that supports Common Cartridge web content resources.",
                "This package contains no credentials and performs no network publishing."
            ]
        case .scorm:
            [
                "SCORM 1.2 package with a local launch page and conservative completion hooks.",
                "Validate against target LMS runtimes before making conformance claims."
            ]
        case .xapi:
            [
                "xAPI activity package with fixture statements only.",
                "LRS endpoints and credentials must be supplied at runtime and are not stored in the project bundle."
            ]
        case .videoHost:
            [
                "Manual video-host upload handoff with metadata profiles.",
                "No OAuth tokens, API credentials, or uploads are performed."
            ]
        }
    }
}

private enum ConnectorPackageUtilities {
    static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let lowered = value.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(lowered).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "lesson" : collapsed
    }

    static func copyProjectFiles(
        _ files: [ProjectFile],
        projectURL: URL,
        destinationRoot: URL,
        destinationPrefix: String,
        requireExisting: Bool
    ) throws -> [ConnectorPackageFile] {
        try files.compactMap { file in
            let sourceURL = try ProjectBundle.projectLocalFileURL(for: file, in: projectURL)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                if requireExisting {
                    throw ConnectorPackageError.missingProjectAsset(file.relativePath)
                }
                return nil
            }
            guard !isSymbolicLink(sourceURL) else {
                throw ConnectorPackageError.unsafeSource(sourceURL.path)
            }
            let destinationURL = destinationRoot.appendingPathComponent(file.relativePath)
            let relativePath = "\(destinationPrefix)/\(file.relativePath)"
            try validatePackageRelativePath(relativePath)
            try ensureSafeDirectory(destinationURL.deletingLastPathComponent(), within: destinationRoot)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                guard !isSymbolicLink(destinationURL) else {
                    throw ConnectorPackageError.unsafeDestination(destinationURL.path)
                }
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return ConnectorPackageFile(
                role: file.role,
                relativePath: relativePath,
                sourceRelativePath: file.relativePath,
                sha256: try sha256Hex(for: destinationURL),
                byteCount: try byteCount(for: destinationURL)
            )
        }
    }

    static func scanPackageFiles(packageURL: URL, excluding excluded: Set<String>) throws -> [ConnectorPackageFile] {
        let rootPath = packageURL.standardizedFileURL.resolvingSymlinksInPath().path
        guard let enumerator = FileManager.default.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return try enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            let filePath = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard filePath.hasPrefix(rootPath + "/") else {
                throw ConnectorPackageError.unsafeSource(url.path)
            }
            let relativePath = String(filePath.dropFirst(rootPath.count + 1))
            guard !excluded.contains(relativePath) else { return nil }
            try validatePackageRelativePath(relativePath)
            return ConnectorPackageFile(
                role: role(for: relativePath),
                relativePath: relativePath,
                sourceRelativePath: nil,
                sha256: try sha256Hex(for: url),
                byteCount: try byteCount(for: url)
            )
        }
        .sorted { $0.relativePath < $1.relativePath }
    }

    static func writeChecksums(files: [ConnectorPackageFile], rootURL: URL, relativePath: String) throws -> String? {
        guard !files.isEmpty else { return nil }
        let lines = try files
            .sorted { $0.relativePath < $1.relativePath }
            .map { file in
                try validatePackageRelativePath(file.relativePath)
                return "\(file.sha256)  \(file.relativePath)"
            }
            .joined(separator: "\n")
        let checksumURL = rootURL.appendingPathComponent(relativePath)
        try ensureSafeDirectory(checksumURL.deletingLastPathComponent(), within: rootURL)
        try "\(lines)\n".write(to: checksumURL, atomically: true, encoding: .utf8)
        return relativePath
    }

    static func ensureSafeDirectory(_ directoryURL: URL, within rootURL: URL) throws {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        var current = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rootPath = root.standardizedFileURL.path
        let targetPath = directoryURL.standardizedFileURL.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            throw ConnectorPackageError.unsafeDestination(directoryURL.path)
        }
        let relativePath = targetPath == rootPath ? "" : String(targetPath.dropFirst(rootPath.count + 1))
        for component in relativePath.split(separator: "/").map(String.init) where !component.isEmpty {
            current.appendPathComponent(component, isDirectory: true)
            if isSymbolicLink(current) {
                throw ConnectorPackageError.unsafeDestination(current.path)
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    throw ConnectorPackageError.unsafeDestination(current.path)
                }
                let resolved = current.resolvingSymlinksInPath()
                guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
                    throw ConnectorPackageError.unsafeDestination(current.path)
                }
            } else {
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
    }

    static func sha256Hex(for url: URL) throws -> String {
        try FileChecksum.sha256Hex(for: url)
    }

    static func byteCount(for url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    static func validatePackageRelativePath(_ path: String) throws {
        guard !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ConnectorPackageError.unsafeSource(path)
        }
    }

    private static func role(for relativePath: String) -> ProjectFileRole? {
        guard relativePath.hasPrefix("assets/") else { return nil }
        let path = String(relativePath.dropFirst("assets/".count))
        let file = ProjectFile(relativePath: path, role: .attachment)
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "mp4", "mov", "webm":
            return path.contains("webcam") ? .webcamVideo : .screenVideo
        case "vtt", "srt":
            return .captions
        case "md", "txt", "json":
            return .transcript
        case "jpg", "jpeg", "png":
            return .thumbnail
        default:
            return file.role
        }
    }
}

private func lessonHTML(context: ConnectorPackageContext, title: String) -> String {
    let video = context.primaryVideoPath ?? ""
    let escapedTitle = htmlEscape(title)
    return """
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>\(escapedTitle)</title></head>
    <body>
      <main>
        <h1>\(escapedTitle)</h1>
        <video controls preload="metadata" src="../\(htmlEscape(video))" style="max-width:100%;height:auto"></video>
      </main>
    </body>
    </html>
    """
}

private func scormHTML(context: ConnectorPackageContext) -> String {
    let video = context.primaryVideoPath.map { "../\($0)" } ?? ""
    return """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>\(htmlEscape(context.manifest.metadata.lessonTitle))</title>
      <script>
      function findAPI(win) {
        var depth = 0;
        while (win && !win.API && win.parent && win.parent !== win && depth < 10) {
          win = win.parent;
          depth += 1;
        }
        return win ? win.API : null;
      }
      function completeLesson() {
        var api = findAPI(window);
        if (!api) return;
        api.LMSInitialize("");
        api.LMSSetValue("cmi.core.lesson_status", "completed");
        api.LMSCommit("");
      }
      </script>
    </head>
    <body>
      <main>
        <h1>\(htmlEscape(context.manifest.metadata.lessonTitle))</h1>
        <video controls preload="metadata" src="\(htmlEscape(video))" onended="completeLesson()" style="max-width:100%;height:auto"></video>
      </main>
    </body>
    </html>
    """
}

private func xapiHTML(context: ConnectorPackageContext) -> String {
    let video = context.primaryVideoPath.map { "../\($0)" } ?? ""
    return """
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>\(htmlEscape(context.manifest.metadata.lessonTitle))</title></head>
    <body>
      <main data-xapi-activity="https://lessonmeld.local/activity/\(htmlEscape(context.slug))">
        <h1>\(htmlEscape(context.manifest.metadata.lessonTitle))</h1>
        <video controls preload="metadata" src="\(htmlEscape(video))" style="max-width:100%;height:auto"></video>
      </main>
    </body>
    </html>
    """
}

private func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private func htmlEscape(_ value: String) -> String {
    xmlEscape(value)
}

private func videoHostTimestamp(_ seconds: Double) -> String {
    let totalSeconds = max(0, Int(seconds.rounded(.down)))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}

public enum AnyCodableConnectorValue: Encodable, Equatable, Sendable {
    case string(String)
    case double(Double)
    case array([AnyCodableConnectorValue])
    case dictionary([String: AnyCodableConnectorValue])
    case optionalString(String?)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .optionalString(let value):
            if let value {
                try container.encode(value)
            } else {
                try container.encodeNil()
            }
        }
    }
}
