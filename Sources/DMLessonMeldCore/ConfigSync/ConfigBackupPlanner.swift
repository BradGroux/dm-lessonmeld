import Foundation

public struct ConfigBackupPlan: Codable, Equatable, Sendable {
    public var rootPath: String
    public var includePaths: [String]
    public var excludedPaths: [ExcludedConfigPath]

    public init(rootPath: String, includePaths: [String], excludedPaths: [ExcludedConfigPath]) {
        self.rootPath = rootPath
        self.includePaths = includePaths
        self.excludedPaths = excludedPaths
    }
}

public struct ExcludedConfigPath: Codable, Equatable, Sendable {
    public var path: String
    public var reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct ConfigBackupPlanner: Sendable {
    public init() {}

    public func plan(rootURL: URL) throws -> ConfigBackupPlan {
        var includePaths: [String] = []
        var excludedPaths: [ExcludedConfigPath] = []
        let normalizedRootURL = rootURL.resolvingSymlinksInPath()
        let normalizedRootPath = normalizedRootURL.path

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ConfigBackupPlan(rootPath: rootURL.path, includePaths: [], excludedPaths: [])
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let normalizedFilePath = url.resolvingSymlinksInPath().path
            let relativePath = normalizedFilePath
                .replacingOccurrences(of: normalizedRootPath + "/", with: "")
            if let reason = exclusionReason(for: relativePath) {
                excludedPaths.append(ExcludedConfigPath(path: relativePath, reason: reason))
            } else if isSyncable(relativePath: relativePath) {
                includePaths.append(relativePath)
            }
        }

        return ConfigBackupPlan(
            rootPath: normalizedRootPath,
            includePaths: includePaths.sorted(),
            excludedPaths: excludedPaths.sorted { $0.path < $1.path }
        )
    }

    private func isSyncable(relativePath: String) -> Bool {
        let allowedExtensions = ["json", "yaml", "yml", "toml", "md"]
        guard let ext = relativePath.split(separator: ".").last?.lowercased() else {
            return false
        }
        return allowedExtensions.contains(ext)
    }

    private func exclusionReason(for relativePath: String) -> String? {
        let lowered = relativePath.lowercased()
        let blockedComponents = [
            "projects/",
            "caches/",
            "diagnostics/",
            "secrets/",
            "transcripts/",
            "media/",
            "exports/"
        ]

        if blockedComponents.contains(where: { lowered.contains($0) }) {
            return "Contains project media, generated output, diagnostics, transcripts, cache, or secrets."
        }

        let blockedExtensions = ["mp4", "mov", "m4a", "wav", "aiff", "png", "jpg", "jpeg", "gif"]
        if let ext = lowered.split(separator: ".").last, blockedExtensions.contains(String(ext)) {
            return "Binary media files are not part of config backup."
        }

        if lowered.contains("token") || lowered.contains("credential") || lowered.contains("secret") {
            return "Potential credential material must stay out of Git sync."
        }

        return nil
    }
}
