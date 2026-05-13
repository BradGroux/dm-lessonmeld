import CryptoKit
import Foundation

public enum LocalAppControl {
    public static let notificationName = Notification.Name("io.digitalmeld.lessonmeld.app-control")
    public static let notificationObject = "io.digitalmeld.lessonmeld"
    public static let commandMaxAgeSeconds = 60

    public static var statusURL: URL {
        get throws {
            let directory = try applicationSupportDirectory()
            return directory.appendingPathComponent("runtime-status.json")
        }
    }

    public static var controlTokenURL: URL {
        get throws {
            let directory = try applicationSupportDirectory()
            return directory.appendingPathComponent("local-control-token")
        }
    }

    public static func applicationSupportDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("DMLessonMeld", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func writeStatus(_ status: LocalAppControlStatus) throws {
        let outputURL = try statusURL
        let data = try DMLessonJSON.encoder().encode(status)
        try data.write(to: outputURL, options: [.atomic])
    }

    public static func readStatus() throws -> LocalAppControlStatus {
        let data = try Data(contentsOf: try statusURL)
        return try DMLessonJSON.decoder().decode(LocalAppControlStatus.self, from: data)
    }

    public static func ensureControlToken() throws -> String {
        let tokenURL = try controlTokenURL
        if FileManager.default.fileExists(atPath: tokenURL.path) {
            return try readControlToken(at: tokenURL)
        }

        let token = generateControlToken()
        try writeControlToken(token, to: tokenURL)
        return token
    }

    public static func controlUserInfo(for action: LocalAppControlAction, issuedAt: Date = Date()) throws -> [String: Any] {
        let token = try ensureControlToken()
        let command = signedCommand(action: action, token: token, issuedAt: issuedAt)
        return command.userInfo
    }

    public static func authenticatedCommand(from userInfo: [AnyHashable: Any]?, now: Date = Date()) -> LocalAppControlCommand? {
        guard let command = LocalAppControlCommand(userInfo: userInfo),
              let token = try? ensureControlToken() else {
            return nil
        }

        return isAuthentic(command, token: token, now: now) ? command : nil
    }

    public static func signedCommand(
        action: LocalAppControlAction,
        token: String,
        nonce: String = UUID().uuidString,
        issuedAt: Date = Date()
    ) -> LocalAppControlCommand {
        let issuedAtSeconds = Int(issuedAt.timeIntervalSince1970.rounded(.down))
        return LocalAppControlCommand(
            action: action,
            nonce: nonce,
            issuedAt: issuedAtSeconds,
            signature: signature(action: action, nonce: nonce, issuedAt: issuedAtSeconds, token: token)
        )
    }

    public static func isAuthentic(_ command: LocalAppControlCommand, token: String, now: Date = Date()) -> Bool {
        guard abs(now.timeIntervalSince1970 - TimeInterval(command.issuedAt)) <= TimeInterval(commandMaxAgeSeconds) else {
            return false
        }

        let expectedSignature = signature(
            action: command.action,
            nonce: command.nonce,
            issuedAt: command.issuedAt,
            token: token
        )
        return constantTimeEqual(command.signature, expectedSignature)
    }

    private static func readControlToken(at url: URL) throws -> String {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let token = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw LocalAppControlError.emptyControlToken
        }
        return token
    }

    private static func writeControlToken(_ token: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((token + "\n").utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func generateControlToken() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    private static func signature(action: LocalAppControlAction, nonce: String, issuedAt: Int, token: String) -> String {
        let payload = "\(action.rawValue)\n\(nonce)\n\(issuedAt)"
        let key = SymmetricKey(data: Data(token.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(code).base64EncodedString()
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        let maxCount = max(left.count, right.count)
        var difference = left.count ^ right.count

        for index in 0..<maxCount {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= Int(leftByte ^ rightByte)
        }

        return difference == 0
    }
}

public enum LocalAppControlAction: String, Codable, CaseIterable, Sendable {
    case showControls
    case start
    case pause
    case resume
    case togglePause
    case stop
    case status
}

public struct LocalAppControlCommand: Codable, Equatable, Sendable {
    public var action: LocalAppControlAction
    public var nonce: String
    public var issuedAt: Int
    public var signature: String

    public init(action: LocalAppControlAction, nonce: String, issuedAt: Int, signature: String) {
        self.action = action
        self.nonce = nonce
        self.issuedAt = issuedAt
        self.signature = signature
    }

    public var userInfo: [String: Any] {
        [
            "action": action.rawValue,
            "nonce": nonce,
            "issuedAt": issuedAt,
            "signature": signature
        ]
    }

    public init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              let actionValue = userInfo["action"] as? String,
              let action = LocalAppControlAction(rawValue: actionValue),
              let nonce = userInfo["nonce"] as? String,
              !nonce.isEmpty,
              let issuedAt = Self.intValue(userInfo["issuedAt"]),
              let signature = userInfo["signature"] as? String,
              !signature.isEmpty else {
            return nil
        }

        self.init(action: action, nonce: nonce, issuedAt: issuedAt, signature: signature)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }
}

public enum LocalAppControlError: Error, Equatable {
    case emptyControlToken
}

public struct LocalAppControlStatus: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var pid: Int32
    public var updatedAt: Date
    public var isAppRunning: Bool
    public var isRecording: Bool
    public var isPaused: Bool
    public var isStopping: Bool
    public var elapsedSeconds: Double
    public var lastProjectPath: String?
    public var message: String

    public init(
        schemaVersion: Int = 1,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        updatedAt: Date = Date(),
        isAppRunning: Bool = true,
        isRecording: Bool,
        isPaused: Bool,
        isStopping: Bool,
        elapsedSeconds: Double,
        lastProjectPath: String?,
        message: String
    ) {
        self.schemaVersion = schemaVersion
        self.pid = pid
        self.updatedAt = updatedAt
        self.isAppRunning = isAppRunning
        self.isRecording = isRecording
        self.isPaused = isPaused
        self.isStopping = isStopping
        self.elapsedSeconds = elapsedSeconds
        self.lastProjectPath = lastProjectPath
        self.message = message
    }

    public var stateLabel: String {
        if isStopping {
            return "stopping"
        }
        if isPaused {
            return "paused"
        }
        if isRecording {
            return "recording"
        }
        return "idle"
    }
}
