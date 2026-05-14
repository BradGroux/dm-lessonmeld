# Usage Guide

## Start the App

Build and launch locally:

```sh
scripts/build-app.sh
open "Packaging/Digital Meld LessonMeld.app"
```

Or run from source:

```sh
swift run DMLessonMeld
```

## First Run

Onboarding checks the permissions LessonMeld needs for recording:

- Screen Recording for screen, window, and area capture
- Microphone for instructor voice
- Camera for webcam picture-in-picture
- Accessibility and Input Monitoring for optional interaction metadata and global shortcuts

You can continue without optional permissions and enable them later from **Settings** or **Onboarding**.

## Record a Lesson

1. Open LessonMeld.
2. Click **Record** in the sidebar to capture immediately, or click **Edit** / **Edit Lesson** to create an editable draft before recording.
3. Choose the capture target from the floating recorder.
4. Confirm camera, microphone, annotation, and audio choices.
5. Press the record button.
6. Use the floating controls to pause, stop, mark moments, or open settings.

When you press **Stop**, LessonMeld opens the saved lesson in the editor. The `.dmlm` item is a macOS package directory: it is the lesson project, not the final video file. It contains `screen.mp4`, optional webcam/audio tracks, and the local sidecars used for review, cuts, zooms, annotations, rendering, and course packaging.

## Review a Project

Open a `.dmlm` lesson bundle from the sidebar or Finder. The project editor lets you:

- Edit lesson title, course, module, instructor, tags, and summary
- Review media readiness
- Add and edit markers
- Save cuts and zoom regions
- Open annotation tools
- Render local video files
- Package course exports

Technical bundle details are kept in advanced sections so normal review work stays readable.

## Annotate

Open annotation tools from the sidebar, project editor, recorder bar, or command palette.

Main controls:

- Cursor mode for click-through behavior
- Pen, highlighter, eraser, line, box, ellipse, arrow, text, and laser pointer
- Whiteboard and blackboard backgrounds
- Color swatches, line width, and text size
- Undo, redo, lock, visibility, pin, copy annotated screen, clear, settings, and close

Text annotations use a focused text editor. Press **Enter** to commit, **Shift+Enter** for a new line, and **Escape** to cancel text entry.

## CLI

Use `dmlesson` for automation and smoke tests:

```sh
swift run dmlesson --help
swift run dmlesson permissions status --json
swift run dmlesson project create --lesson-title "Intro" --output /tmp/Intro.dmlm
swift run dmlesson render plan /tmp/Intro.dmlm --output /tmp/lesson.mp4 --json
```

JSON output is intended to be stable enough for local agents and scripts. Metadata is safe by default; media paths and transcript contents should be included only when explicitly requested.

## Local-Only Posture

Normal operation does not require accounts, telemetry, analytics, cloud sync, license activation, or hosted processing. Project files stay local until you move, publish, or back them up yourself.
