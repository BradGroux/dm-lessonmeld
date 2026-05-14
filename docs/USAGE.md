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
2. Click **Record** in the sidebar to capture immediately.
3. Choose the capture target from the floating recorder.
4. Confirm camera, microphone, annotation, and audio choices.
5. Press the record button.
6. Use the floating controls to pause, stop, mark moments, or open settings.

When you press **Stop**, LessonMeld opens the saved lesson in the editor. The `.dmlm` item is a macOS package directory: it is the lesson project, not the final video file. It contains `screen.mp4`, optional webcam/audio tracks, and the local sidecars used for review, cuts, zooms, annotations, rendering, and course packaging.

## Edit an Existing Video

Use **Edit Video** in the sidebar, **File > Create Project from Video...**, the command palette, or the menu bar extra to import an existing MP4 or MOV.

LessonMeld copies the source video into a local `.dmlm` bundle as the primary screen video, writes the project manifest, and opens the timeline editor immediately. Imported videos use the full editing workspace: a large preview canvas, custom playback controls, trim in/out points, cut blocks, zoom blocks, markers, annotation controls, export controls, and a bottom timeline. Recording-only tracks such as webcam picture-in-picture, cursor metadata, microphone, and system audio are available only when they were captured or added to the bundle.

## Review a Project

Open a `.dmlm` lesson bundle from the sidebar or Finder. The project editor lets you:

- Edit lesson title, course, module, instructor, tags, and summary
- Style the final video canvas with aspect ratio, custom dimensions, crop, background, padding, inset, rounded corners, and shadow controls
- Review media readiness
- Add and edit markers
- Save timeline cuts and zoom regions
- Scrub through a bottom timeline with clip, cut, zoom, and marker lanes
- Open annotation tools
- Render local video files
- Package course exports

Technical bundle details are kept in advanced sections so normal review work stays readable.

## Style the Video Canvas

Open **Edit Video**, then use the **Canvas** inspector tab to control the rendered frame. Canvas settings are saved in `editor-settings.json` inside the current `.dmlm` bundle, so recorded lessons and imported MP4/MOV projects keep their own styling.

Canvas controls affect the final render:

- **Aspect** keeps the source size, uses common formats such as 1:1, 4:5, 9:16, 4:3, or 16:9, or uses custom pixel dimensions.
- **Background** can be none, a solid color, a gradient, or a project-local PNG/JPEG image.
- **Padding** adds space around the source video.
- **Inset** reserves an outer frame before padding is applied.
- **Corners** rounds the source video frame.
- **Shadow** adds depth behind the source video.
- **Crop** trims the source video with normalized `0...1` fields before it is placed on the canvas.

Use **None** for background when the rendered video should remain raw source pixels. Use a solid, gradient, or image background when exporting square, portrait, or padded lesson videos for publishing.

## Edit on the Timeline

The bottom timeline writes to the same project-local sidecars used by render/export. Timeline edits autosave when you finish dragging or use the block context menu.

- Drag the **In** and **Out** handles on the clip lane to adjust trim bounds.
- Drag cut and zoom blocks to move them.
- Drag a cut or zoom block edge to resize its range.
- Drag markers to retime them.
- Right-click cut, zoom, and marker blocks to jump, disable, duplicate, or remove them.
- Select a block and press **Delete** to remove it.
- Press **B** to add a cut at the playhead and **Z** to add a zoom at the playhead.
- Use the left and right arrow keys to nudge the playhead by one second.

Search **Timeline Editing Shortcuts** in the command palette for the active keyboard controls.

## Add Zooms

Use the **Zooms** inspector tab or the purple timeline lane to create and edit zoom regions.

- **Add** creates a smooth zoom at the playhead.
- **Instant** creates a zoom with no ramp.
- **Auto** creates zooms from recorded click metadata when the project has a cursor metadata sidecar.
- Select a zoom block, then drag the focus box on the preview to place the zoom visually.
- Use the scale, focus size, X, and Y sliders for precise adjustment without typing normalized values.
- Disable a zoom to keep it visible in the timeline while excluding it from render/export.
- Save **Zoom Defaults** to persist the project-level automatic click zoom toggle in `editor-settings.json`.

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
