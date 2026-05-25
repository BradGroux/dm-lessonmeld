# Roadmap

## v0.0.1 Developer Preview

- Buildable Swift package and `dmlesson` CLI. Done.
- Native foreground macOS app shell with permission status, quick-record panel, and live annotation overlay. Done.
- First-run onboarding, persistent settings, shortcut preferences, command palette, and launch diagnostics for recording, package export, agents, and local-only privacy. Done.
- In-app config backup controls for plan/init/settings JSON write/commit. Done.
- App project editor for manifest inspection, screen preview/scrub, edit-decision cuts, render readiness, full render export, and contiguous trim export. Done.
- Shared `edit-decision-list.json` project sidecar with app and CLI read/add-cut/validate/export support. Done.
- Git-friendly settings JSON defaults/export/validation through the CLI. Done.
- Project bundle manifest and validation. Done.
- Lesson templates, brand presets, and export presets. Done.
- Display and region recording to `screen.mp4`. Done, needs broader real-device QA.
- Microphone and webcam recording commands. Done, needs device-matrix QA.
- LearnHouse-ready local package export and `.learnhouse.zip` archive. Done.
- Agent-readable manifest output. Done.
- Caption/transcript sidecar exporters. Done.
- Config/template backup planner and local Git init/status/commit workflow with Git-safe include/exclude rules. Done.
- Annotation sidecar commands and live overlay shell. Done.
- AVFoundation render planning/export with webcam picture-in-picture, cursor/click/shortcut burn-in, zoom region burn-in, annotation burn-in, and transcript caption burn-in. Done, needs real-media fixture coverage.

## v1.0

- Harden the first recording flow around a compact recording launcher, Display/Window/Area mode controls, contextual permission preflight, no default auto-stop timer, and source controls for camera, mic, and system audio.
- Replace card-based quick record UX with a floating recorder control bar and in-progress widget that supports elapsed time, pause/resume, stop, restart, delete, hide, and recording flags.
- Harden display recording with permission UX, cancellation, preview, audio-free/video-only reliability, and manual QA.
- Add window recording, exact area selection controls, and roadmap-gated iOS device recording. Window recording and drag-to-select area controls are wired; iOS device recording remains roadmap-gated.
- Harden webcam, microphone, system audio, cursor metadata, click/shortcut metadata capture in combined app workflows. Initial combined app workflow is wired; broader device and permission-matrix QA remains.
- Add recording recovery, Finder/open-url project handling, and richer project bundle creation. Finder/open-url project handling is wired; recovery remains.
- Add a post-recording completion widget with Edit, Save Video, Copy Path, Open Project, Package LearnHouse, and caption/transcript export actions.
- Extend cut-list export into the full render pipeline with webcam PiP/audio/cursor effects/zoom regions/annotations/captions, then add zoom/pan keyframes, webcam PiP controls, canvas styling, and richer render progress. Full render, ProRes MOV export, share packages, and raw asset extraction are wired; GIF/alpha/parallel execution remains behind explicit export gates.
- Expand annotation overlay polish: horizontal/vertical toolbar, pen, highlighter, eraser, line, arrow, box, ellipse, text, spotlight, whiteboard, blackboard, swatches, line weights, text sizes, undo/redo, clear, and frame capture.
- Expand presets/templates to cover capture sources, webcam layout, annotations, zoom behavior, captions, canvas/background, export, and LearnHouse packaging. Project/app preset files are wired; additional bundled preset templates remain.
- Add local transcription model handling. Settings and CLI model-readiness status are wired; runtime execution remains.
- Add Homebrew distribution and signed/notarized DMG. Homebrew cask mirror plus DMG and zip release automation are in place; Apple App ID registration and GitHub release signing secrets are configured for Developer ID signed and Apple-notarized public binaries by default.
- Expand CLI recording control and JSON automation output.
- Add optional GitHub remote setup/restore UX for settings and templates after the local Git workflow has more field use.
- Expand agent workflows for OpenClaw, Codex, and Veritas Kanban. Target-specific workflow JSON is wired; deeper app-control actions remain.
- Add accessibility/compliance and recording-safety passes.

## Post-v1.0

- Additional LMS/video-host connectors. See [Connector Roadmap](CONNECTOR_ROADMAP.md) for the prioritized package-first backlog.
- MCP server wrapping stable CLI commands. A dependency-free stdio wrapper exists for safe read/plan commands; broader write tools remain gated.
- Agent-suggested edits and lesson packaging.
