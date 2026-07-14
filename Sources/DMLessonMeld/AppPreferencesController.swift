import AppKit
import DMLessonMeldCore
import Foundation

@MainActor
final class AppPreferencesController: ObservableObject {
    @Published private(set) var snapshot: LessonMeldPreferences
    @Published var didPresentOnboardingThisLaunch = false
    @Published var didApplyLaunchPreferences = false
    @Published private(set) var launchDiagnostics: LaunchDiagnostics
    @Published private(set) var previousExitWasClean: Bool

    private let defaults: UserDefaults
    private let key = "io.digitalmeld.dm-lessonmeld.preferences"
    private let launchStateKey = "io.digitalmeld.dm-lessonmeld.launchState"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(LessonMeldPreferences.self, from: data) {
            snapshot = decoded.normalized()
        } else {
            snapshot = LessonMeldPreferences()
        }
        let diagnostics = Self.loadLaunchDiagnostics(defaults: defaults, key: launchStateKey)
        launchDiagnostics = diagnostics
        previousExitWasClean = diagnostics.lastExitWasClean
        markLaunch()
    }

    var shouldShowOnboardingAtLaunch: Bool {
        !snapshot.onboardingCompleted && !didPresentOnboardingThisLaunch
    }

    var shouldUseRecoveryLaunch: Bool {
        !previousExitWasClean || launchDiagnostics.safeMode
    }

    func update(_ mutate: (inout LessonMeldPreferences) -> Void) {
        var next = snapshot
        mutate(&next)
        replace(with: next)
    }

    func replace(with preferences: LessonMeldPreferences) {
        snapshot = preferences.normalized()
        save()
    }

    func completeOnboarding() {
        update { preferences in
            preferences.firstRunCompletedAt = Date()
        }
    }

    func reset() {
        snapshot = LessonMeldPreferences()
        save()
    }

    func markCleanTermination() {
        launchDiagnostics.lastExitWasClean = true
        launchDiagnostics.lastCleanExitAt = Date()
        saveLaunchDiagnostics()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    private func markLaunch() {
        launchDiagnostics.launchCount += 1
        launchDiagnostics.lastLaunchAt = Date()
        launchDiagnostics.safeMode = ProcessInfo.processInfo.arguments.contains("--safe-mode")
        saveLaunchDiagnostics()
        launchDiagnostics.lastExitWasClean = false
        saveLaunchDiagnostics()
    }

    private func saveLaunchDiagnostics() {
        guard let data = try? JSONEncoder().encode(launchDiagnostics) else { return }
        defaults.set(data, forKey: launchStateKey)
    }

    private static func loadLaunchDiagnostics(defaults: UserDefaults, key: String) -> LaunchDiagnostics {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(LaunchDiagnostics.self, from: data) else {
            return LaunchDiagnostics()
        }
        return decoded
    }
}

struct LaunchDiagnostics: Codable, Equatable {
    var launchCount: Int
    var lastLaunchAt: Date?
    var lastCleanExitAt: Date?
    var lastExitWasClean: Bool
    var safeMode: Bool

    init(
        launchCount: Int = 0,
        lastLaunchAt: Date? = nil,
        lastCleanExitAt: Date? = nil,
        lastExitWasClean: Bool = true,
        safeMode: Bool = false
    ) {
        self.launchCount = launchCount
        self.lastLaunchAt = lastLaunchAt
        self.lastCleanExitAt = lastCleanExitAt
        self.lastExitWasClean = lastExitWasClean
        self.safeMode = safeMode
    }
}
