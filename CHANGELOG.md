# Changelog

## Unreleased

## 0.0.8 - 2026-05-26

- Reworked Settings around a native macOS sidebar/detail layout with standard search and toolbar actions.
- Opened the correct macOS Privacy pane when Microphone or Camera access is missing from the dashboard permission rows.

## 0.0.7 - 2026-05-26

- Made main-dashboard permission warnings actionable so clicking a missing permission opens the native macOS permission flow or System Settings pane.
- Made Settings sections scroll independently so sidebar and detail content remain reachable in shorter windows.

## 0.0.6 - 2026-05-26

- Stopped preparing the local app-control Keychain token during normal app startup so recorder users are not prompted for Keychain access on launch.
- Kept Keychain-backed app-control authentication lazy for explicit CLI/automation commands.

## 0.0.5 - 2026-05-25

- Registered the `io.digitalmeld.dm-lessonmeld` Apple App ID for Digital Meld release signing.
- Configured the GitHub release workflow secrets for Developer ID signed and Apple-notarized DMG and zip artifacts.
- Bumped the app bundle version to `0.0.5` and build number to `5`.

## 0.0.4 - 2026-05-17

- Added a testable support target for app-adjacent render planning and quick-recording completion workflows.
- Split renderer layer construction, audio mixing, and export-session execution out of `RenderService`.
- Added a package-first LMS/video-host connector roadmap.
- Added package-first Common Cartridge, SCORM, xAPI, and video-host handoff exports.
- Added H5P feasibility and LTI 1.3 design docs.
- Hardened recorder startup so pause during countdown blocks capture until recording is resumed.
- Restricted local runtime status writes to owner-only file permissions.
- Rejected symlink escapes in `.lessonshare` and LearnHouse package exports.
- Expanded config backup exclusions for common credential filenames.
- Rebound CLI edit exports to manifest-contained project media when loading edit-decision sidecars.
- Scoped Apple release signing secrets to required workflow steps and switched required release notarization to App Store Connect API key or keychain profile credentials.
- Allowed tagged developer-preview releases to publish unsigned, non-notarized artifacts when Apple signing secrets are not configured.

## 0.0.3 - 2026-05-14

- Added DMG release packaging with optional Developer ID signing and notarization.
- Added release workflow enforcement for signed/notarized tagged builds with DMG and zip checksums.
- Added in-app About/version/build metadata and release-notes link.

## 0.0.1 - 2026-05-13

- Initial developer preview.
- Added the native `Digital Meld LessonMeld` macOS app shell with menu commands, first-run onboarding, settings, command palette, project editor, and floating recorder controls.
- Added local display, region, microphone, webcam, project bundle, render, LearnHouse, settings, config backup, annotations, and agent CLI workflows through `dmlesson`.
- Added local `.dmlm` lesson bundles with JSON sidecars for manifests, edit decisions, annotations, cursor metadata, transcripts, presets, and LearnHouse packaging.
- Added webcam picture-in-picture rendering, webcam shape/aspect/FPS settings, selected microphone persistence, floating webcam preview, timed normalized annotation burn-in, cursor/interaction burn-in, caption burn-in, and zoom render planning.
- Added local app-control status/actions for agent and CLI workflows.
- Added release packaging scripts, GitHub Actions CI/release workflows, a mirrored Homebrew Cask, and app icon assets.
