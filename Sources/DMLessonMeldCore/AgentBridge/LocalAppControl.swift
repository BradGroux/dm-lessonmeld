import CryptoKit
import Foundation
import LocalAuthentication
import Security

public enum LocalAppControl {
    public static let notificationName = Notification.Name("io.digitalmeld.lessonmeld.app-control")
    public static let notificationObject = "io.digitalmeld.lessonmeld"
    public static let commandMaxAgeSeconds = 60
    static let legacyControlTokenProvenanceMarker = "io.digitalmeld.lessonmeld.local-control-token.v1"

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

    public static var replayCacheURL: URL {
        get throws {
            let directory = try applicationSupportDirectory()
            return directory.appendingPathComponent("local-control-replay-cache.json")
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
        try writeStatus(status, to: try statusURL)
    }

    public static func writeStatus(_ status: LocalAppControlStatus, to outputURL: URL) throws {
        let data = try DMLessonJSON.encoder().encode(status)
        try data.write(to: outputURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
    }

    public static func readStatus() throws -> LocalAppControlStatus {
        let data = try Data(contentsOf: try statusURL)
        return try DMLessonJSON.decoder().decode(LocalAppControlStatus.self, from: data)
    }

    public static func ensureControlToken() throws -> String {
        try ensureControlToken(
            store: KeychainControlTokenStore(),
            legacyTokenURL: try controlTokenURL
        )
    }

    static func ensureControlToken(store: LocalAppControlTokenStore, legacyTokenURL: URL?) throws -> String {
        if let token = try store.readControlToken() {
            try removeLegacyControlToken(at: legacyTokenURL)
            return token
        }

        if let legacyTokenURL,
           FileManager.default.fileExists(atPath: legacyTokenURL.path) {
            if legacyControlTokenHasProvenance(at: legacyTokenURL) {
                let token = try readControlToken(at: legacyTokenURL)
                try store.writeControlToken(token)
                try removeLegacyControlToken(at: legacyTokenURL)
                return token
            }
            try removeLegacyControlToken(at: legacyTokenURL)
        }

        let token = generateControlToken()
        try store.writeControlToken(token)
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

        return authenticatedCommand(
            command,
            token: token,
            replayCacheURL: try? replayCacheURL,
            now: now
        )
    }

    static func authenticatedCommand(
        from userInfo: [AnyHashable: Any]?,
        token: String,
        replayCacheURL: URL,
        now: Date = Date()
    ) -> LocalAppControlCommand? {
        guard let command = LocalAppControlCommand(userInfo: userInfo) else {
            return nil
        }

        return authenticatedCommand(command, token: token, replayCacheURL: replayCacheURL, now: now)
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

    private static func authenticatedCommand(
        _ command: LocalAppControlCommand,
        token: String,
        replayCacheURL: URL?,
        now: Date
    ) -> LocalAppControlCommand? {
        guard isAuthentic(command, token: token, now: now),
              let replayCacheURL,
              (try? consumeReplayNonce(command.nonce, issuedAt: command.issuedAt, now: now, cacheURL: replayCacheURL)) == true else {
            return nil
        }

        return command
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

    private static func removeLegacyControlToken(at url: URL?) throws {
        guard let url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let provenanceURL = legacyControlTokenProvenanceURL(for: url)
        if FileManager.default.fileExists(atPath: provenanceURL.path) {
            try FileManager.default.removeItem(at: provenanceURL)
        }
    }

    static func writeLegacyControlTokenProvenance(for legacyTokenURL: URL) throws {
        try Data("\(legacyControlTokenProvenanceMarker)\n".utf8)
            .write(to: legacyControlTokenProvenanceURL(for: legacyTokenURL), options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: legacyControlTokenProvenanceURL(for: legacyTokenURL).path
        )
    }

    private static func legacyControlTokenHasProvenance(at url: URL) -> Bool {
        let provenanceURL = legacyControlTokenProvenanceURL(for: url)
        guard let marker = try? String(contentsOf: provenanceURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return marker == legacyControlTokenProvenanceMarker
    }

    static func legacyControlTokenProvenanceURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).provenance")
    }

    static func consumeReplayNonce(_ nonce: String, issuedAt: Int, now: Date = Date(), cacheURL: URL) throws -> Bool {
        let nowSeconds = Int(now.timeIntervalSince1970.rounded(.down))
        let oldestAllowed = nowSeconds - commandMaxAgeSeconds
        var cache = try loadReplayCache(from: cacheURL)
        cache.nonces = cache.nonces.filter { $0.value >= oldestAllowed }

        guard cache.nonces[nonce] == nil else {
            try writeReplayCache(cache, to: cacheURL)
            return false
        }

        cache.nonces[nonce] = issuedAt
        try writeReplayCache(cache, to: cacheURL)
        return true
    }

    private static func loadReplayCache(from url: URL) throws -> LocalAppControlReplayCache {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LocalAppControlReplayCache()
        }
        let data = try Data(contentsOf: url)
        return try DMLessonJSON.decoder().decode(LocalAppControlReplayCache.self, from: data)
    }

    private static func writeReplayCache(_ cache: LocalAppControlReplayCache, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try DMLessonJSON.encoder().encode(cache)
        try data.write(to: url, options: [.atomic])
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

struct LocalAppControlReplayCache: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var nonces: [String: Int]

    init(schemaVersion: Int = 1, nonces: [String: Int] = [:]) {
        self.schemaVersion = schemaVersion
        self.nonces = nonces
    }
}

protocol LocalAppControlTokenStore: Sendable {
    func readControlToken() throws -> String?
    func writeControlToken(_ token: String) throws
}

struct KeychainControlTokenStore: LocalAppControlTokenStore {
    private let service = "io.digitalmeld.lessonmeld.local-app-control"
    private let account = "control-token"

    func readControlToken() throws -> String? {
        var query = keychainQuery(failAuthenticationUI: true)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            throw LocalAppControlError.keychainNeedsUserInteraction(status)
        }
        guard status == errSecSuccess else {
            throw LocalAppControlError.keychainReadFailed(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw LocalAppControlError.emptyControlToken
        }
        return token
    }

    func writeControlToken(_ token: String) throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalAppControlError.emptyControlToken
        }

        let data = Data(token.utf8)
        let updateStatus = SecItemUpdate(
            keychainQuery(failAuthenticationUI: true) as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecInteractionNotAllowed || updateStatus == errSecAuthFailed {
            throw LocalAppControlError.keychainNeedsUserInteraction(updateStatus)
        }
        if updateStatus != errSecItemNotFound {
            throw LocalAppControlError.keychainWriteFailed(updateStatus)
        }

        var addQuery = keychainQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw LocalAppControlError.keychainWriteFailed(addStatus)
        }
    }

    private func keychainQuery(failAuthenticationUI: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if failAuthenticationUI {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
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

public enum LocalAppControlError: Error, Equatable, LocalizedError {
    case emptyControlToken
    case keychainNeedsUserInteraction(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .emptyControlToken:
            "Local app-control token is empty."
        case .keychainNeedsUserInteraction(let status):
            "Local app-control token needs Keychain user interaction (OSStatus \(status))."
        case .keychainReadFailed(let status):
            "Could not read local app-control token from Keychain (OSStatus \(status))."
        case .keychainWriteFailed(let status):
            "Could not write local app-control token to Keychain (OSStatus \(status))."
        }
    }
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

    public func redactedForAutomation() -> LocalAppControlStatus {
        LocalAppControlStatus(
            schemaVersion: schemaVersion,
            pid: pid,
            updatedAt: updatedAt,
            isAppRunning: isAppRunning,
            isRecording: isRecording,
            isPaused: isPaused,
            isStopping: isStopping,
            elapsedSeconds: elapsedSeconds,
            lastProjectPath: SafePathDisplay.basename(lastProjectPath),
            message: SafePathDisplay.redactingAbsolutePaths(in: message)
        )
    }
}
