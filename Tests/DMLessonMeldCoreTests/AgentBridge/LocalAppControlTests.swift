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

    @Test("Oversized local app control payload fields are rejected")
    func oversizedPayloadFieldsAreRejected() {
        let issuedAt = Date(timeIntervalSince1970: 1_779_000_000)
        let command = LocalAppControl.signedCommand(
            action: .start,
            token: "test-token",
            nonce: "nonce-1",
            issuedAt: issuedAt
        )

        var oversizedNonce = command.userInfo
        oversizedNonce["nonce"] = String(repeating: "a", count: LocalAppControl.maxCommandNonceBytes + 1)
        var oversizedSignature = command.userInfo
        oversizedSignature["signature"] = String(repeating: "a", count: LocalAppControl.maxCommandSignatureBytes + 1)
        var oversizedIssuedAt = command.userInfo
        oversizedIssuedAt["issuedAt"] = String(repeating: "1", count: LocalAppControl.maxIssuedAtStringBytes + 1)

        #expect(LocalAppControlCommand(userInfo: oversizedNonce) == nil)
        #expect(LocalAppControlCommand(userInfo: oversizedSignature) == nil)
        #expect(LocalAppControlCommand(userInfo: oversizedIssuedAt) == nil)
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

    @Test("Replay cache rejects oversized files")
    func replayCacheRejectsOversizedFiles() throws {
        let temp = try TemporaryDirectory()
        let replayCacheURL = temp.url.appendingPathComponent("replay-cache.json")
        try Data(repeating: UInt8(ascii: "{"), count: Int(LocalAppControl.maxReplayCacheBytes + 1))
            .write(to: replayCacheURL)

        #expect(throws: LocalAppControlError.runtimeFileTooLarge(
            "replay cache",
            byteCount: LocalAppControl.maxReplayCacheBytes + 1,
            limit: LocalAppControl.maxReplayCacheBytes
        )) {
            try LocalAppControl.consumeReplayNonce(
                "nonce",
                issuedAt: 1_779_000_000,
                now: Date(timeIntervalSince1970: 1_779_000_000),
                cacheURL: replayCacheURL
            )
        }
    }

    @Test("Replay cache keeps the newest bounded nonce set")
    func replayCacheKeepsNewestBoundedNonceSet() throws {
        let temp = try TemporaryDirectory()
        let replayCacheURL = temp.url.appendingPathComponent("replay-cache.json")
        let issuedAt = 1_779_000_000
        let oldNonces = Dictionary(uniqueKeysWithValues: (0..<(LocalAppControl.maxReplayCacheNonces + 25)).map { index in
            ("old-\(index)", issuedAt - 1)
        })
        try DMLessonJSON.encoder()
            .encode(LocalAppControlReplayCache(nonces: oldNonces))
            .write(to: replayCacheURL)

        let accepted = try LocalAppControl.consumeReplayNonce(
            "new",
            issuedAt: issuedAt,
            now: Date(timeIntervalSince1970: TimeInterval(issuedAt)),
            cacheURL: replayCacheURL
        )
        let data = try Data(contentsOf: replayCacheURL)
        let cache = try DMLessonJSON.decoder().decode(LocalAppControlReplayCache.self, from: data)

        #expect(accepted)
        #expect(cache.nonces.count == LocalAppControl.maxReplayCacheNonces)
        #expect(cache.nonces["new"] == issuedAt)
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

    @Test("Oversized legacy tokens are not migrated")
    func oversizedLegacyTokensAreNotMigrated() throws {
        let temp = try TemporaryDirectory()
        let legacyTokenURL = temp.url.appendingPathComponent("local-control-token")
        try Data(repeating: UInt8(ascii: "a"), count: Int(LocalAppControl.maxLegacyControlTokenBytes + 1))
            .write(to: legacyTokenURL)
        try LocalAppControl.writeLegacyControlTokenProvenance(for: legacyTokenURL)
        let store = InMemoryTokenStore()

        let token = try LocalAppControl.ensureControlToken(store: store, legacyTokenURL: legacyTokenURL)

        #expect(!token.isEmpty)
        #expect(token != String(repeating: "a", count: Int(LocalAppControl.maxLegacyControlTokenBytes + 1)))
        #expect(store.token == token)
        #expect(!FileManager.default.fileExists(atPath: legacyTokenURL.path))
        #expect(!FileManager.default.fileExists(atPath: LocalAppControl.legacyControlTokenProvenanceURL(for: legacyTokenURL).path))
    }

    @Test("Oversized legacy provenance is ignored")
    func oversizedLegacyProvenanceIsIgnored() throws {
        let temp = try TemporaryDirectory()
        let legacyTokenURL = temp.url.appendingPathComponent("local-control-token")
        let provenanceURL = LocalAppControl.legacyControlTokenProvenanceURL(for: legacyTokenURL)
        try Data("attacker-token\n".utf8).write(to: legacyTokenURL)
        try Data(repeating: UInt8(ascii: "a"), count: Int(LocalAppControl.maxLegacyControlTokenProvenanceBytes + 1))
            .write(to: provenanceURL)
        let store = InMemoryTokenStore()

        let token = try LocalAppControl.ensureControlToken(store: store, legacyTokenURL: legacyTokenURL)

        #expect(token != "attacker-token")
        #expect(store.token == token)
        #expect(!FileManager.default.fileExists(atPath: legacyTokenURL.path))
        #expect(!FileManager.default.fileExists(atPath: provenanceURL.path))
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

    @Test("Runtime status rejects oversized files")
    func runtimeStatusRejectsOversizedFiles() throws {
        let temp = try TemporaryDirectory()
        let statusURL = temp.url.appendingPathComponent("runtime-status.json")
        try Data(repeating: UInt8(ascii: "{"), count: Int(LocalAppControl.maxRuntimeStatusBytes + 1))
            .write(to: statusURL)

        #expect(throws: LocalAppControlError.runtimeFileTooLarge(
            "runtime status",
            byteCount: LocalAppControl.maxRuntimeStatusBytes + 1,
            limit: LocalAppControl.maxRuntimeStatusBytes
        )) {
            try LocalAppControl.readStatus(from: statusURL)
        }
    }

    @Test("Runtime status redaction hides absolute project paths")
    func runtimeStatusRedactionHidesAbsoluteProjectPaths() {
        let status = LocalAppControlStatus(
            isRecording: false,
            isPaused: false,
            isStopping: false,
            elapsedSeconds: 0,
            lastProjectPath: "/Users/example/Client/Lesson.dmlm",
            message: "Rendered /Users/example/Client/Lesson.dmlm/Exports/final.mp4."
        ).redactedForAutomation()

        #expect(status.lastProjectPath == "Lesson.dmlm")
        #expect(status.message == "Rendered final.mp4.")
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
