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

    public func redactedForAutomation() -> ConfigBackupPlan {
        ConfigBackupPlan(
            rootPath: SafePathDisplay.basename(rootPath),
            includePaths: includePaths,
            excludedPaths: excludedPaths
        )
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
    private let maxContentScanBytes = 1_048_576

    public init() {}

    public func plan(rootURL: URL) throws -> ConfigBackupPlan {
        var includePaths: [String] = []
        var excludedPaths: [ExcludedConfigPath] = []
        let normalizedRootURL = rootURL.resolvingSymlinksInPath()
        let normalizedRootPath = normalizedRootURL.path

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ConfigBackupPlan(rootPath: rootURL.path, includePaths: [], excludedPaths: [])
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let displayedRelativePath = relativePath(for: url.standardizedFileURL.path, rootPath: rootURL.standardizedFileURL.path)
            guard values.isSymbolicLink != true else {
                excludedPaths.append(ExcludedConfigPath(
                    path: displayedRelativePath,
                    reason: "Symbolic links are not included in config backups."
                ))
                continue
            }
            guard values.isRegularFile == true else { continue }

            let normalizedFilePath = url.resolvingSymlinksInPath().path
            guard normalizedFilePath == normalizedRootPath || normalizedFilePath.hasPrefix(normalizedRootPath + "/") else {
                excludedPaths.append(ExcludedConfigPath(
                    path: displayedRelativePath,
                    reason: "Path resolves outside the config backup root."
                ))
                continue
            }
            let relativePath = relativePath(for: normalizedFilePath, rootPath: normalizedRootPath)
            if let reason = exclusionReason(for: relativePath) {
                excludedPaths.append(ExcludedConfigPath(path: relativePath, reason: reason))
            } else if isSyncable(relativePath: relativePath) {
                if let reason = try contentExclusionReason(for: url) {
                    excludedPaths.append(ExcludedConfigPath(path: relativePath, reason: reason))
                } else {
                    includePaths.append(relativePath)
                }
            }
        }

        return ConfigBackupPlan(
            rootPath: normalizedRootPath,
            includePaths: includePaths.sorted(),
            excludedPaths: excludedPaths.sorted { $0.path < $1.path }
        )
    }

    private func relativePath(for filePath: String, rootPath: String) -> String {
        filePath.replacingOccurrences(of: rootPath + "/", with: "")
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

        let sensitiveTerms = [
            "token",
            "credential",
            "secret",
            "password",
            "passwd",
            "api-key",
            "apikey",
            "api_key",
            "private-key",
            "private_key",
            "oauth",
            "session",
            "cookie",
            "auth"
        ]
        if sensitiveTerms.contains(where: { lowered.contains($0) }) {
            return "Potential credential material must stay out of Git sync."
        }

        return nil
    }

    private func contentExclusionReason(for url: URL) throws -> String? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxContentScanBytes) ?? Data()
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lowered = content.lowercased()
        let secretMarkers = [
            "-----begin private key-----",
            "-----begin rsa private key-----",
            "-----begin openssh private key-----",
            "aws_secret_access_key",
            "github_token",
            "slack_bot_token",
            "xoxb-",
            "sk_live_",
            "sk_test_"
        ]
        if secretMarkers.contains(where: { lowered.contains($0) }) {
            return "Potential credential material must stay out of Git sync."
        }

        let sensitiveKeys = [
            "access_token",
            "accesstoken",
            "api_key",
            "api-key",
            "apikey",
            "auth_token",
            "authtoken",
            "client_secret",
            "clientsecret",
            "passwd",
            "password",
            "private_key",
            "private-key",
            "privatekey",
            "refresh_token",
            "refreshtoken",
            "secret",
            "session_token",
            "sessiontoken",
            "token"
        ]

        for rawLine in lowered.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            if sensitiveKeys.contains(where: { lineContainsSensitiveAssignment(line, key: $0) }) {
                return "Potential credential material must stay out of Git sync."
            }
        }

        return nil
    }

    private func lineContainsSensitiveAssignment(_ line: String, key: String) -> Bool {
        guard let keyRange = line.range(of: key),
              keyRange.lowerBound == line.startIndex || !line[line.index(before: keyRange.lowerBound)].isLetter,
              keyRange.upperBound == line.endIndex || !line[keyRange.upperBound].isLetter else {
            return false
        }

        let remainder = line[keyRange.upperBound...]
        guard let delimiterIndex = remainder.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
            return false
        }

        let value = remainder[remainder.index(after: delimiterIndex)...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"',"))
            .trimmingCharacters(in: CharacterSet(charactersIn: ",}"))
        guard !value.isEmpty, !["null", "false", "true"].contains(value) else {
            return false
        }

        return value.count >= 6
    }
}
