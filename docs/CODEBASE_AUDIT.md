# Codebase Audit

Last reviewed: 2026-05-16

This audit covers the Swift app, shared core, CLI, packaging, release workflow, docs, and product backlog surfaces.

## Changes Landed From This Pass

- Moved project-editor dirty-state refresh ownership into `ProjectEditorModel` so unsaved-change state no longer depends on `ProjectEditorView` being mounted.
- Preserved nested LearnHouse asset paths under `assets/` so files with the same basename do not collide during package export.
- Removed the broken public no-copy LearnHouse package path; LearnHouse packages are self-contained.
- Made agent manifest transcript references opt-in independently from media paths.
- Filtered config-backup Git status output to report only syncable config/template changes and `.gitignore`, avoiding excluded media or credential-like filenames.
- Changed interaction metadata capture to be off by default, matching the optional privacy posture in docs.
- Limited render caption source selection to JSON transcript/caption sidecars so Markdown, VTT, SRT, and plain-text transcript references do not break caption burn-in.
- Moved the local app-control token into Keychain, migrated legacy plaintext token files, and added a persisted nonce cache to reject replayed local commands.
- Debounced annotation sidecar persistence through a serialized background writer and flushed pending writes when the overlay closes.
- Modeled embedded system audio explicitly in project manifests and render plans so ScreenCaptureKit audio is not confused with a missing sidecar.
- Serialized `DisplayScreenRecorder` stream, writer, pause, and sample counters on one state queue instead of mixing locks with unsynchronized lifecycle mutation.
- Added CLI window source listing and `record window --window-id` capture support, with project recording able to store window capture settings.
- Moved large video import project creation/copy/manifest work into a core import service and run it off the main actor from the app.
- Added a local real-media fixture smoke harness for MP4/MOV files and `.dmlm` bundles, plus release/CI syntax checks for the fixture scripts.
- Expanded the post-recording completion bar with caption/transcript sidecar export alongside review, video export, reveal, copy path, LearnHouse package, and new recording actions.
- Added local transcription model preferences plus app and CLI readiness checks for a configured local model file.
- Added target-specific agent workflow JSON for OpenClaw, Codex, and Veritas Kanban around the stable CLI command surface.
- Added a dependency-free stdio MCP wrapper for safe `dmlesson` project inspect, render plan, agent manifest/workflows, and transcription model status tools.
- Added CLI smoke coverage for documented examples, usage failures, JSON output shape, and README/usage command drift.
- Hardened release CI so build/package verification runs with read-only repository permissions and only the publish job receives `contents: write`.
- Fixed docs drift for speed-region retiming, render-plan-only knobs, README recording examples, and the project bundle manifest filename.
- Fixed `.gitignore` so future source-owned `docs/assets/**` files are actually trackable.

## Remaining Refactor Targets

- Split `ProjectEditorModel` into draft state, project IO, export coordination, playback, and AppKit dialog/workspace services. The current model still owns too many unrelated responsibilities.
- Split `QuickRecorderPanel.swift` into recorder state, capture-device selection, window/control-bar ownership, completion actions, and recording execution.
- Move app-layer business logic into a testable support library target so app workflows can be unit-tested without the executable target.
- Split `RenderService.swift` into composition building, overlay/caption/cursor layer building, audio mixing, and export execution.

## Product And Expansion Backlog

- Decide whether `0.0.4` should be published now or moved back to an unreleased state. The repo metadata is `0.0.4`, while GitHub Releases and casks still point at older artifacts.
- Publish a signed/notarized DMG release before treating DMG install docs as applying to every public release; older preview releases are zip-only.
- Update the repo cask and public tap cask together after the next release, and decide whether to keep zip-backed cask installs or switch the cask to the DMG artifact.
- Keep release workflow permissions under review as GitHub Actions evolves; current build/package verification and publish permissions are separated.
- Add local transcription runtime execution and model download/install assistance.
- Expand deeper local app-control actions for agent workflows beyond read/validate/package command sequences.
- Expand MCP coverage only after write/export tools have explicit confirmation boundaries.
- Add LMS/video-host connector evaluations after LearnHouse package export is solid.
