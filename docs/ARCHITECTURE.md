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
    AgentBridge/           Agent-readable manifests, command catalog, and target workflow catalog
    Annotation/            Shared annotation model and undoable store
    Audio/                 Microphone capture, audio models, waveform peaks
    Captions/              Transcript/caption import/export helpers plus local transcription model readiness
    Capture/               Screen, region, webcam, cursor/keystroke metadata
    ConfigSync/            Safe local Git config/template backup planning and commits
    ConnectorExport/       Common Cartridge, SCORM, xAPI, and video-host handoff package builders
    Editor/                Edit decision lists, canvas/camera/audio settings, trim plans, AVFoundation trim export
    LearnHouseExport/      LearnHouse-ready local package generation
    LessonProject/         Project bundle manifest, validation, JSON helpers
    LessonPreset/          Shareable local preset files and safe project/app preference appliers
    LessonSettings/        Preferences snapshot, onboarding state, safe defaults
    LessonTemplate/        Lesson templates, brand presets, export presets
    Render/                AVFoundation render plans/export with styled canvases, webcam PiP, audio gain/music mixing, cursor/click/shortcut effects, zoom regions, annotations, and styled transcript captions
    ShareExport/           Raw asset extraction and local `.lessonshare` package generation with checksums
  DMLessonMeldSupport/     Testable app-workflow services shared by the app and app-adjacent tests

Tests/
  DMLessonMeldCoreTests/   Core regression suite, organized by the same internal folders
```

## Runtime stance

- Normal operation has no backend.
- Secrets belong in macOS Keychain, not project/config files.
- Local app-control tokens are stored in Keychain only when explicit app-control automation is used, with a short-lived persisted nonce cache to reject replayed local commands.
- Git sync is local-first, opt-in, and only for non-sensitive config/templates/presets. Adding a GitHub remote is left to the user or a future explicit integration.
- The app owns the interactive permission/recording path. The CLI also supports direct local capture for automation, smoke tests, and agent workflows.
- Settings are persisted locally through `UserDefaults` as a versioned `LessonMeldPreferences` snapshot.
- Settings backup controls can write the current preferences snapshot to `settings/preferences.json`, initialize the local backup repo, preview the plan, and commit through the core config sync folder.
- The support target owns app-adjacent pure workflow logic such as project render planning, quick-recording completion render/package decisions, and caption/transcript sidecar export.
- The app editor opens local `.dmlm` bundles, inspects manifests, opens video-backed projects in a preview-first timeline workspace, saves `editor-settings.json` canvas, cursor, camera, audio, and caption settings, `edit-decision-list.json` cut/zoom sidecars, and `overlays.json` timed overlay sidecars, exports those saved cuts, checks render readiness, exports full renders through support/core services, creates contiguous trim exports through existing core services, imports/exports `.dmlpreset` style files without touching project media or metadata, extracts raw project assets, builds local `.lessonshare` packages with checksums, and exposes package-first connector builders through the CLI.
- Project media URL resolution is centralized through `ProjectBundle.fileURL(for:in:)` so project-relative and explicitly attached absolute files behave the same across app, CLI, render, validation, and LearnHouse package paths.
- First-run onboarding covers Screen Recording, Microphone, Camera, Accessibility, Input Monitoring, teaching defaults, local-only posture, Git-safe settings backup, LearnHouse, and agent manifests.
- Git-friendly settings exports use stable JSON object keys, including shortcut values, so backups diff cleanly.
- Config backup planning classifies JSON/YAML/TOML/Markdown as safe to stage, credential-bearing and excluded, or review-required when inspection is incomplete or uncertain. Commits stage safe files plus exact review-required paths explicitly approved by the caller; media, transcripts, diagnostics, caches, projects, exports, and credential-like names remain excluded.
- Launch diagnostics track previous clean exit, safe mode, launch count, and current permission health.

## Remaining implementation gaps

- Effect controls beyond trims, cuts, zooms, markers, annotations, and export readiness.
- iOS device capture.
- Local transcription model download/runtime. Model path preferences and readiness checks are in place.
- Higher-fidelity renderer support for caption styling, cursor styling, zoom/pan keyframes, GIF/alpha output, and parallel rendering.
- Apple Developer release provisioning is configured for public binary publication. Release packaging, DMG generation, Developer ID signing/notarization enforcement, and the Homebrew cask mirror are wired.

## Agent boundary

Agents should interact through deterministic project files and CLI JSON output. Commands must default to metadata-only output and require explicit flags before exposing transcript or media paths. `agent workflows --target openclaw|codex|veritas-kanban --json` exposes safe command sequences for common automation handoffs. `scripts/dmlesson-mcp-server.py` wraps the safe read/plan subset as stdio MCP tools without exposing recording or export execution.
