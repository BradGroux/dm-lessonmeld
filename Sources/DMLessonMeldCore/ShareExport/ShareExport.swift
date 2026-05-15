import CryptoKit
import Foundation

public struct SharePackageFile: Codable, Equatable, Sendable {
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
        sourceRelativePath: String? = nil,
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

public struct RawAssetExtractionResult: Codable, Equatable, Sendable {
    public var outputDirectoryPath: String
    public var checksumPath: String?
    public var files: [SharePackageFile]

    enum CodingKeys: String, CodingKey {
        case outputDirectoryPath = "output_directory_path"
        case checksumPath = "checksum_path"
        case files
    }

    public init(outputDirectoryPath: String, checksumPath: String?, files: [SharePackageFile]) {
        self.outputDirectoryPath = outputDirectoryPath
        self.checksumPath = checksumPath
        self.files = files
    }
}

public struct LocalSharePackageManifest: Codable, Equatable, Sendable {
    public var schema: String
    public var schemaVersion: Int
    public var generatedAt: Date
    public var sourceProject: String
    public var lessonTitle: String
    public var finalVideoPath: String?
    public var rawAssetsPath: String
    public var checksumPath: String?
    public var files: [SharePackageFile]
    public var notes: [String]

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case sourceProject = "source_project"
        case lessonTitle = "lesson_title"
        case finalVideoPath = "final_video_path"
        case rawAssetsPath = "raw_assets_path"
        case checksumPath = "checksum_path"
        case files
        case notes
    }

    public init(
        schema: String = "io.digitalmeld.dm-lessonmeld.local-share-package",
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        sourceProject: String,
        lessonTitle: String,
        finalVideoPath: String?,
        rawAssetsPath: String = "raw-assets",
        checksumPath: String?,
        files: [SharePackageFile],
        notes: [String] = []
    ) {
        self.schema = schema
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.sourceProject = sourceProject
        self.lessonTitle = lessonTitle
        self.finalVideoPath = finalVideoPath
        self.rawAssetsPath = rawAssetsPath
        self.checksumPath = checksumPath
        self.files = files
        self.notes = notes
    }
}

public struct LocalSharePackageResult: Codable, Equatable, Sendable {
    public var packagePath: String
    public var archivePath: String?
    public var manifest: LocalSharePackageManifest

    enum CodingKeys: String, CodingKey {
        case packagePath = "package_path"
        case archivePath = "archive_path"
        case manifest
    }

    public init(packagePath: String, archivePath: String? = nil, manifest: LocalSharePackageManifest) {
        self.packagePath = packagePath
        self.archivePath = archivePath
        self.manifest = manifest
    }
}

public enum ShareExportError: Error, Equatable, LocalizedError, Sendable {
    case missingProjectAsset(String)
    case unsafeSource(String)
    case unsafeDestination(String)
    case finalVideoMissing(String)

    public var errorDescription: String? {
        switch self {
        case .missingProjectAsset(let path):
            "Project asset is missing: \(path)"
        case .unsafeSource(let path):
            "Export source is not safe: \(path)"
        case .unsafeDestination(let path):
            "Export destination is not safe: \(path)"
        case .finalVideoMissing(let path):
            "Final video does not exist: \(path)"
        }
    }
}

public struct RawAssetExtractor {
    public init() {}

    public func extract(projectURL: URL, outputDirectory: URL) throws -> RawAssetExtractionResult {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let rootURL = outputDirectory.appendingPathComponent("\(Self.slug(manifest.metadata.lessonTitle))-raw-assets", isDirectory: true)
        try ShareExportUtilities.ensureSafeDirectory(rootURL, within: outputDirectory, error: ShareExportError.unsafeDestination)
        let files = try Self.copyProjectFiles(
            manifest.media.allFiles,
            projectURL: projectURL,
            destinationRoot: rootURL,
            destinationPrefix: "",
            requireExisting: true
        )
        let checksumPath = try Self.writeChecksums(files: files, rootURL: rootURL, relativePath: "checksums.sha256")
        return RawAssetExtractionResult(
            outputDirectoryPath: rootURL.path,
            checksumPath: checksumPath,
            files: files
        )
    }
}

public struct LocalSharePackageBuilder {
    public var archiveBuilder: LearnHouseArchiveBuilder

    public init(archiveBuilder: LearnHouseArchiveBuilder = LearnHouseArchiveBuilder()) {
        self.archiveBuilder = archiveBuilder
    }

    public func buildPackage(
        projectURL: URL,
        outputDirectory: URL,
        finalVideoURL: URL? = nil,
        archive: Bool = false
    ) throws -> LocalSharePackageResult {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let packageURL = outputDirectory.appendingPathComponent("\(Self.slug(manifest.metadata.lessonTitle)).lessonshare", isDirectory: true)
        let rawAssetsURL = packageURL.appendingPathComponent("raw-assets", isDirectory: true)
        let projectURLInPackage = packageURL.appendingPathComponent("project", isDirectory: true)
        let exportsURL = packageURL.appendingPathComponent("exports", isDirectory: true)

        try ShareExportUtilities.ensureSafeDirectory(packageURL, within: outputDirectory, error: ShareExportError.unsafeDestination)
        try ShareExportUtilities.ensureSafeDirectory(rawAssetsURL, within: packageURL, error: ShareExportError.unsafeDestination)
        try ShareExportUtilities.ensureSafeDirectory(projectURLInPackage, within: packageURL, error: ShareExportError.unsafeDestination)
        try ShareExportUtilities.ensureSafeDirectory(exportsURL, within: packageURL, error: ShareExportError.unsafeDestination)

        var files = try Self.copyProjectFiles(
            manifest.media.allFiles,
            projectURL: projectURL,
            destinationRoot: rawAssetsURL,
            destinationPrefix: "raw-assets",
            requireExisting: false
        )

        files.append(try Self.writeJSONFile(
            manifest,
            role: .manifest,
            relativePath: "project/project-manifest.json",
            rootURL: packageURL
        ))
        files += try Self.copyOptionalProjectSidecars(projectURL: projectURL, packageURL: packageURL)

        let finalVideoPath: String?
        if let finalVideoURL {
            guard FileManager.default.fileExists(atPath: finalVideoURL.path) else {
                throw ShareExportError.finalVideoMissing(finalVideoURL.path)
            }
            guard !ShareExportUtilities.isSymbolicLink(finalVideoURL) else {
                throw ShareExportError.unsafeSource(finalVideoURL.path)
            }
            let relativePath = "exports/\(finalVideoURL.lastPathComponent)"
            files.append(try Self.copyFile(
                sourceURL: finalVideoURL,
                destinationURL: packageURL.appendingPathComponent(relativePath),
                destinationRoot: packageURL,
                role: .screenVideo,
                relativePath: relativePath,
                sourceRelativePath: nil
            ))
            finalVideoPath = relativePath
        } else {
            finalVideoPath = nil
        }

        let checksumPath = try Self.writeChecksums(files: files, rootURL: packageURL, relativePath: "checksums.sha256")
        let packageManifest = LocalSharePackageManifest(
            sourceProject: projectURL.lastPathComponent,
            lessonTitle: manifest.metadata.lessonTitle,
            finalVideoPath: finalVideoPath,
            checksumPath: checksumPath,
            files: files,
            notes: [
                "This local share package is file-based and contains no credentials.",
                "Use raw-assets for source media and project sidecars for editable LessonMeld state."
            ]
        )
        let manifestData = try DMLessonJSON.encoder().encode(packageManifest)
        try manifestData.write(to: packageURL.appendingPathComponent("share-package.json"), options: [.atomic])
        try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"), options: [.atomic])

        let archiveURL = archive ? try archiveBuilder.buildArchive(packageDirectory: packageURL) : nil
        return LocalSharePackageResult(
            packagePath: packageURL.path,
            archivePath: archiveURL?.path,
            manifest: packageManifest
        )
    }
}

extension RawAssetExtractor {
    fileprivate static func slug(_ value: String) -> String {
        ShareExportUtilities.slug(value)
    }

    fileprivate static func copyProjectFiles(
        _ files: [ProjectFile],
        projectURL: URL,
        destinationRoot: URL,
        destinationPrefix: String,
        requireExisting: Bool
    ) throws -> [SharePackageFile] {
        try ShareExportUtilities.copyProjectFiles(
            files,
            projectURL: projectURL,
            destinationRoot: destinationRoot,
            destinationPrefix: destinationPrefix,
            requireExisting: requireExisting
        )
    }

    fileprivate static func writeChecksums(files: [SharePackageFile], rootURL: URL, relativePath: String) throws -> String? {
        try ShareExportUtilities.writeChecksums(files: files, rootURL: rootURL, relativePath: relativePath)
    }
}

extension LocalSharePackageBuilder {
    fileprivate static func slug(_ value: String) -> String {
        ShareExportUtilities.slug(value)
    }

    fileprivate static func copyProjectFiles(
        _ files: [ProjectFile],
        projectURL: URL,
        destinationRoot: URL,
        destinationPrefix: String,
        requireExisting: Bool
    ) throws -> [SharePackageFile] {
        try ShareExportUtilities.copyProjectFiles(
            files,
            projectURL: projectURL,
            destinationRoot: destinationRoot,
            destinationPrefix: destinationPrefix,
            requireExisting: requireExisting
        )
    }

    fileprivate static func copyOptionalProjectSidecars(projectURL: URL, packageURL: URL) throws -> [SharePackageFile] {
        let sidecars = [
            EditorSettingsFile.defaultFileName,
            EditDecisionListFile.defaultFileName,
            OverlayStoreFile.defaultFileName
        ]
        return try sidecars.compactMap { fileName in
            let sourceURL = projectURL.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
            let relativePath = "project/\(fileName)"
            return try ShareExportUtilities.copyFile(
                sourceURL: sourceURL,
                destinationURL: packageURL.appendingPathComponent(relativePath),
                destinationRoot: packageURL,
                role: nil,
                relativePath: relativePath,
                sourceRelativePath: fileName
            )
        }
    }

    fileprivate static func copyFile(
        sourceURL: URL,
        destinationURL: URL,
        destinationRoot: URL,
        role: ProjectFileRole?,
        relativePath: String,
        sourceRelativePath: String?
    ) throws -> SharePackageFile {
        try ShareExportUtilities.copyFile(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            destinationRoot: destinationRoot,
            role: role,
            relativePath: relativePath,
            sourceRelativePath: sourceRelativePath
        )
    }

    fileprivate static func writeJSONFile<T: Encodable>(
        _ value: T,
        role: ProjectFileRole?,
        relativePath: String,
        rootURL: URL
    ) throws -> SharePackageFile {
        let destinationURL = rootURL.appendingPathComponent(relativePath)
        try ShareExportUtilities.ensureSafeDirectory(destinationURL.deletingLastPathComponent(), within: rootURL, error: ShareExportError.unsafeDestination)
        let data = try DMLessonJSON.encoder().encode(value)
        try data.write(to: destinationURL, options: [.atomic])
        return SharePackageFile(
            role: role,
            relativePath: relativePath,
            sourceRelativePath: nil,
            sha256: try ShareExportUtilities.sha256Hex(for: destinationURL),
            byteCount: try ShareExportUtilities.byteCount(for: destinationURL)
        )
    }

    fileprivate static func writeChecksums(files: [SharePackageFile], rootURL: URL, relativePath: String) throws -> String? {
        try ShareExportUtilities.writeChecksums(files: files, rootURL: rootURL, relativePath: relativePath)
    }
}

private enum ShareExportUtilities {
    static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let lowered = value.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(lowered).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "lesson-share" : collapsed
    }

    static func copyProjectFiles(
        _ files: [ProjectFile],
        projectURL: URL,
        destinationRoot: URL,
        destinationPrefix: String,
        requireExisting: Bool
    ) throws -> [SharePackageFile] {
        try files.compactMap { file in
            let sourceURL = try ProjectBundle.projectLocalFileURL(for: file, in: projectURL)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                if requireExisting {
                    throw ShareExportError.missingProjectAsset(file.relativePath)
                }
                return nil
            }

            let destinationURL = destinationRoot.appendingPathComponent(file.relativePath)
            let relativePath = destinationPrefix.isEmpty
                ? file.relativePath
                : "\(destinationPrefix)/\(file.relativePath)"
            return try copyFile(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                destinationRoot: destinationRoot,
                role: file.role,
                relativePath: relativePath,
                sourceRelativePath: file.relativePath
            )
        }
    }

    static func copyFile(
        sourceURL: URL,
        destinationURL: URL,
        destinationRoot: URL,
        role: ProjectFileRole?,
        relativePath: String,
        sourceRelativePath: String?
    ) throws -> SharePackageFile {
        guard !isSymbolicLink(sourceURL) else {
            throw ShareExportError.unsafeSource(sourceURL.path)
        }
        try ensureSafeDirectory(destinationURL.deletingLastPathComponent(), within: destinationRoot, error: ShareExportError.unsafeDestination)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            guard !isSymbolicLink(destinationURL) else {
                throw ShareExportError.unsafeDestination(destinationURL.path)
            }
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return SharePackageFile(
            role: role,
            relativePath: relativePath,
            sourceRelativePath: sourceRelativePath,
            sha256: try sha256Hex(for: destinationURL),
            byteCount: try byteCount(for: destinationURL)
        )
    }

    static func writeChecksums(files: [SharePackageFile], rootURL: URL, relativePath: String) throws -> String? {
        guard !files.isEmpty else { return nil }
        let lines = files
            .sorted { $0.relativePath < $1.relativePath }
            .map { "\($0.sha256)  \($0.relativePath)" }
            .joined(separator: "\n")
        let checksumURL = rootURL.appendingPathComponent(relativePath)
        try ensureSafeDirectory(checksumURL.deletingLastPathComponent(), within: rootURL, error: ShareExportError.unsafeDestination)
        try "\(lines)\n".write(to: checksumURL, atomically: true, encoding: .utf8)
        return relativePath
    }

    static func sha256Hex(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func byteCount(for url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    static func ensureSafeDirectory<E: Error>(
        _ directoryURL: URL,
        within rootURL: URL,
        error makeError: (String) -> E
    ) throws {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        var current = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rootPath = root.standardizedFileURL.path
        let targetPath = directoryURL.standardizedFileURL.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            throw makeError(directoryURL.path)
        }
        let relativePath = targetPath == rootPath ? "" : String(targetPath.dropFirst(rootPath.count + 1))
        for component in relativePath.split(separator: "/").map(String.init) where !component.isEmpty {
            current.appendPathComponent(component, isDirectory: true)
            if isSymbolicLink(current) {
                throw makeError(current.path)
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    throw makeError(current.path)
                }
                let resolved = current.resolvingSymlinksInPath()
                guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
                    throw makeError(current.path)
                }
            } else {
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
            }
        }
    }
}
