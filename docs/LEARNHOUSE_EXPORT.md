# LearnHouse Export

`dm-lessonmeld` should support LearnHouse out of the box through a local package export. Direct publishing can come later.

## MVP package

The export layer can generate a local package directory and a zipped `.learnhouse.zip` archive.

```text
lesson-name.learnhouse/
  manifest.json
  assets/
    lesson.mp4
    thumbnail.jpg
    captions.vtt
    captions.srt
    transcript.md
    transcript.txt
    transcript.json
    checksums.sha256
  learnhouse/
    manifest.json
    courses/{course_uuid}/course.json
    courses/{course_uuid}/thumbnails/{thumbnail}
    courses/{course_uuid}/chapters/{chapter_uuid}/chapter.json
    courses/{course_uuid}/chapters/{chapter_uuid}/activities/{activity_uuid}/activity.json
    courses/{course_uuid}/chapters/{chapter_uuid}/activities/{activity_uuid}/files/video/{video}
```

`LearnHousePackageBuilder.buildPackage(projectURL:outputDirectory:)` writes the directory form.
`LearnHousePackageBuilder.buildArchive(projectURL:outputDirectory:)` writes the same directory form and then creates `lesson-name.learnhouse.zip` beside it.
`LearnHouseArchiveBuilder` is also public for callers that need to archive an already-built `.learnhouse` directory.

Archive creation uses Foundation `Process` with the built-in macOS `/usr/bin/ditto` zip support. No production dependency is required.

## Strategy

- The root `manifest.json` is a Digital Meld manifest for portability and agent workflows.
- Root manifest fields use stable `snake_case` JSON names for package metadata such as `schema_version`, `learn_house`, `course_uuid`, `relative_path`, and `byte_count`.
- The `learnhouse/` folder mirrors LearnHouse's native course transfer structure where enough metadata exists.
- Captions and transcripts remain `dm-lessonmeld` sidecars until LearnHouse has a documented first-class caption/transcript import field for hosted video activities.
- Packages contain no credentials.

## Roadmap

- Add course/chapter/activity UUID stability.
- Validate packages before export.
- Add direct LearnHouse publish connector only after explicit credential and confirmation flows exist.
