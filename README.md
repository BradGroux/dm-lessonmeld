# dm-lessonmeld

`dm-lessonmeld` / **Digital Meld LessonMeld** is a native, local-first macOS recording suite for curriculum builders, workshop leads, and technical teams.

It records lessons into local `.dmlm` project bundles, lets you review and annotate them, renders teaching-ready videos, and packages exports for course workflows without accounts, telemetry, analytics, or cloud processing.

> Status: v0.0.3 developer preview. The core app, CLI, project bundle, recording, annotation, render, export, settings, and packaging foundations are in place. Device-matrix QA, Developer ID signing, notarization, and broader distribution hardening are still release work.

## Features

- Native macOS app with standard menu, main window, settings, onboarding, command palette, diagnostics, and local project editor
- Floating recording control bar for display, window, and area capture with microphone, webcam, and system audio controls
- Existing MP4/MOV import that creates a lesson project and opens a preview-first timeline editor immediately
- Local `.dmlm` lesson bundles with screen media, audio/video sidecars, edit decisions, annotations, markers, transcripts, render settings, and export metadata
- Live annotation overlay with cursor, pen, highlighter, eraser, line, box, ellipse, arrow, text, laser pointer, whiteboard, blackboard, colors, line weights, text sizes, undo/redo, copy, and clear controls
- Webcam picture-in-picture settings for aspect ratio, shape, corners, mirroring, border, shadow, resolution, and FPS
- Timeline edit-decision sidecars for trims, cuts, markers, and zoom regions
- Render planning/export with webcam PiP, cursor/click/shortcut effects, zooms, annotations, and captions
- Caption and transcript sidecar exporters
- Local package export for course publishing workflows
- Git-safe settings/template backup planning for non-sensitive config
- Agent-readable project manifests and signed local app-control messages for automation
- `dmlesson` CLI for capture, project, edit, render, export, package, settings, config backup, annotations, and app-control workflows

## Documentation

- [Usage guide](docs/USAGE.md)
- [Architecture notes](docs/ARCHITECTURE.md)
- [Release guide](docs/RELEASE.md)
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

## Developer Preview Gatekeeper Step

> [!IMPORTANT]
> Current GitHub release downloads are ad-hoc signed and not notarized. macOS Gatekeeper may block them with an "Apple could not verify" dialog until Developer ID signing is configured.
>
> After moving the app to `/Applications`, run:
>
> ```sh
> xattr -dr com.apple.quarantine "/Applications/Digital Meld LessonMeld.app"
> open "/Applications/Digital Meld LessonMeld.app"
> ```
>
> Only do this for builds you trust. See [Opening developer preview builds](docs/RELEASE.md#opening-developer-preview-builds).

## Install with Homebrew

The intended public install path is the dedicated `BradGroux/tap` Homebrew tap:

```sh
brew tap BradGroux/tap
brew install --cask dm-lessonmeld
```

Until releases are Developer ID signed and notarized, Homebrew installs may still need the Gatekeeper preview step above before first launch.

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
```

See [docs/RELEASE.md](docs/RELEASE.md) for the full release checklist.

## Build and Test

```sh
swift build
swift test
```

## CLI Examples

```sh
swift run dmlesson permissions status --json
swift run dmlesson settings defaults --json
swift run dmlesson record display --output /tmp/screen.mp4
swift run dmlesson record region --output /tmp/region.mp4 --x 0 --y 0 --width 1280 --height 720
swift run dmlesson record microphone --output /tmp/microphone.m4a --format m4a
swift run dmlesson record webcam --output /tmp/webcam.mov
swift run dmlesson project create --lesson-title "Intro" --output /tmp/Intro.dmlm
swift run dmlesson edit validate /tmp/Intro.dmlm --json
swift run dmlesson render plan /tmp/Intro.dmlm --output /tmp/lesson.mp4 --json
swift run dmlesson render export /tmp/Intro.dmlm --output /tmp/lesson.mp4
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
