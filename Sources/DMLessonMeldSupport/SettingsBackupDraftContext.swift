import DMLessonMeldCore
import Foundation

public struct SettingsBackupDraftContext: Equatable, Sendable {
    public let preferences: LessonMeldPreferences

    public init(preferences: LessonMeldPreferences) {
        self.preferences = preferences.normalized()
    }

    public var isEnabled: Bool {
        preferences.privacy.allowGitBackupsForSettings
    }

    public var rootURL: URL {
        let expanded = NSString(string: preferences.privacy.configBackupRootPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    public func encodedPreferences() throws -> Data {
        try DMLessonJSON.encoder().encode(preferences)
    }
}
