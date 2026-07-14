import DMLessonMeldSupport
import Testing

@Suite("Main window launch policy")
struct MainWindowLaunchPolicyTests {
    @Test("Enabled preference presents the main window at launch")
    func enabledPreferencePresentsMainWindow() {
        #expect(MainWindowLaunchPolicy.action(
            showMainWindowAtLaunch: true
        ) == .present)
    }

    @Test("Disabled preference suppresses only automatic presentation")
    func disabledPreferenceSuppressesAutomaticPresentation() {
        #expect(MainWindowLaunchPolicy.action(
            showMainWindowAtLaunch: false
        ) == .suppress)
    }
}
