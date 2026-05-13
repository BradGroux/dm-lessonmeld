import DMLessonMeldCore
import Foundation
import Testing

@Suite("Chapter export")
struct ChapterExportTests {
    @Test("Exports sorted chapter markers for YouTube descriptions")
    func exportsYouTubeChapters() throws {
        let manifest = ProjectManifest(
            metadata: LessonMetadata(lessonTitle: "Lesson"),
            markers: [
                ProjectTimelineMarker(id: "note", kind: .presenterNote, timeSeconds: 10, title: "Ignore"),
                ProjectTimelineMarker(id: "chapter-2", kind: .chapter, timeSeconds: 75, title: "Demo"),
                ProjectTimelineMarker(id: "chapter-1", kind: .chapter, timeSeconds: 0, title: "Intro")
            ]
        )

        let entries = ChapterExporter.entries(from: manifest)
        let rendered = try ChapterExporter.render(entries, format: .youtube)

        #expect(entries.map(\.title) == ["Intro", "Demo"])
        #expect(rendered == "00:00 Intro\n01:15 Demo\n")
    }

    @Test("Exports markdown with chapter notes")
    func exportsMarkdownChapters() throws {
        let entries = [
            ChapterExportEntry(timeSeconds: 3_661, title: "Wrap", notes: "Final recap")
        ]

        let rendered = try ChapterExporter.render(entries, format: .markdown)

        #expect(rendered == "- **1:01:01** Wrap - Final recap\n")
    }
}
