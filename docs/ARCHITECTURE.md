# Architecture

`dm-lessonmeld` is a Swift-native macOS suite with a shared package core and two primary executables:

- `DMLessonMeld`: local foreground macOS app with a standard app menu, first-run onboarding, settings, command palette, project editor, quick recording, permission status, launch diagnostics, and live annotation overlay.
- `dmlesson`: CLI for capture, project inspection, editing, rendering, export/package automation, settings JSON, config backup, and agent workflows.

## Current package layout

```text
Sources/
  DMLessonMeld/            SwiftUI/AppKit app, windows, recorder UI, settings, onboarding
  DMLessonMeldCLI/         `dmlesson` command-line interface
  DMLessonMeldCore/        Shared local-first suite core
    AgentBridge/           Agent-readable manifests and command catalog
    Annotation/            Shared annotation model and undoable store
    Audio/                 Microphone capture, audio models, waveform peaks
    Captions/              Transcript and caption import/export helpers
    Capture/               Screen, region, webcam, cursor/keystroke metadata
    ConfigSync/            Safe local Git config/template backup planning and commits
    Editor/                Edit decision lists, canvas/camera/audio settings, trim plans, AVFoundation trim export
    LearnHouseExport/      LearnHouse-ready local package generation
    LessonProject/         Project bundle manifest, validation, JSON helpers
    LessonSettings/        Preferences snapshot, onboarding state, safe defaults
    LessonTemplate/        Lesson templates, brand presets, export presets
    Render/                AVFoundation render plans/export with styled canvases, webcam PiP, audio gain/music mixing, cursor/click/shortcut effects, zoom regions, annotations, and styled transcript captions

Tests/
  DMLessonMeldCoreTests/   Core regression suite, organized by the same internal folders
```

## Runtime stance

- Normal operation has no backend.
- Secrets belong in macOS Keychain, not project/config files.
- Git sync is local-first, opt-in, and only for non-sensitive config/templates/presets. Adding a GitHub remote is left to the user or a future explicit integration.
- The app owns the interactive permission/recording path. The CLI also supports direct local capture for automation, smoke tests, and agent workflows.
- Settings are persisted locally through `UserDefaults` as a versioned `LessonMeldPreferences` snapshot.
- Settings backup controls can write the current preferences snapshot to `settings/preferences.json`, initialize the local backup repo, preview the plan, and commit through the core config sync folder.
- The app editor opens local `.dmlm` bundles, inspects manifests, opens video-backed projects in a preview-first timeline workspace, saves `editor-settings.json` canvas, cursor, and camera settings, `edit-decision-list.json` cut/zoom sidecars, and `overlays.json` timed overlay sidecars, exports those saved cuts, checks render readiness, exports full renders with canvas styling, camera layout regions/reactions, cursor/click/shortcut/zoom/overlay/annotation/caption burn-in and progress/cancel controls, and creates contiguous trim exports through existing core services.
- Project media URL resolution is centralized through `ProjectBundle.fileURL(for:in:)` so project-relative and explicitly attached absolute files behave the same across app, CLI, render, validation, and LearnHouse package paths.
- First-run onboarding covers Screen Recording, Microphone, Camera, Accessibility, Input Monitoring, teaching defaults, local-only posture, Git-safe settings backup, LearnHouse, and agent manifests.
- Git-friendly settings exports use stable JSON object keys, including shortcut values, so backups diff cleanly.
- Config backup commits stage only planner-approved JSON/YAML/TOML/Markdown files plus the generated `.gitignore`; media, transcripts, diagnostics, caches, projects, exports, and credential-like names are excluded.
- Launch diagnostics track previous clean exit, safe mode, launch count, and current permission health.

## Remaining implementation gaps

- Effect controls beyond trims, cuts, zooms, markers, annotations, and export readiness.
- iOS device capture.
- Local transcription model download/runtime.
- Higher-fidelity renderer support for caption styling, cursor styling, zoom/pan keyframes, GIF/ProRes, and parallel rendering.
- Developer ID signed/notarized distribution and DMG packaging. Homebrew cask mirror and release workflow are wired.

## Agent boundary

Agents should interact through deterministic project files and CLI JSON output. Commands must default to metadata-only output and require explicit flags before exposing transcript or media paths.
