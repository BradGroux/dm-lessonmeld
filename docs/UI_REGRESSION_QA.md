# UI Regression QA

LessonMeld keeps the CI gate lightweight and deterministic:

- `EditorWorkspaceLayoutSnapshot` verifies editor stage, inspector, and timeline frames do not overlap across desktop, laptop, narrow, and short window sizes.
- `RecorderControlBarLayout` locks the floating recorder bar dimensions so setup and active recording states fit the stable bar width.
- `UIRegressionFixtures.scenarios` names the app surfaces and visible controls that need visual smoke coverage.

Run the automated gate with:

```sh
swift test --filter EditorWorkspaceLayoutTests
```

## Visual Smoke Pass

Use a deterministic local `.dmlm` fixture or a short imported public-domain video. Do not commit large media files.

Check these scenarios:

- `editor-empty`: first-run dashboard at laptop width.
- `recorder-setup`: floating recorder before recording starts.
- `recorder-active`: floating recorder while recording, including pause and stop controls.
- `video-editor-overlays`: loaded project with the Overlays inspector open and at least one text or shape overlay visible.
- `video-editor-captions`: loaded project with the Captions inspector open and a caption visible in preview.
- `video-editor-narrow`: loaded project at the minimum supported editor width; inspector may collapse but stage and timeline must not overlap.
- `settings-search`: Settings window with search filtering and dirty section indicator.
- `onboarding-permissions`: onboarding permissions list with at least one missing optional permission.
- `command-palette`: command palette search with enabled and disabled command rows.

For each scenario, confirm:

- Primary controls are visible and not clipped.
- Text does not overlap buttons, sliders, or adjacent panels.
- The editor stage, inspector, and timeline never draw over one another.
- Overlay and caption inspector panels stay within the right pane.
- The current playhead and selected timeline blocks remain visible at laptop and desktop widths.
