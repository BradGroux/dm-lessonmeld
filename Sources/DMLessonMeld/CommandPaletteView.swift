import AppKit
import DMLessonMeldCore
import SwiftUI

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    var commands: [CommandPaletteCommand]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .accessibilityLabel("Command search")
                    .accessibilityHint("Type a command name, workflow, or shortcut keyword.")
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    if filteredCommands.isEmpty {
                        ContentUnavailableView("No Commands Found", systemImage: "command", description: Text("Try a different search."))
                            .padding(.top, 48)
                    } else {
                        ForEach(filteredCommands) { command in
                            Button {
                                guard command.isEnabled else { return }
                                command.action()
                                dismiss()
                            } label: {
                                LessonMeldCommandRow(
                                    title: command.title,
                                    subtitle: command.disabledReason ?? command.subtitle,
                                    systemImage: command.systemImage,
                                    shortcut: command.shortcut
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!command.isEnabled)
                            .opacity(command.isEnabled ? 1 : 0.62)
                            .accessibilityLabel(command.title)
                            .accessibilityValue(commandAccessibilityValue(command))
                            .accessibilityHint(command.disabledReason ?? command.subtitle)
                        }
                    }
                }
                .padding(10)
            }
            .frame(minHeight: 280)
        }
        .frame(
            minWidth: AppUILayoutSurface.commandPalette.minimumSize.width,
            minHeight: AppUILayoutSurface.commandPalette.minimumSize.height
        )
        .onAppear {
            searchFocused = true
        }
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

    private func commandAccessibilityValue(_ command: CommandPaletteCommand) -> String {
        let state = command.isEnabled ? "Enabled" : "Disabled"
        guard let shortcut = command.shortcut else { return state }
        return "\(state), shortcut \(shortcut)"
    }
}

struct CommandPaletteCommand: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var shortcut: String?
    var keywords: [String]
    var isEnabled = true
    var disabledReason: String?
    var action: () -> Void

    init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        shortcut: String?,
        keywords: [String],
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.keywords = keywords
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.action = action
    }

    init(command: LessonMeldAppCommand) {
        self.init(
            id: command.id.rawValue,
            title: command.title,
            subtitle: command.subtitle,
            systemImage: command.systemImage,
            shortcut: command.shortcut,
            keywords: command.keywords,
            isEnabled: command.isEnabled,
            disabledReason: command.disabledReason,
            action: command.action
        )
    }
}
