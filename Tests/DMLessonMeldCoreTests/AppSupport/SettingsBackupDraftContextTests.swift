import DMLessonMeldCore
import DMLessonMeldSupport
import Foundation
import Testing

@Suite("Settings backup draft context")
struct SettingsBackupDraftContextTests {
    @Test("Visible draft controls backup enablement root and JSON")
    func visibleDraftControlsEveryBackupInput() throws {
        var saved = LessonMeldPreferences()
        saved.privacy.allowGitBackupsForSettings = false
        saved.privacy.configBackupRootPath = "/tmp/saved-settings-backup"
        saved.general.defaultTemplateID = "saved-template"

        var draft = saved
        draft.privacy.allowGitBackupsForSettings = true
        draft.privacy.configBackupRootPath = "/tmp/visible-draft-backup"
        draft.general.defaultTemplateID = "draft-template"

        let context = SettingsBackupDraftContext(preferences: draft)
        let encoded = try context.encodedPreferences()
        let decoded = try DMLessonJSON.decoder().decode(LessonMeldPreferences.self, from: encoded)

        #expect(context.isEnabled)
        #expect(context.rootURL.standardizedFileURL.path == "/tmp/visible-draft-backup")
        #expect(decoded == draft.normalized())
        #expect(decoded != saved.normalized())
    }
}
