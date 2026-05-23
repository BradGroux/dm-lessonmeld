import Foundation

public enum SafePathDisplay {
    public static func basename(_ path: String?) -> String? {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return basename(path)
    }

    public static func basename(_ path: String) -> String {
        let lastComponent = URL(fileURLWithPath: path).lastPathComponent
        return lastComponent.isEmpty ? path : lastComponent
    }

    public static func projectRelativeOrBasename(_ path: String?, projectPath: String?) -> String? {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard path.hasPrefix("/") else {
            return path
        }
        guard let projectPath, !projectPath.isEmpty else {
            return basename(path)
        }

        let project = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let file = URL(fileURLWithPath: path).standardizedFileURL.path
        if file == project {
            return basename(project)
        }
        if file.hasPrefix(project + "/") {
            return String(file.dropFirst(project.count + 1))
        }
        return basename(file)
    }

    public static func redactingAbsolutePaths(in message: String) -> String {
        let pattern = #"(?<![:A-Za-z0-9._-])/(?:[^/\s:]+/)+[^\s,;:)\]}]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return message
        }

        var redacted = message
        let fullRange = NSRange(message.startIndex..<message.endIndex, in: message)
        let matches = regex.matches(in: message, range: fullRange)
        for match in matches.reversed() {
            guard let range = Range(match.range, in: redacted) else { continue }
            var path = String(redacted[range])
            var suffix = ""
            while let last = path.last, ".!?".contains(last) {
                suffix.insert(last, at: suffix.startIndex)
                path.removeLast()
            }
            redacted.replaceSubrange(range, with: basename(path) + suffix)
        }
        return redacted
    }
}
