import DMLessonMeldCore
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
}
