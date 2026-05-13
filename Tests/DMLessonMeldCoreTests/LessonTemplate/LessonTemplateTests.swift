import DMLessonMeldCore
import Testing

@Suite("Lesson templates")
struct LessonTemplateTests {
    @Test("Default workshop template seeds a lesson manifest")
    func defaultTemplateSeedsManifest() throws {
        let template = try #require(LessonTemplateLibrary.template(id: "workshop-lesson"))
        let manifest = template.seedManifest(lessonTitle: "Intro to OpenClaw", courseTitle: "OpenClaw Dev Days")

        #expect(manifest.metadata.lessonTitle == "Intro to OpenClaw")
        #expect(manifest.metadata.courseTitle == "OpenClaw Dev Days")
        #expect(manifest.markers.contains { $0.title == "Demo" })
        #expect(manifest.exportPresets == ["learnhouse-1080p"])
    }

    @Test("LearnHouse preset includes sidecars")
    func learnHousePresetIncludesSidecars() throws {
        let preset = try #require(LessonTemplateLibrary.exportPreset(id: "learnhouse-1080p"))

        #expect(preset.format == "mp4")
        #expect(preset.includesSidecars)
    }
}
