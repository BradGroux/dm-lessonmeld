import Foundation

enum AppMetadata {
    static var version: String {
        bundleString("CFBundleShortVersionString") ?? "development"
    }

    static var build: String {
        bundleString("CFBundleVersion") ?? "local"
    }

    static var versionBuildText: String {
        "Version \(version) (\(build))"
    }

    static var bundleIdentifier: String {
        bundleString("CFBundleIdentifier") ?? "io.digitalmeld.dm-lessonmeld"
    }

    static var copyright: String {
        bundleString("NSHumanReadableCopyright") ?? "Copyright (c) 2026 Digital Meld. MIT licensed."
    }

    static let releaseNotesURL = URL(string: "https://github.com/BradGroux/dm-lessonmeld/releases")!

    static let updatePolicy = "Updates are published through signed and notarized GitHub releases plus the BradGroux/tap Homebrew cask. Automatic update checks are not enabled."

    private static func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
