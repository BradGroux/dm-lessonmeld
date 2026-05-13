import Foundation

public struct ConfigGitBackupStatus: Codable, Equatable, Sendable {
    public var rootPath: String
    public var repositoryInitialized: Bool
    public var changedPaths: [String]

    public init(rootPath: String, repositoryInitialized: Bool, changedPaths: [String]) {
        self.rootPath = rootPath
        self.repositoryInitialized = repositoryInitialized
        self.changedPaths = changedPaths
    }
}

public struct ConfigGitBackupCommitResult: Codable, Equatable, Sendable {
    public var rootPath: String
    public var didCommit: Bool
    public var commitHash: String?
    public var committedPaths: [String]
    public var message: String

    public init(
        rootPath: String,
        didCommit: Bool,
        commitHash: String?,
        committedPaths: [String],
        message: String
    ) {
        self.rootPath = rootPath
        self.didCommit = didCommit
        self.commitHash = commitHash
        self.committedPaths = committedPaths
        self.message = message
    }
}

public enum ConfigGitBackupError: Error, Equatable, LocalizedError, Sendable {
    case gitNotFound(String)
    case gitFailed(String)
    case noSyncableFiles

    public var errorDescription: String? {
        switch self {
        case .gitNotFound(let path):
            "Git executable was not found at \(path)."
        case .gitFailed(let message):
            message
        case .noSyncableFiles:
            "No syncable config/template files were found."
        }
    }
}

public struct ConfigGitBackupManager: Sendable {
    public var gitExecutableURL: URL
    public var planner: ConfigBackupPlanner

    public init(
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        planner: ConfigBackupPlanner = ConfigBackupPlanner()
    ) {
        self.gitExecutableURL = gitExecutableURL
        self.planner = planner
    }

    public func ensureRepository(rootURL: URL) throws -> ConfigGitBackupStatus {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try ensureGitExists()

        if !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(".git").path) {
            try runGit(["init"], rootURL: rootURL)
        }

        try writeDefaultGitIgnore(rootURL: rootURL)
        return try status(rootURL: rootURL)
    }

    public func status(rootURL: URL) throws -> ConfigGitBackupStatus {
        let initialized = FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(".git").path)
        guard initialized else {
            return ConfigGitBackupStatus(rootPath: rootURL.path, repositoryInitialized: false, changedPaths: [])
        }

        let output = try runGit(["status", "--porcelain", "--untracked-files=all"], rootURL: rootURL)
        let changed = output
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.count >= 4 else { return nil }
                let path = String(line.dropFirst(3))
                return path.components(separatedBy: " -> ").last ?? path
            }
            .sorted()

        return ConfigGitBackupStatus(rootPath: rootURL.path, repositoryInitialized: true, changedPaths: changed)
    }

    public func commit(rootURL: URL, message: String) throws -> ConfigGitBackupCommitResult {
        _ = try ensureRepository(rootURL: rootURL)
        let plan = try planner.plan(rootURL: rootURL)
        var pathsToAdd = plan.includePaths
        if FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(".gitignore").path) {
            pathsToAdd.append(".gitignore")
        }
        pathsToAdd = Array(Set(pathsToAdd)).sorted()
        guard !pathsToAdd.isEmpty else {
            throw ConfigGitBackupError.noSyncableFiles
        }

        try runGit(["add", "--"] + pathsToAdd, rootURL: rootURL)
        let changed = try stagedPaths(rootURL: rootURL)
        guard !changed.isEmpty else {
            return ConfigGitBackupCommitResult(
                rootPath: rootURL.path,
                didCommit: false,
                commitHash: nil,
                committedPaths: [],
                message: "No config changes to commit."
            )
        }

        try runGit([
            "-c", "user.name=Digital Meld LessonMeld",
            "-c", "user.email=dm-lessonmeld@localhost",
            "commit",
            "--no-gpg-sign",
            "-m", message
        ], rootURL: rootURL)

        let hash = try runGit(["rev-parse", "--short", "HEAD"], rootURL: rootURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ConfigGitBackupCommitResult(
            rootPath: rootURL.path,
            didCommit: true,
            commitHash: hash,
            committedPaths: changed,
            message: message
        )
    }

    public func trackedPaths(rootURL: URL) throws -> [String] {
        try runGit(["ls-files"], rootURL: rootURL)
            .split(separator: "\n")
            .map(String.init)
            .sorted()
    }

    private func stagedPaths(rootURL: URL) throws -> [String] {
        try runGit(["diff", "--cached", "--name-only"], rootURL: rootURL)
            .split(separator: "\n")
            .map(String.init)
            .sorted()
    }

    private func ensureGitExists() throws {
        guard FileManager.default.isExecutableFile(atPath: gitExecutableURL.path) else {
            throw ConfigGitBackupError.gitNotFound(gitExecutableURL.path)
        }
    }

    private func writeDefaultGitIgnore(rootURL: URL) throws {
        let gitignoreURL = rootURL.appendingPathComponent(".gitignore")
        let body = """
        # Digital Meld LessonMeld local config backup
        Projects/
        projects/
        Caches/
        caches/
        Diagnostics/
        diagnostics/
        Secrets/
        secrets/
        Transcripts/
        transcripts/
        Media/
        media/
        Exports/
        exports/
        *.mp4
        *.mov
        *.m4a
        *.wav
        *.aiff
        *.png
        *.jpg
        *.jpeg
        *.gif
        *token*
        *credential*
        *secret*

        """

        if let existing = try? String(contentsOf: gitignoreURL, encoding: .utf8),
           existing.contains("# Digital Meld LessonMeld local config backup")
            || existing.contains("# DM LessonMeld local config backup") {
            return
        }

        if FileManager.default.fileExists(atPath: gitignoreURL.path),
           let existing = try? String(contentsOf: gitignoreURL, encoding: .utf8) {
            try (existing + "\n" + body).write(to: gitignoreURL, atomically: true, encoding: .utf8)
        } else {
            try body.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    private func runGit(_ arguments: [String], rootURL: URL) throws -> String {
        let process = Process()
        process.executableURL = gitExecutableURL
        process.arguments = arguments
        process.currentDirectoryURL = rootURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ConfigGitBackupError.gitFailed(error.isEmpty ? output : error)
        }

        return output
    }
}
