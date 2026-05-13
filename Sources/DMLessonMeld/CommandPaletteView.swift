import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var commands: [CommandPaletteCommand]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredCommands) { command in
                        Button {
                            command.action()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: command.systemImage)
                                    .font(.title3)
                                    .frame(width: 26)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(command.title)
                                        .font(.headline)
                                    Text(command.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if let shortcut = command.shortcut {
                                    Text(shortcut)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .frame(minHeight: 280)
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    private var filteredCommands: [CommandPaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return commands }

        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
                || $0.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }
}

struct CommandPaletteCommand: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var shortcut: String?
    var keywords: [String]
    var action: () -> Void
}
