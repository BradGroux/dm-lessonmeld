import DMLessonMeldCore
import Foundation
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

    @Test("Imports VTT, SRT, and plain text captions")
    func importsCommonFormats() throws {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:03.500
        Welcome to captions.
        """
        let srt = """
        1
        00:00:04,000 --> 00:00:06,250
        Now build.
        """

        let vttTranscript = try TranscriptImporter.transcript(from: Data(vtt.utf8), fileName: "captions.vtt")
        let srtTranscript = try TranscriptImporter.transcript(from: Data(srt.utf8), fileName: "captions.srt")
        let textTranscript = try TranscriptImporter.transcript(from: Data("One\nTwo".utf8), fileName: "captions.txt")

        #expect(vttTranscript.segments.first?.startSeconds == 1)
        #expect(vttTranscript.segments.first?.endSeconds == 3.5)
        #expect(vttTranscript.segments.first?.text == "Welcome to captions.")
        #expect(srtTranscript.segments.first?.startSeconds == 4)
        #expect(srtTranscript.segments.first?.endSeconds == 6.25)
        #expect(textTranscript.segments.map { $0.text } == ["One", "Two"])
    }
}
