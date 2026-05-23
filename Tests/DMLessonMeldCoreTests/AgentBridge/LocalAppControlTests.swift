@testable import DMLessonMeldCore
import Foundation
import Testing

@Suite("Local app control")
struct LocalAppControlTests {
    @Test("Signed commands round trip through notification userInfo")
    func signedCommandRoundTrip() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_779_000_000)
        let command = LocalAppControl.signedCommand(
            action: .start,
            token: "test-token",
            nonce: "nonce-1",
            issuedAt: issuedAt
        )

        let decoded = try #require(LocalAppControlCommand(userInfo: command.userInfo))

        #expect(decoded == command)
        #expect(LocalAppControl.isAuthentic(decoded, token: "test-token", now: issuedAt))
    }

    @Test("Tampered local app control commands are rejected")
    func tamperedCommandsAreRejected() {
        let issuedAt = Date(timeIntervalSince1970: 1_779_000_000)
        let command = LocalAppControl.signedCommand(
            action: .start,
            token: "test-token",
            nonce: "nonce-1",
            issuedAt: issuedAt
        )
        let tampered = LocalAppControlCommand(
            action: .stop,
            nonce: command.nonce,
            issuedAt: command.issuedAt,
            signature: command.signature
        )

        #expect(LocalAppControl.isAuthentic(tampered, token: "test-token", now: issuedAt) == false)
        #expect(LocalAppControl.isAuthentic(command, token: "wrong-token", now: issuedAt) == false)
    }

    @Test("Expired local app control commands are rejected")
    func expiredCommandsAreRejected() {
        let issuedAt = Date(timeIntervalSince1970: 1_779_000_000)
        let command = LocalAppControl.signedCommand(
            action: .start,
            token: "test-token",
            nonce: "nonce-1",
            issuedAt: issuedAt
        )

        #expect(LocalAppControl.isAuthentic(command, token: "test-token", now: issuedAt.addingTimeInterval(61)) == false)
    }

    @Test("Authenticated app control commands reject nonce replays")
    func authenticatedCommandsRejectNonceReplays() throws {
        let temp = try TemporaryDirectory()
        let issuedAt = Date(timeIntervalSince1970: 1_779_000_000)
        let command = LocalAppControl.signedCommand(
            action: .start,
            token: "test-token",
            nonce: "nonce-1",
            issuedAt: issuedAt
        )
        let replayCacheURL = temp.url.appendingPathComponent("replay-cache.json")

        let first = LocalAppControl.authenticatedCommand(
            from: command.userInfo,
            token: "test-token",
            replayCacheURL: replayCacheURL,
            now: issuedAt
        )
        let second = LocalAppControl.authenticatedCommand(
            from: command.userInfo,
            token: "test-token",
            replayCacheURL: replayCacheURL,
            now: issuedAt
        )

        #expect(first == command)
        #expect(second == nil)
        let permissions = try #require(FileManager.default.attributesOfItem(atPath: replayCacheURL.path)[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test("Keychain token migration removes legacy plaintext token")
    func keychainTokenMigrationRemovesLegacyPlaintextToken() throws {
        let temp = try TemporaryDirectory()
        let legacyTokenURL = temp.url.appendingPathComponent("local-control-token")
        try Data("legacy-token\n".utf8).write(to: legacyTokenURL)
        try LocalAppControl.writeLegacyControlTokenProvenance(for: legacyTokenURL)
        let store = InMemoryTokenStore()

        let token = try LocalAppControl.ensureControlToken(store: store, legacyTokenURL: legacyTokenURL)

        #expect(token == "legacy-token")
        #expect(store.token == "legacy-token")
        #expect(!FileManager.default.fileExists(atPath: legacyTokenURL.path))
        #expect(!FileManager.default.fileExists(atPath: LocalAppControl.legacyControlTokenProvenanceURL(for: legacyTokenURL).path))
    }

    @Test("Pre-created legacy tokens without provenance are rejected")
    func precreatedLegacyTokenWithoutProvenanceIsRejected() throws {
        let temp = try TemporaryDirectory()
        let legacyTokenURL = temp.url.appendingPathComponent("local-control-token")
        try Data("attacker-token\n".utf8).write(to: legacyTokenURL)
        let store = InMemoryTokenStore()

        let token = try LocalAppControl.ensureControlToken(store: store, legacyTokenURL: legacyTokenURL)

        #expect(!token.isEmpty)
        #expect(token != "attacker-token")
        #expect(store.token == token)
        #expect(!FileManager.default.fileExists(atPath: legacyTokenURL.path))
        #expect(!FileManager.default.fileExists(atPath: LocalAppControl.legacyControlTokenProvenanceURL(for: legacyTokenURL).path))
    }

    @Test("New control tokens are stored without creating legacy plaintext files")
    func newControlTokensSkipLegacyPlaintextFiles() throws {
        let temp = try TemporaryDirectory()
        let legacyTokenURL = temp.url.appendingPathComponent("local-control-token")
        let store = InMemoryTokenStore()

        let token = try LocalAppControl.ensureControlToken(store: store, legacyTokenURL: legacyTokenURL)

        #expect(!token.isEmpty)
        #expect(store.token == token)
        #expect(!FileManager.default.fileExists(atPath: legacyTokenURL.path))
    }

    @Test("Status files are owner-readable only")
    func statusFilesArePrivate() throws {
        let temp = try TemporaryDirectory()
        let statusURL = temp.url.appendingPathComponent("runtime-status.json")
        try LocalAppControl.writeStatus(
            LocalAppControlStatus(
                isRecording: false,
                isPaused: false,
                isStopping: false,
                elapsedSeconds: 0,
                lastProjectPath: "/Users/example/Movies/DMLessonMeld/private.dmlm",
                message: "Idle"
            ),
            to: statusURL
        )

        let permissions = try #require(FileManager.default.attributesOfItem(atPath: statusURL.path)[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
    }
}

private final class InMemoryTokenStore: LocalAppControlTokenStore, @unchecked Sendable {
    var token: String?

    func readControlToken() throws -> String? {
        token
    }

    func writeControlToken(_ token: String) throws {
        self.token = token
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
