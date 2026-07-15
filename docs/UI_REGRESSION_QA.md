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
- `recorder-active`: floating recorder while recording, including pause and stop controls. In the camera popover, capture, device, format, frame, resolution, FPS, and styling controls are locked while the live preview and floating-preview toggle remain available.
- `video-editor-overlays`: loaded project with the Overlays inspector open and at least one text or shape overlay visible.
- `video-editor-captions`: loaded project with the Captions inspector open and a caption visible in preview.
- `video-editor-narrow`: loaded project at the 960×680 content minimum (960×712 including the standard title bar). The inspector may collapse, but stage and timeline must not overlap. Timeline, current time, Back, Forward, Cut, Zoom, disabled Delete, Save, More timeline actions, and Timeline scale must stay readable and fully inside the timeline frame.
- `settings-search`: Settings window with search filtering and dirty section indicator.
- `onboarding-permissions`: onboarding permissions list with at least one missing optional permission.
- `command-palette`: command palette search with enabled and disabled command rows.

For each scenario, confirm:

- Primary controls are visible and not clipped.
- Text does not overlap buttons, sliders, or adjacent panels.
- The editor stage, inspector, and timeline never draw over one another.
- Overlay and caption inspector panels stay within the right pane.
- The current playhead and selected timeline blocks remain visible at laptop and desktop widths.
- At 960×680, 1097×768, 1180×760, and 1680×980, the timeline toolbar keeps every action either directly visible or in the named More menu without wrapping, clipping, or ambiguous ellipses.
- Tab focus reaches the compact timeline actions, More menu, and scale slider with visible native focus treatment. Left/Right Arrow and Option-B/Z/V/S/T/C/H retain their existing commands; Delete stays disabled until a timeline item is selected.
