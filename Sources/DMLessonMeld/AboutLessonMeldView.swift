import AppKit
import SwiftUI

struct AboutLessonMeldView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppBrand.displayName)
                        .font(.title2.weight(.semibold))
                    Text(AppMetadata.versionBuildText)
                        .foregroundStyle(.secondary)
                    Text(AppMetadata.bundleIdentifier)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Local-first lesson recording, video editing, rendering, and packaging.", systemImage: "record.circle")
                Label("Signed and notarized release builds install through the DMG or Homebrew cask.", systemImage: "checkmark.seal")
                Label(AppMetadata.updatePolicy, systemImage: "arrow.down.app")
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link("Release Notes", destination: AppMetadata.releaseNotesURL)
                Spacer()
                Text(AppMetadata.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 560, alignment: .leading)
    }
}
