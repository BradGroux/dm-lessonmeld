import DMLessonMeldCore
import Testing

@Suite("Transcript exporter")
struct TranscriptExporterTests {
    @Test("Exports Markdown, plain text, VTT, and SRT")
    func exportsCommonFormats() {
        let transcript = TranscriptDocument(
            title: "Lesson",
            segments: [
                TranscriptSegment(id: "1", startSeconds: 0, endSeconds: 2.5, text: "Welcome."),
                TranscriptSegment(id: "2", startSeconds: 62.25, endSeconds: 65, text: "Now build.")
            ]
        )

        #expect(TranscriptExporter.markdown(transcript).contains("**1:02** Now build."))
        #expect(TranscriptExporter.plainText(transcript) == "Welcome.\nNow build.\n")
        #expect(TranscriptExporter.vtt(transcript).contains("00:01:02.250 --> 00:01:05.000"))
        #expect(TranscriptExporter.srt(transcript).contains("00:00:00,000 --> 00:00:02,500"))
    }
}
