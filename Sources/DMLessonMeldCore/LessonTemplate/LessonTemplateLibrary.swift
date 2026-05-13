import Foundation

public enum LessonTemplateLibrary {
    public static let defaultBrandPreset = BrandPreset(
        id: "digital-meld-dark",
        name: "Digital Meld Dark",
        canvasBackground: "near-black",
        cursorStyle: "high-contrast-ring",
        captionStyle: "dark-lower-third",
        cameraLayout: "bottom-right-rounded"
    )

    public static let defaultTemplates: [LessonTemplate] = [
        LessonTemplate(
            id: "workshop-lesson",
            name: "Workshop Lesson",
            summary: "Structured lesson with setup, demo, exercise, and recap markers.",
            segmentKinds: [.intro, .setup, .demo, .explanation, .exercise, .recap, .outro],
            defaultExportPresetID: "learnhouse-1080p",
            brandPreset: defaultBrandPreset
        ),
        LessonTemplate(
            id: "quick-demo",
            name: "Quick Demo",
            summary: "Short product walkthrough with intro, demo, and recap markers.",
            segmentKinds: [.intro, .demo, .recap],
            defaultExportPresetID: "web-1080p",
            brandPreset: defaultBrandPreset
        )
    ]

    public static let defaultExportPresets: [LessonTemplateExportPreset] = [
        LessonTemplateExportPreset(
            id: "learnhouse-1080p",
            name: "LearnHouse 1080p",
            format: "mp4",
            codec: "h264",
            resolution: "1920x1080",
            fps: "source",
            includesSidecars: true
        ),
        LessonTemplateExportPreset(
            id: "web-1080p",
            name: "Web 1080p",
            format: "mp4",
            codec: "h264",
            resolution: "1920x1080",
            fps: "30",
            includesSidecars: false
        ),
        LessonTemplateExportPreset(
            id: "archive-prores",
            name: "Archive ProRes",
            format: "mov",
            codec: "prores422",
            resolution: "source",
            fps: "source",
            includesSidecars: true
        )
    ]

    public static func template(id: String) -> LessonTemplate? {
        defaultTemplates.first { $0.id == id }
    }

    public static func exportPreset(id: String) -> LessonTemplateExportPreset? {
        defaultExportPresets.first { $0.id == id }
    }
}
