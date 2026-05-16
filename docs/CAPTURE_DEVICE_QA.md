# Capture Device Matrix QA

LessonMeld capture QA is local-only because it touches macOS privacy permissions, screen contents, microphones, cameras, and system audio. The smoke harness writes disposable artifacts to a temp directory by default and separates automated checks from manual permission and app-flow checks.

## One-command Smoke

Dry run without creating recordings:

```sh
scripts/capture-device-matrix-smoke.sh
```

Full local device pass:

```sh
scripts/capture-device-matrix-smoke.sh --all --keep-output
```

Useful options:

- `--record`: capture display, region, and a screen-only `.dmlm` project.
- `--all`: capture display, region, screen-only project, microphone, webcam, system audio, and combined project.
- `--duration 3`: set the capture duration in seconds. Default is `2`.
- `--output /tmp/lessonmeld-smoke`: choose the artifact directory. Default is a timestamped temp directory.
- `--keep-output`: keep the directory path visible for attaching artifacts to a bug report.

Each run writes:

- `summary.tsv` with `PASS`, `SKIP`, `MANUAL`, and `FAIL` rows.
- `logs/*.log` with full command output for each automated check.
- Captured media and `.dmlm` projects when recording options are enabled.

## Real-media Fixtures

Keep real media fixtures outside the repository and point the fixture harness at them:

```sh
scripts/real-media-fixture-smoke.sh --video /path/to/sample.mp4 --project /path/to/captured.dmlm --render --keep-output
```

Use `--video` for raw MP4/MOV files and `--project` for existing `.dmlm` bundles. The harness builds the CLI, copies raw videos into disposable lesson bundles, runs project inspect and render-plan checks, and optionally exports final MP4 files with `--render`.

## Matrix

| Area | Automated by harness | Expected artifact | Notes |
| --- | --- | --- | --- |
| CLI build | Always | `.build/debug/dmlesson` | Proves the current checkout can run smoke commands. |
| Permission status | Always | JSON log | Does not request permissions or change OS state. |
| Window listing | Always | JSON log | Runs `record windows --json` without starting capture. |
| Display capture | `--record` or `--all` | `display.mp4` | Requires Screen Recording permission. |
| Area capture | `--record` or `--all` | `region.mp4` | Captures a 640x360 region at display origin. |
| Screen project capture | `--record` or `--all` | `project-screen.dmlm/screen.mp4` | Also runs `project inspect --json`. |
| Display plus system audio | `--all` or `--record --with-system-audio` | `display-system-audio.mp4` | Requires system audio availability and Screen Recording permission. |
| Microphone capture | `--all` or `--record --with-microphone` | `microphone.m4a` | Requires Microphone permission and an input device. |
| Webcam capture | `--all` or `--record --with-webcam` | `webcam.mov` | Requires Camera permission and a camera. |
| Combined capture | `--all` or `--record --with-combined` | `project-combined.dmlm` with screen, mic, and webcam files | Exercises mixed capture orchestration. |
| Window capture | Manual | `window.mp4` or `.dmlm/screen.mp4` | Run `record windows --json`, choose an ID, then run `record window --window-id <id> ...` or use the app recorder Window mode. |
| Permission denied or revoked | Manual | Explicit error in app or CLI | Revoke Screen Recording, Microphone, or Camera in System Settings and rerun the relevant capture. |
| Missing camera or microphone | Manual | Clear device failure or skipped check | Run on hardware without that device, or disable it at the OS/device layer. |
| Stop timeout and cancel timing | Manual | App status leaves `Stopping` | Start from the app control bar, stop immediately, and verify the status transitions. |

## Triage Rules

- Treat empty media files as failures, even if the command exited successfully.
- Treat permission or device failures as product bugs when the message is missing, vague, or leaves the app stuck.
- Keep captured artifacts local unless the content is safe to share.
- Do not commit generated media or `.dmlm` smoke projects.
- Do not commit real fixture media; commit only scripts, fixture notes, and anonymized failure summaries.
