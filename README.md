# dm-lessonmeld

`dm-lessonmeld` / **Digital Meld LessonMeld** is a native, local-first macOS recording suite for curriculum builders, workshop leads, and technical teams.

It records lessons into local `.dmlm` project bundles, lets you review and annotate them, renders teaching-ready videos, and packages exports for course workflows without accounts, telemetry, analytics, or cloud processing.

> Status: v0.0.4 developer preview. The core app, CLI, project bundle, recording, annotation, render, export, settings, packaging foundations, and local capture smoke harness are in place. Release automation supports Developer ID signed/notarized DMG and zip artifacts with App Store Connect API key notarization for tagged releases.

## Features

- Native macOS app with standard menu, main window, settings, onboarding, command palette, diagnostics, and local project editor
- Floating recording control bar for display, window, and area capture with microphone, webcam, and system audio controls
- Existing MP4/MOV import that creates a lesson project and opens a preview-first timeline editor immediately
- Local `.dmlm` lesson bundles with screen media, audio/video sidecars, edit decisions, annotations, markers, transcripts, render settings, and export metadata
- Live annotation overlay with cursor, pen, highlighter, eraser, line, box, ellipse, arrow, text, laser pointer, whiteboard, blackboard, colors, line weights, text sizes, undo/redo, copy, and clear controls
- Webcam picture-in-picture settings for aspect ratio, shape, corners, mirroring, border, shadow, timed layout regions, and reactions
- Timeline edit-decision sidecars for trims, cuts, speed regions, markers, zoom regions, timed video overlays, masks, and highlights
- Render planning/export with MP4, MOV, and ProRes MOV output, quality and codec controls, plan-recorded resolution/frame-rate/concurrency settings, hardware acceleration intent, gated alpha/GIF states, webcam PiP, audio gain regions, background music, cursor/click/shortcut effects, zooms, masks/highlights, overlays, annotations, and styled caption burn-in
- Caption and transcript import, local transcription model readiness checks, timeline editing, styling, and sidecar exporters
- Shareable `.dmlpreset` files for reusing project editor styles plus capture, annotation, and export defaults across lesson bundles
- Raw asset extraction and local `.lessonshare` packages with final video, project sidecars, raw media, transcripts/captions, and checksums
- Local package export for course publishing workflows
- Git-safe settings/template backup planning for non-sensitive config
- Agent-readable project manifests, target-specific workflow JSON, a stdio MCP wrapper for safe CLI tools, and Keychain-backed signed local app-control messages for automation
- `dmlesson` CLI for capture, project, edit, render, export, package, settings, config backup, annotations, transcription status, and app-control workflows

## Documentation

- [Usage guide](docs/USAGE.md)
- [Architecture notes](docs/ARCHITECTURE.md)
- [Release guide](docs/RELEASE.md)
- [Capture device QA](docs/CAPTURE_DEVICE_QA.md)
- [Codebase audit](docs/CODEBASE_AUDIT.md)
- [Product requirements](docs/PRD.md)
- [Roadmap](docs/ROADMAP.md)
- [LearnHouse export](docs/LEARNHOUSE_EXPORT.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Mac Requirements

- macOS 15 Sequoia or later
- Screen Recording permission for screen, window, and region capture
- Microphone permission for instructor audio
- Camera permission for webcam picture-in-picture
- Accessibility and Input Monitoring permissions for optional local interaction metadata and global shortcuts
- Swift 6.1 compatible toolchain and Xcode command line tools for source builds

The first-run onboarding window checks these permissions and links to the relevant **System Settings > Privacy & Security** panes. You can reopen onboarding from the app sidebar.

## Install from a Release

For signed public releases that include a notarized DMG, download the DMG from GitHub Releases:

```text
dm-lessonmeld-VERSION-macos.dmg
```

Open the DMG, drag **Digital Meld LessonMeld.app** to Applications, then open the app and grant macOS permissions when prompted.

The release zip remains attached for automation and cask update workflows. Older preview releases may be zip-only; those are not the DMG-first public distribution path. Local ad-hoc preview builds can still require the Gatekeeper workaround in [docs/RELEASE.md](docs/RELEASE.md#opening-local-preview-builds).

## Install with Homebrew

The intended public install path is the dedicated `BradGroux/tap` Homebrew tap:

```sh
brew tap BradGroux/tap
brew install --cask dm-lessonmeld
```

Fallback direct tap path:

```sh
brew tap BradGroux/dm-lessonmeld https://github.com/BradGroux/dm-lessonmeld
brew install --cask bradgroux/dm-lessonmeld/dm-lessonmeld
```

## Clone

```sh
git clone https://github.com/BradGroux/dm-lessonmeld.git
cd dm-lessonmeld
```

## Run from Source

```sh
swift run DMLessonMeld
swift run dmlesson --help
```

## Build a Local App Bundle

```sh
scripts/build-app.sh
open "Packaging/Digital Meld LessonMeld.app"
```

The generated app bundle is ad-hoc signed for local testing. Public releases should be Developer ID signed and notarized before broad distribution.

## Package a Release

```sh
scripts/package-release.sh
```

Optional release environment:

```sh
CODESIGN_IDENTITY="Developer ID Application: Example" scripts/package-release.sh
CODESIGN_IDENTITY="Developer ID Application: Example" NOTARIZE_PROFILE="dm-lessonmeld" scripts/package-release.sh
DM_LESSONMELD_REQUIRE_NOTARIZATION=1 CODESIGN_IDENTITY="Developer ID Application: Example" NOTARIZE_PROFILE="dm-lessonmeld" scripts/package-release.sh
DM_LESSONMELD_REQUIRE_NOTARIZATION=1 CODESIGN_IDENTITY="Developer ID Application: Example" NOTARIZE_KEY_PATH="/path/AuthKey_ABC123.p8" NOTARIZE_KEY_ID="ABC123" NOTARIZE_ISSUER_ID="00000000-0000-0000-0000-000000000000" scripts/package-release.sh
```

Release packaging emits both `.zip` and `.dmg` paths and writes artifacts under `.build/dist`.

See [docs/RELEASE.md](docs/RELEASE.md) for the full release checklist.

## Build and Test

```sh
swift build
swift test
scripts/cli-smoke-tests.sh
```

MCP wrapper smoke:

```sh
scripts/dmlesson-mcp-server.py --self-test
```

## CLI Examples

Safe JSON and docs-drift checks run in `scripts/cli-smoke-tests.sh`. Recording commands require local macOS permissions and real devices; use `scripts/capture-device-matrix-smoke.sh` for those capture passes.
Use `scripts/real-media-fixture-smoke.sh` with local MP4/MOV or `.dmlm` fixtures when validating render behavior against representative media.
Use `scripts/dmlesson-mcp-server.py` as a local stdio MCP wrapper for safe inspect, plan, manifest, workflow, and transcription-status tools.

```sh
swift run dmlesson permissions status --json
swift run dmlesson settings defaults --json
swift run dmlesson record display --duration 10 --output /tmp/screen.mp4
swift run dmlesson record region --duration 10 --output /tmp/region.mp4 --x 0 --y 0 --width 1280 --height 720
swift run dmlesson record windows --json
swift run dmlesson record window --window-id 123 --duration 10 --output /tmp/window.mp4
swift run dmlesson record microphone --duration 10 --output /tmp/microphone.m4a --format m4a
swift run dmlesson record webcam --duration 10 --output /tmp/webcam.mov
swift run dmlesson project create --lesson-title "Intro" --output /tmp/Intro.dmlm
swift run dmlesson edit validate /tmp/Intro.dmlm --json
swift run dmlesson render plan /tmp/Intro.dmlm --output /tmp/lesson.mp4 --json
swift run dmlesson render export /tmp/Intro.dmlm --output /tmp/lesson.mp4
swift run dmlesson presets create-from-project /tmp/Intro.dmlm --output /tmp/workshop.dmlpreset --name "Workshop"
swift run dmlesson presets apply /tmp/Intro.dmlm --preset /tmp/workshop.dmlpreset
swift run dmlesson project extract-assets /tmp/Intro.dmlm --output /tmp/raw-assets
swift run dmlesson share package /tmp/Intro.dmlm --output /tmp/shares --final-video /tmp/lesson.mp4
swift run dmlesson learnhouse package /tmp/Intro.dmlm --output /tmp/lesson-export --archive
swift run dmlesson config plan ~/.dm-lessonmeld --json
swift run dmlesson app status --json
```

## Privacy

`dm-lessonmeld` is designed to be local-only during normal operation:

- No accounts
- No analytics
- No telemetry
- No cloud sync
- No license activation
- No hosted processing

Project media stays in local `.dmlm` bundles unless you explicitly move or publish it.

## Contributing

Issues and pull requests are welcome. Keep the app native, local-first, dependency-light, and practical for people recording lessons under real deadlines. Start with [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
