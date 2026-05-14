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

Use **Import Video** in the sidebar, **File > Import Video**, the command palette, or the menu bar extra to import an existing MP4 or MOV.

LessonMeld copies the source video into a local `.dmlm` bundle as the primary screen video, writes the project manifest, and opens the timeline editor immediately. Imported videos use the full editing workspace: a large preview canvas, custom playback controls, trim in/out points, cut blocks, zoom blocks, overlays, markers, annotation controls, export controls, and a bottom timeline. Recording-only tracks such as webcam picture-in-picture, cursor metadata, microphone, and system audio are available only when they were captured or added to the bundle.

## Review a Project

Open a `.dmlm` lesson bundle from the sidebar or Finder. The project editor lets you:

- Edit lesson title, course, module, instructor, tags, and summary
- Style the final video canvas with aspect ratio, custom dimensions, crop, background, padding, inset, rounded corners, and shadow controls
- Review media readiness and project assets
- Add and edit markers
- Save timeline cuts, zoom regions, and timed video overlays
- Scrub through a bottom timeline with clip, cut, zoom, overlay, cursor, and marker lanes
- Open annotation tools
- Render local video files
- Package course exports

Use **Assets** in the editor inspector, or **Project Assets** on the project dashboard, to inspect the editable `.dmlm` lesson project separately from source videos, audio sidecars, captions, overlays, annotations, edit decisions, and export destinations. Asset rows show status, size when available, validation issues, and Finder actions for opening or revealing the underlying file.

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

## Mix Audio and Pacing

Use the **Audio** inspector tab to adjust captured sound and lesson pacing.

- Control screen, microphone, and system audio gain with mute and solo toggles.
- Import background music into `audio/assets/` inside the `.dmlm` bundle.
- Set music start time, source offset, duration, loop behavior, fade in/out, and duck-under-voice volume.
- Add volume regions at the playhead, then drag or resize them in the **Audio** timeline lane.
- Choose whether each volume region targets all tracks, screen audio, microphone, system audio, or music.
- Add speed regions for slow-downs, fast review, typing cleanup, or dead-air cleanup.

Volume and music settings are saved in `editor-settings.json` and are applied by the full render exporter. Speed regions are saved in `edit-decisions.json`; render inspection blocks export while speed regions exist until AV retiming support is implemented, so the unsupported state is explicit instead of silently producing the wrong video.

## Edit Captions

Use the **Captions** inspector tab to review, retime, style, and export caption sidecars.

- Import JSON transcript, VTT, SRT, plain text, or Markdown files.
- Add manual captions at the playhead when no transcription runtime is available.
- Edit caption text in sync with preview playback.
- Drag or resize caption blocks in the **Captions** timeline lane.
- Choose burn-in placement, font, size, text color, background color, max line count, and safe margin.
- Save captions to project-local `transcript.json`, `captions.vtt`, `captions.srt`, and `transcript.txt` sidecars.

Render/export uses the JSON transcript source for styled burned-in captions. LearnHouse packaging includes the project-local caption and transcript sidecars because they are attached to the lesson manifest.

## Export and Share Locally

Use the **Export** inspector tab to keep export actions separate:

- **Render Settings** controls quality, container, resolution, frame rate, codec, hardware acceleration, concurrency, and explicit alpha/GIF/ProRes roadmap gates.
- **Local Render** writes a final MP4/MOV through the renderer.
- **Local Share Package** builds a `.lessonshare` directory with project metadata, editable sidecars, raw assets, optional final video, and checksums.
- **Raw Assets** extracts source files from the `.dmlm` bundle into a standalone raw-assets folder.
- **Course Package** builds the LearnHouse package.
- **Publishing** stays gated until a future connector exists, so local export actions do not accidentally publish externally.

CLI equivalents:

```sh
swift run dmlesson render plan /tmp/Intro.dmlm --output /tmp/lesson.mp4 --resolution 1080p --fps 30 --codec h264 --json
swift run dmlesson project extract-assets /tmp/Intro.dmlm --output /tmp/raw-assets --json
swift run dmlesson share package /tmp/Intro.dmlm --output /tmp/shares --final-video /tmp/lesson.mp4 --json
```

Alpha, GIF, and ProRes options are visible as explicit gates. Render validation reports them as unsupported instead of silently producing a different file.

## Add Video Overlays

Use the **Overlays** inspector tab or the overlay timeline lane to add project-local text, shapes, callouts, arrows, images, masks, and highlights.

- Add text, callout, shape, or image overlays at the playhead.
- Drag an overlay on the preview to place it visually.
- Drag the resize handle on a selected overlay to size focus regions visually.
- Drag or resize overlay blocks in the **Overlays** timeline lane to control timing.
- Edit opacity, text size, fill, stroke, fade in/out, animation preset, and z-order.
- For highlight overlays, choose dim, blur, spotlight, or outline mode, plus rectangle, rounded rectangle, or ellipse focus shape.
- Imported images are copied under `overlays/assets/` inside the `.dmlm` bundle.
- Save overlays into `overlays.json` so render/export burns them into the final video.

## Edit Camera Layouts

Recorded projects with a webcam track show the **Camera** inspector tab.

- Adjust the default camera corner, size, margin, aspect ratio, shape, mirroring, border, shadow, and corner radius.
- Add timed camera layout regions for corner PiP, side-by-side, presenter focus, hidden camera, and full camera.
- Drag or resize camera layout blocks in the **Camera** timeline lane.
- Add simple reaction overlays at the playhead.
- Save camera settings into `editor-settings.json` so render/export uses the same timed layouts.

Imported videos without a webcam track keep camera controls unavailable until a camera source is added to the project.

## Add Zooms

Use the **Zooms** inspector tab or the purple timeline lane to create and edit zoom regions.

- **Add** creates a smooth zoom at the playhead.
- **Instant** creates a zoom with no ramp.
- **Auto** creates zooms from recorded click metadata when the project has a cursor metadata sidecar.
- Select a zoom block, then drag the focus box on the preview to place the zoom visually.
- Use the scale, focus size, X, and Y sliders for precise adjustment without typing normalized values.
- Disable a zoom to keep it visible in the timeline while excluding it from render/export.
- Save **Zoom Defaults** to persist the project-level automatic click zoom toggle in `editor-settings.json`.

## Polish Cursor Effects

Recorded projects with cursor metadata can be adjusted from the **Cursor** inspector tab.

- Preview pointer, click, and keyboard overlay choices directly over the editor video.
- Choose the macOS pointer or a touch-dot pointer style.
- Enable or disable smoothed cursor movement.
- Change pointer visibility, size, fill color, and outline color.
- Change click ripple color, scale, opacity, and duration.
- Add optional generated click sounds and control their render volume.
- Show or hide captured keyboard shortcuts.
- Add cursor hide ranges at the playhead, then drag or resize them in the **Cursor** timeline lane.
- Save cursor settings into `editor-settings.json` so render/export uses the same effect choices.

Imported videos without cursor metadata show the cursor controls as unavailable because there is no pointer, click, or keyboard sidecar to render.

## Reuse Lesson Presets

Use the **Presets** inspector tab in the video editor to save or apply a local `.dmlpreset` file. Presets are separate from `.dmlm` lesson bundles: a `.dmlm` is the editable project with media, while a `.dmlpreset` is a reusable style/settings file.

Project presets include:

- Canvas, crop, background, padding, corner, shadow, cursor, click, keyboard, camera, audio, caption, and other editor settings from `editor-settings.json`
- Capture defaults from current app settings
- Annotation defaults from current app settings
- Export defaults from current app settings
- Project export preset IDs

Applying a preset writes project editor settings and may update capture settings or export preset IDs. It does not overwrite lesson metadata, media references, transcripts, captions, markers, or timeline tracks.

The Settings window also has a **Presets** section for importing or exporting app-level capture, annotation, and export defaults without opening a project.

CLI equivalents:

```sh
swift run dmlesson presets create-from-project /tmp/Intro.dmlm --output /tmp/workshop.dmlpreset --name "Workshop"
swift run dmlesson presets inspect /tmp/workshop.dmlpreset
swift run dmlesson presets preview /tmp/Other.dmlm --preset /tmp/workshop.dmlpreset
swift run dmlesson presets apply /tmp/Other.dmlm --preset /tmp/workshop.dmlpreset
```

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
