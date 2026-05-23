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

    @Test("Malformed caption timestamps return import errors")
    func malformedCaptionTimestampsReturnImportErrors() {
        let malformedVTT = """
        WEBVTT

        --> 00:00:03.000
        Missing start.
        """
        let malformedSRT = """
        1
        00:00:04,000 --> bad
        Bad end.
        """

        #expect(throws: TranscriptImportError.malformedTimestamp("--> 00:00:03.000")) {
            try TranscriptImporter.transcript(from: Data(malformedVTT.utf8), fileName: "captions.vtt")
        }
        #expect(throws: TranscriptImportError.malformedTimestamp("00:00:04,000 --> bad")) {
            try TranscriptImporter.transcript(from: Data(malformedSRT.utf8), fileName: "captions.srt")
        }
    }

    @Test("Oversized transcript imports are rejected before decoding")
    func oversizedTranscriptImportsAreRejectedBeforeDecoding() {
        let oversized = Data(repeating: UInt8(ascii: "A"), count: TranscriptImporter.maxImportBytes + 1)

        #expect(throws: TranscriptImportError.importTooLarge(byteCount: oversized.count, limit: TranscriptImporter.maxImportBytes)) {
            try TranscriptImporter.transcript(from: oversized, fileName: "captions.txt")
        }
    }

    @Test("Transcript imports enforce segment count limits")
    func transcriptImportsEnforceSegmentCountLimits() {
        let captions = (0...TranscriptImporter.maxSegments)
            .map { index in
                let start = index * 2
                let end = start + 1
                return """
                00:00:\(String(format: "%02d", start % 60)).000 --> 00:00:\(String(format: "%02d", end % 60)).000
                Caption \(index)
                """
            }
            .joined(separator: "\n\n")

        #expect(throws: TranscriptImportError.tooManySegments(limit: TranscriptImporter.maxSegments)) {
            try TranscriptImporter.webVTT(captions)
        }
    }
}
