import SwiftUI

enum LessonMeldDesign {
    enum Spacing {
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let panel: CGFloat = 8
    }

    static var cardFill: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var panelFill: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.68)
    }

    static var sidebarFill: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var selectedFill: Color {
        Color.accentColor.opacity(0.15)
    }

    static var rowFill: Color {
        Color.primary.opacity(0.04)
    }

    static var hairline: Color {
        Color.primary.opacity(0.08)
    }
}

struct LessonMeldCard<Content: View>: View {
    var padding: CGFloat = 14
    private let content: () -> Content

    init(padding: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LessonMeldDesign.cardFill, in: RoundedRectangle(cornerRadius: LessonMeldDesign.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LessonMeldDesign.Radius.card, style: .continuous)
                    .stroke(LessonMeldDesign.hairline, lineWidth: 1)
            )
    }
}

struct LessonMeldPanel<Content: View>: View {
    var title: String
    var subtitle: String?
    var padding: CGFloat = 16
    private let content: () -> Content

    init(title: String, subtitle: String? = nil, padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.padding = padding
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LessonMeldDesign.panelFill, in: RoundedRectangle(cornerRadius: LessonMeldDesign.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LessonMeldDesign.Radius.panel, style: .continuous)
                .stroke(LessonMeldDesign.hairline, lineWidth: 1)
        )
    }
}

struct LessonMeldSectionTitle: View {
    var title: String
    var topPadding: CGFloat = 0

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, topPadding)
    }
}

struct LessonMeldInspectorSectionTitle: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct LessonMeldStatusPill: View {
    var title: String
    var systemImage: String
    var tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 1))
    }
}

struct LessonMeldSidebarItem: View {
    var title: String
    var systemImage: String
    var isSelected = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.92))
            .background(isSelected ? LessonMeldDesign.selectedFill : LessonMeldDesign.rowFill, in: RoundedRectangle(cornerRadius: LessonMeldDesign.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LessonMeldDesign.Radius.card, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
    }
}

struct LessonMeldCommandRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var shortcut: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 26)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let shortcut {
                Text(shortcut)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LessonMeldDesign.rowFill, in: RoundedRectangle(cornerRadius: LessonMeldDesign.Radius.card, style: .continuous))
    }
}
