import DMLessonMeldCore
import Foundation
import Testing

@Suite("Config backup planner")
struct ConfigBackupPlannerTests {
    @Test("Includes syncable config and excludes media, transcripts, and secrets")
    func plansSafeConfigBackup() throws {
        let temp = try TemporaryDirectory()
        try write("{}", to: temp.url.appendingPathComponent("templates/workshop.json"))
        try write("{}", to: temp.url.appendingPathComponent("presets/brand.yaml"))
        try write("video", to: temp.url.appendingPathComponent("Projects/Lesson/screen.mp4"))
        try write("text", to: temp.url.appendingPathComponent("transcripts/lesson.md"))
        try write("token", to: temp.url.appendingPathComponent("profiles/github-token.json"))

        let plan = try ConfigBackupPlanner().plan(rootURL: temp.url)

        #expect(plan.includePaths.contains("templates/workshop.json"))
        #expect(plan.includePaths.contains("presets/brand.yaml"))
        #expect(!plan.includePaths.contains("transcripts/lesson.md"))
        #expect(plan.excludedPaths.contains { $0.path == "Projects/Lesson/screen.mp4" })
        #expect(plan.excludedPaths.contains { $0.path == "transcripts/lesson.md" })
        #expect(plan.excludedPaths.contains { $0.path == "profiles/github-token.json" })
    }

    @Test("Config plan redaction hides absolute root paths")
    func configPlanRedactionHidesRootPath() throws {
        let temp = try TemporaryDirectory()
        try write("{}", to: temp.url.appendingPathComponent("templates/workshop.json"))

        let plan = try ConfigBackupPlanner().plan(rootURL: temp.url).redactedForAutomation()

        #expect(plan.rootPath == temp.url.lastPathComponent)
        #expect(!plan.rootPath.hasPrefix("/"))
    }

    @Test("Excludes common credential file names from config backups")
    func excludesCommonCredentialNames() throws {
        let temp = try TemporaryDirectory()
        try write("{}", to: temp.url.appendingPathComponent("profiles/passwords.yaml"))
        try write("{}", to: temp.url.appendingPathComponent("profiles/api-key.toml"))
        try write("{}", to: temp.url.appendingPathComponent("profiles/private_key.json"))
        try write("{}", to: temp.url.appendingPathComponent("profiles/oauth.json"))
        try write("{}", to: temp.url.appendingPathComponent("profiles/session.json"))
        try write("{}", to: temp.url.appendingPathComponent("templates/workshop.json"))

        let plan = try ConfigBackupPlanner().plan(rootURL: temp.url)

        #expect(plan.includePaths.contains("templates/workshop.json"))
        #expect(!plan.includePaths.contains("profiles/passwords.yaml"))
        #expect(!plan.includePaths.contains("profiles/api-key.toml"))
        #expect(!plan.includePaths.contains("profiles/private_key.json"))
        #expect(!plan.includePaths.contains("profiles/oauth.json"))
        #expect(!plan.includePaths.contains("profiles/session.json"))
    }

    @Test("Excludes syncable file names with secret content")
    func excludesSecretContentInBenignFileNames() throws {
        let temp = try TemporaryDirectory()
        try write(#"{ "apiKey": "sk_test_1234567890" }"#, to: temp.url.appendingPathComponent("templates/workshop.json"))
        try write("title = \"Workshop\"", to: temp.url.appendingPathComponent("templates/safe.toml"))

        let plan = try ConfigBackupPlanner().plan(rootURL: temp.url)

        #expect(plan.includePaths.contains("templates/safe.toml"))
        #expect(!plan.includePaths.contains("templates/workshop.json"))
        #expect(plan.excludedPaths.contains {
            $0.path == "templates/workshop.json" && $0.reason.contains("credential")
        })
    }

    @Test("Classifies credential-bearing JSON, YAML, TOML, and Markdown")
    func classifiesCredentialBearingConfigFormats() throws {
        let temp = try TemporaryDirectory()
        try write(#"{ "theme": "dark" }"#, to: temp.url.appendingPathComponent("safe/settings.json"))
        try write("theme: dark", to: temp.url.appendingPathComponent("safe/settings.yaml"))
        try write("title = \"Workshop\"", to: temp.url.appendingPathComponent("safe/settings.toml"))
        try write("# Workshop template", to: temp.url.appendingPathComponent("safe/README.md"))
        try write(
            #"{ "header": "Bearer dummy-credential-123" }"#,
            to: temp.url.appendingPathComponent("unsafe/header.json")
        )
        try write(
            "connection_string: \"Endpoint=https://example.invalid;AccountKey=dummy-account-key-123\"",
            to: temp.url.appendingPathComponent("unsafe/connection.yaml")
        )
        try write(
            "account_key = \"dummy-account-key-123\"",
            to: temp.url.appendingPathComponent("unsafe/account.toml")
        )
        try write(
            "# Authorization: Bearer dummy-bearer-123",
            to: temp.url.appendingPathComponent("unsafe/header.md")
        )
        try write(
            #"{ "value": "github_pat_dummy-token-123" }"#,
            to: temp.url.appendingPathComponent("unsafe/current-token.json")
        )

        let plan = try ConfigBackupPlanner().plan(rootURL: temp.url)

        #expect(Set(plan.includePaths) == [
            "safe/README.md",
            "safe/settings.json",
            "safe/settings.toml",
            "safe/settings.yaml"
        ])
        for path in [
            "unsafe/account.toml",
            "unsafe/connection.yaml",
            "unsafe/current-token.json",
            "unsafe/header.json",
            "unsafe/header.md"
        ] {
            #expect(plan.excludedPaths.contains { $0.path == path && $0.reason.contains("credential") })
        }
    }

    @Test("Requires review for malformed, undecodable, and oversized config content")
    func requiresReviewForUncertainContent() throws {
        let temp = try TemporaryDirectory()
        try write("{", to: temp.url.appendingPathComponent("review/malformed.json"))
        try write("not a mapping", to: temp.url.appendingPathComponent("review/unclassified.yaml"))
        try write("not an assignment", to: temp.url.appendingPathComponent("review/unclassified.toml"))
        try write(Data([0xFF, 0xFE, 0xFD]), to: temp.url.appendingPathComponent("review/non-utf8.md"))
        try write(
            Data(repeating: UInt8(ascii: "a"), count: ConfigBackupPlanner.maxContentScanBytes),
            to: temp.url.appendingPathComponent("safe/boundary.md")
        )
        try write(
            Data(repeating: UInt8(ascii: "a"), count: ConfigBackupPlanner.maxContentScanBytes + 1),
            to: temp.url.appendingPathComponent("review/oversized.md")
        )

        let plan = try ConfigBackupPlanner().plan(rootURL: temp.url)

        #expect(plan.includePaths.contains("safe/boundary.md"))
        #expect(Set(plan.reviewRequiredPaths.map(\.path)) == [
            "review/malformed.json",
            "review/non-utf8.md",
            "review/oversized.md",
            "review/unclassified.toml",
            "review/unclassified.yaml"
        ])
        #expect(plan.reviewRequiredPaths.allSatisfy { !$0.reason.contains("{") })
    }

    @Test("Git backup stages review-required files only after exact path approval")
    func commitsReviewRequiredFilesOnlyAfterApproval() throws {
        try #require(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"))
        let temp = try TemporaryDirectory()
        try write("{}", to: temp.url.appendingPathComponent("templates/safe.json"))
        try write("{", to: temp.url.appendingPathComponent("templates/review.json"))
        let manager = ConfigGitBackupManager()

        let safeResult = try manager.commit(rootURL: temp.url, message: "Commit safe config")
        let initiallyTracked = try manager.trackedPaths(rootURL: temp.url)

        #expect(safeResult.didCommit)
        #expect(initiallyTracked.contains("templates/safe.json"))
        #expect(!initiallyTracked.contains("templates/review.json"))

        let reviewedResult = try manager.commit(
            rootURL: temp.url,
            message: "Commit reviewed config",
            approvedReviewPaths: ["templates/review.json"]
        )

        #expect(reviewedResult.didCommit)
        #expect(try manager.trackedPaths(rootURL: temp.url).contains("templates/review.json"))
        #expect(throws: ConfigGitBackupError.invalidReviewApproval("templates/not-reviewed.json")) {
            try manager.commit(
                rootURL: temp.url,
                message: "Reject invalid approval",
                approvedReviewPaths: ["templates/not-reviewed.json"]
            )
        }
    }

    @Test("Git backup rejects unapproved paths already staged in the index")
    func rejectsUnapprovedPreStagedPaths() throws {
        try #require(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"))
        let temp = try TemporaryDirectory()
        let manager = ConfigGitBackupManager()
        _ = try manager.ensureRepository(rootURL: temp.url)
        try write("{}", to: temp.url.appendingPathComponent("templates/safe.json"))
        try write(
            #"{ "authorization": "Bearer dummy-credential-123" }"#,
            to: temp.url.appendingPathComponent("profiles/benign.json")
        )
        try runGit(["add", "--", "profiles/benign.json"], rootURL: temp.url)

        #expect(throws: ConfigGitBackupError.unapprovedStagedPath("profiles/benign.json")) {
            try manager.commit(rootURL: temp.url, message: "Reject staged credential")
        }
    }

    @Test("Git backup initializes a local repository with safe ignore rules")
    func initializesLocalGitBackupRepository() throws {
        try #require(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"))
        let temp = try TemporaryDirectory()

        let status = try ConfigGitBackupManager().ensureRepository(rootURL: temp.url)

        #expect(status.repositoryInitialized)
        #expect(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent(".git").path))
        let gitignore = try String(contentsOf: temp.url.appendingPathComponent(".gitignore"), encoding: .utf8)
        #expect(gitignore.contains("# Digital Meld LessonMeld local config backup"))
        #expect(gitignore.contains("projects/"))
        #expect(gitignore.contains("*token*"))
    }

    @Test("Git backup rejects oversized existing gitignore")
    func rejectsOversizedExistingGitIgnore() throws {
        try #require(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"))
        let temp = try TemporaryDirectory()
        let gitignoreURL = temp.url.appendingPathComponent(".gitignore")
        try Data(repeating: UInt8(ascii: "#"), count: Int(ConfigGitBackupManager.maxGitIgnoreBytes + 1))
            .write(to: gitignoreURL, options: [.atomic])

        #expect(throws: ConfigGitBackupError.gitIgnoreTooLarge(
            gitignoreURL.path,
            byteCount: ConfigGitBackupManager.maxGitIgnoreBytes + 1,
            limit: ConfigGitBackupManager.maxGitIgnoreBytes
        )) {
            try ConfigGitBackupManager().ensureRepository(rootURL: temp.url)
        }
    }

    @Test("Git backup commits only syncable config files")
    func commitsOnlySyncableConfigFiles() throws {
        try #require(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"))
        let temp = try TemporaryDirectory()
        try write("{}", to: temp.url.appendingPathComponent("templates/workshop.json"))
        try write("video", to: temp.url.appendingPathComponent("media/screen.mp4"))
        try write("token", to: temp.url.appendingPathComponent("profiles/github-token.json"))
        let manager = ConfigGitBackupManager()

        let result = try manager.commit(rootURL: temp.url, message: "Backup lesson config")

        #expect(result.didCommit)
        let hash = try #require(result.commitHash)
        #expect(!hash.isEmpty)
        let tracked = try manager.trackedPaths(rootURL: temp.url)
        #expect(tracked.contains(".gitignore"))
        #expect(tracked.contains("templates/workshop.json"))
        #expect(!tracked.contains("media/screen.mp4"))
        #expect(!tracked.contains("profiles/github-token.json"))
    }

    @Test("Git backup commits bypass local hooks")
    func commitsBypassLocalHooks() throws {
        try #require(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"))
        let temp = try TemporaryDirectory()
        let manager = ConfigGitBackupManager()
        _ = try manager.ensureRepository(rootURL: temp.url)
        let hookMarkerURL = temp.url.appendingPathComponent("hook-ran")
        let hookURL = temp.url.appendingPathComponent(".git/hooks/pre-commit")
        try write(
            """
            #!/bin/sh
            echo ran > \(hookMarkerURL.path)
            exit 1
            """,
            to: hookURL
        )
        try makeExecutable(hookURL)
        try write("{}", to: temp.url.appendingPathComponent("templates/workshop.json"))

        let result = try manager.commit(rootURL: temp.url, message: "Backup lesson config")

        #expect(result.didCommit)
        #expect(!FileManager.default.fileExists(atPath: hookMarkerURL.path))
    }

    @Test("Git runner drains large output")
    func gitRunnerDrainsLargeOutput() throws {
        let temp = try TemporaryDirectory()
        let fakeGitURL = temp.url.appendingPathComponent("git")
        try write(
            """
            #!/bin/sh
            /usr/bin/awk 'BEGIN { for (i = 0; i < 50000; i++) print "templates/file" i ".json" }'
            """,
            to: fakeGitURL
        )
        try makeExecutable(fakeGitURL)
        let manager = ConfigGitBackupManager(gitExecutableURL: fakeGitURL)

        let tracked = try manager.trackedPaths(rootURL: temp.url)

        #expect(tracked.count == 50_000)
        #expect(tracked.contains("templates/file49999.json"))
    }

    @Test("Git runner times out stuck commands")
    func gitRunnerTimesOutStuckCommands() throws {
        let temp = try TemporaryDirectory()
        let fakeGitURL = temp.url.appendingPathComponent("git")
        try write(
            """
            #!/bin/sh
            /bin/sleep 5
            """,
            to: fakeGitURL
        )
        try makeExecutable(fakeGitURL)
        let manager = ConfigGitBackupManager(gitExecutableURL: fakeGitURL, processTimeoutSeconds: 0.05)

        #expect(throws: ConfigGitBackupError.gitTimedOut("git ls-files")) {
            try manager.trackedPaths(rootURL: temp.url)
        }
    }

    @Test("Git backup status reports only syncable changed paths")
    func statusReportsOnlySyncableChangedPaths() throws {
        try #require(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"))
        let temp = try TemporaryDirectory()
        let manager = ConfigGitBackupManager()
        _ = try manager.ensureRepository(rootURL: temp.url)
        try write("{}", to: temp.url.appendingPathComponent("templates/workshop.json"))
        try write("token", to: temp.url.appendingPathComponent("profiles/github-token.json"))
        try write("video", to: temp.url.appendingPathComponent("media/screen.mp4"))

        let status = try manager.status(rootURL: temp.url)

        #expect(status.changedPaths.contains(".gitignore"))
        #expect(status.changedPaths.contains("templates/workshop.json"))
        #expect(!status.changedPaths.contains("profiles/github-token.json"))
        #expect(!status.changedPaths.contains("media/screen.mp4"))
    }

    @Test("Excludes symlink escapes from config backups")
    func excludesSymlinkEscapes() throws {
        let temp = try TemporaryDirectory()
        let outside = temp.url.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).json")
        try write("{}", to: outside)
        let symlinkURL = temp.url.appendingPathComponent("templates/outside.json")
        try FileManager.default.createDirectory(at: symlinkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outside)

        let plan = try ConfigBackupPlanner().plan(rootURL: temp.url)

        #expect(!plan.includePaths.contains("templates/outside.json"))
        #expect(plan.excludedPaths.contains {
            $0.path == "templates/outside.json" && $0.reason.contains("Symbolic links")
        })
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func runGit(_ arguments: [String], rootURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootURL.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw POSIXError(.EIO)
        }
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
