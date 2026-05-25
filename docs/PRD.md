# Product Requirements: Digital Meld LessonMeld

## Summary

Digital Meld LessonMeld is a native, open-source, local-first macOS recording suite for creating curriculum videos, workshops, walkthroughs, support videos, and technical lessons.

The product should feel like a recorder first, then a review, render, and package workspace. A user should be able to start a recording quickly, trust that everything stays local, review the captured lesson, annotate or mark the important moments, render a clean video, and package the lesson for course delivery.

## Product Goals

- Record display, window, and selected-area lessons from a compact floating recorder.
- Capture webcam, microphone, optional system audio, cursor movement, clicks, and keyboard interaction metadata.
- Store work in local `.dmlm` bundles with deterministic media files and JSON sidecars.
- Provide a useful project editor for metadata, markers, cuts, zooms, annotations, render readiness, and export actions.
- Make curriculum workflows first-class: lesson details, chapters, retake markers, notes, captions, transcripts, templates, and course-ready package exports.
- Keep normal operation local-only: no accounts, telemetry, analytics, license activation, cloud sync, or hosted processing.
- Expose deterministic CLI and agent-readable JSON for automation.
- Keep the codebase native, lean, dependency-light, and easy for contributors to reason about.

## Non-Goals

- Cloud hosting or shareable links in the initial product.
- Account system, subscription activation, analytics, or telemetry.
- Windows/Linux support.
- Browser-based editor.
- External plugin loading in the initial product.
- Direct credentialed publishing integrations before explicit confirmation and credential flows exist.
- AI voiceover in the initial product.

## Target Users

- Curriculum builders recording technical lessons.
- Workshop leads preparing repeatable training assets.
- Founders and builders recording product demos.
- Engineers creating walkthroughs, bug reports, and release notes.
- Support and customer-success teams producing short local explainers.
- Open-source maintainers who want polished demo videos without proprietary lock-in.

## Core Flows

### First Run

- Show onboarding as a normal app window.
- Explain local-only posture plainly.
- Preflight Screen Recording, Microphone, Camera, Accessibility, and Input Monitoring permissions.
- Offer teaching defaults for microphone, webcam, captions, project folder, templates, and package export.
- Let users reopen onboarding from the main sidebar.

### New Recording

- Open a compact floating recorder from the sidebar, menu, shortcut, CLI/app-control command, or first-run call to action.
- Let the user choose display, window, or area capture.
- Put camera, microphone, annotation, and system audio controls on the recorder.
- Keep advanced controls in popovers: countdown, auto-stop, cursor capture, privacy/safety controls, speaker notes, and project template.
- Recording should be manual-stop by default. Timed recording is an option, not the default path.

### Recording In Progress

- Show an elapsed-time control bar with pause/resume, stop, restart/delete, hide, marker, camera, microphone, annotation, and settings controls.
- Keep the control bar out of captures by default, with a setting to include it for testing or tutorials.
- Provide menu and shortcut stop paths.
- Save recoverable local tracks and metadata if the app exits unexpectedly.

### Review and Edit

- Open `.dmlm` bundles from the app, Finder, or CLI.
- Show a lesson overview that favors user decisions over raw internal data.
- Let users edit lesson details, course/module/instructor fields, summary, tags, markers, cuts, zoom regions, annotations, and render/export settings.
- Keep technical bundle details available behind diagnostics/advanced disclosure.

### Annotation

- Keep annotation available as a live overlay during recording and review.
- Tools: cursor, pen, highlighter, eraser, line, box, ellipse, arrow, text, laser pointer, whiteboard, blackboard, undo, redo, lock, visibility, pin, copy annotated screen, clear, settings, and close.
- Toolbar must support horizontal and vertical layouts, drag positioning, collapse, per-display movement, hover tooltips, and settings-controlled tooltip visibility.
- Text annotations need real editable text entry, multiline support, auto-sizing, Escape cancel, and predictable commit behavior.

### Render and Export

- Render to local files first.
- Support webcam picture-in-picture, cursor/click/shortcut effects, zoom regions, annotations, captions, and transcript sidecars.
- Provide local course-package export with stable manifests and checksums.
- Keep direct publishing connectors on the roadmap until credential, preview, and confirmation flows are hardened.

### CLI and Agent Support

- `dmlesson` should expose project, capture, edit, render, export, package, settings, config backup, annotation, and app-control commands.
- JSON output must be stable and safe by default.
- Media paths and transcript contents should require explicit flags before appearing in agent-readable output.
- Local app-control commands must be authenticated so another local process cannot start capture without a valid token.

## Project Bundle

The `.dmlm` bundle is the source of truth.

Expected structure:

```text
lesson-name.dmlm/
  project.json
  screen.mp4
  webcam.mov
  microphone.m4a
  system-audio.m4a
  cursor-metadata.json
  interaction-metadata.json
  edit-decision-list.json
  annotations.json
  captions.vtt
  transcript.json
  exports/
```

All optional files should be referenced by the manifest or known sidecar names. Validation should distinguish blockers from warnings.

## Settings and Backup

- Store preferences locally as versioned JSON-compatible models.
- Support export/validate/write-defaults from the CLI.
- Support local Git backup for non-sensitive settings, templates, presets, and Markdown notes.
- Never back up project media, transcripts, diagnostics, caches, credentials, or secrets by default.
- Git remotes are explicit user opt-in.

## Distribution

- MIT licensed.
- Public source repo.
- Homebrew Cask distribution.
- Developer-preview builds can be ad-hoc signed only when the release mode is explicitly set to `unsigned-preview`.
- Broad binary distribution uses Developer ID signing, Apple notarization, and a DMG-first install path.
- Release artifacts should include DMG, zip, and SHA256 checksums.

## Success Criteria for v0.0.1

- Source builds locally with Swift.
- Tests pass.
- Packaged app launches.
- README, docs, release guide, changelog, cask, CI, and security/contributing docs exist.
- Public docs describe LessonMeld as its own product and avoid reference-app implementation notes.
- Version history starts at `0.0.1`.

## Roadmap Themes

- Device-matrix QA for screen, window, area, webcam, microphone, and system audio capture.
- Better recording recovery.
- Richer timeline editing UI.
- Local transcription runtime.
- More renderer controls and media formats.
- More course and video-host package/export targets.
- Signed/notarized release hygiene and cask checksum updates after each public tag.
- Accessibility and recording-safety pass.
