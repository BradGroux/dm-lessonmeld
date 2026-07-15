# Contributing

Thanks for helping improve Digital Meld LessonMeld.

## Development Setup

Requirements:

- macOS 15 or later
- Xcode command line tools
- Swift 6.1 compatible toolchain

Run:

```sh
swift build
swift test
scripts/build-app.sh
```

## Project Shape

The repo intentionally keeps a small native Swift package structure:

- `Sources/DMLessonMeld`: macOS app, windows, recorder UI, settings, onboarding, and overlay UI
- `Sources/DMLessonMeldCore`: project bundles, capture, audio, render, templates, annotations, settings, exports, and agents
- `Sources/DMLessonMeldCLI`: `dmlesson` CLI wrapper over core services
- `Tests/DMLessonMeldCoreTests`: core regression coverage

Prefer existing patterns over new abstractions. Keep changes scoped and dependency-light.

## Pull Requests

Good PRs include:

- A clear summary
- The user-facing behavior change
- Tests or verification steps
- Any release, migration, or permission notes

Run the smallest meaningful verification gate before opening a PR:

```sh
swift test
scripts/build-app.sh
```

For packaging changes, also run:

```sh
scripts/package-release.sh
codesign --verify --deep --strict "Packaging/Digital Meld LessonMeld.app"
ruby -c Casks/dm-lessonmeld.rb
```

## Product Guardrails

- Keep native normal operation local-only and fully useful without an account.
- Do not add native telemetry, implicit cloud sync, background media upload, or hosted processing.
- Hosted community work follows `docs/COMMUNITY_PLATFORM_ARCHITECTURE.md` and belongs in the approved hosted codebase. This repository owns only the explicit, metadata-safe Publication contract and client boundary.
- Do not mix hosted service dependencies, credentials, tenant state, or provider SDKs into the native process.
- Do not add production dependencies without explicit approval and a strong reason.
- Do not expose media paths, transcripts, or sensitive project data in agent output by default.
- Keep macOS permissions contextual and understandable.

## License

By contributing, you agree that your contribution is licensed under the MIT License.
