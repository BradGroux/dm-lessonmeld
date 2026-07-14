import Foundation

enum ConfigBackupContentClassification: Equatable, Sendable {
    case safe
    case credentialBearing(reason: String)
    case reviewRequired(reason: String)
}

struct ConfigBackupContentPolicy: Sendable {
    static let credentialReason = "Potential credential material must stay out of Git sync."
    static let oversizedReason = "Content exceeds the complete-inspection limit and requires explicit review."
    static let undecodableReason = "Content is not valid UTF-8 and requires explicit review."
    static let unclassifiedReason = "Content could not be classified confidently and requires explicit review."

    let maxContentScanBytes: Int64

    init(maxContentScanBytes: Int64) {
        self.maxContentScanBytes = maxContentScanBytes
    }

    func classify(url: URL) throws -> ConfigBackupContentClassification {
        let data: Data
        do {
            data = try TrustedFileAccess.readData(from: url, maxBytes: maxContentScanBytes)
        } catch TrustedFileAccessError.tooLarge {
            return .reviewRequired(reason: Self.oversizedReason)
        } catch TrustedFileAccessError.notRegularFile {
            return .reviewRequired(reason: Self.unclassifiedReason)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            return .reviewRequired(reason: Self.undecodableReason)
        }
        if containsCredentialMaterial(content) {
            return .credentialBearing(reason: Self.credentialReason)
        }

        switch url.pathExtension.lowercased() {
        case "json":
            return classifyJSON(data)
        case "yaml", "yml":
            return linesAreClassifiable(content, format: .yaml)
                ? .safe
                : .reviewRequired(reason: Self.unclassifiedReason)
        case "toml":
            return linesAreClassifiable(content, format: .toml)
                ? .safe
                : .reviewRequired(reason: Self.unclassifiedReason)
        case "md":
            return .safe
        default:
            return .reviewRequired(reason: Self.unclassifiedReason)
        }
    }

    private func classifyJSON(_ data: Data) -> ConfigBackupContentClassification {
        do {
            let value = try JSONSerialization.jsonObject(with: data)
            return jsonContainsCredentialMaterial(value)
                ? .credentialBearing(reason: Self.credentialReason)
                : .safe
        } catch {
            return .reviewRequired(reason: Self.unclassifiedReason)
        }
    }

    private func jsonContainsCredentialMaterial(_ value: Any) -> Bool {
        if let object = value as? [String: Any] {
            for (key, child) in object {
                if isSensitiveKey(key), hasCredentialValue(child) {
                    return true
                }
                if jsonContainsCredentialMaterial(child) {
                    return true
                }
            }
            return false
        }
        if let array = value as? [Any] {
            return array.contains(where: jsonContainsCredentialMaterial)
        }
        return false
    }

    private func hasCredentialValue(_ value: Any) -> Bool {
        if value is NSNull { return false }
        if let boolean = value as? Bool { return boolean }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count >= 6 && !["null", "false", "true"].contains(trimmed.lowercased())
        }
        if let array = value as? [Any] { return !array.isEmpty }
        if let object = value as? [String: Any] { return !object.isEmpty }
        return true
    }

    private func containsCredentialMaterial(_ content: String) -> Bool {
        let lowered = content.lowercased()
        let secretMarkers = [
            "-----begin private key-----",
            "-----begin rsa private key-----",
            "-----begin openssh private key-----",
            "aws_secret_access_key",
            "github_token",
            "github_pat_",
            "ghp_",
            "gho_",
            "ghu_",
            "ghs_",
            "ghr_",
            "glpat-",
            "slack_bot_token",
            "xoxb-",
            "xoxp-",
            "xapp-",
            "sk_live_",
            "sk_test_",
            "sk-proj-",
            "npm_"
        ]
        if secretMarkers.contains(where: lowered.contains) || containsBearerCredential(lowered) {
            return true
        }

        for rawLine in lowered.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if sensitiveKeys.contains(where: { lineContainsSensitiveAssignment(line, key: $0) }) {
                return true
            }
        }
        return false
    }

    private func containsBearerCredential(_ content: String) -> Bool {
        var searchStart = content.startIndex
        while searchStart < content.endIndex,
              let marker = content.range(of: "bearer ", range: searchStart..<content.endIndex) {
            let suffix = content[marker.upperBound...]
            let rawToken = suffix.prefix { !$0.isWhitespace }
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,;:!?)]}"))
            if token.count >= 6,
               token.contains(where: { $0.isNumber || "_-.~+/=".contains($0) }) {
                return true
            }
            searchStart = marker.upperBound
        }
        return false
    }

    private enum StructuredTextFormat {
        case yaml
        case toml
    }

    private func linesAreClassifiable(_ content: String, format: StructuredTextFormat) -> Bool {
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            switch format {
            case .yaml:
                if line == "---" || line == "..." || line == "{}" || line == "[]"
                    || line.hasPrefix("-") || line.contains(":") {
                    continue
                }
            case .toml:
                if (line.hasPrefix("[") && line.hasSuffix("]")) || line.contains("=") {
                    continue
                }
            }
            return false
        }
        return true
    }

    private var sensitiveKeys: [String] {
        [
            "access_key",
            "access-key",
            "accesskey",
            "access_token",
            "accesstoken",
            "account_key",
            "account-key",
            "accountkey",
            "api_key",
            "api-key",
            "apikey",
            "auth_token",
            "authtoken",
            "authorization",
            "client_secret",
            "clientsecret",
            "connection_string",
            "connection-string",
            "connectionstring",
            "passwd",
            "password",
            "private_key",
            "private-key",
            "privatekey",
            "proxy_authorization",
            "proxyauthorization",
            "refresh_token",
            "refreshtoken",
            "secret",
            "session_token",
            "sessiontoken",
            "shared_access_key",
            "sharedaccesskey",
            "token"
        ]
    }

    private func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter(\.isLetter)
        return sensitiveKeys.contains { candidate in
            candidate.filter(\.isLetter) == normalized
        }
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
