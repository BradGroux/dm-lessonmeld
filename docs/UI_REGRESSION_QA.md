# UI Regression QA

LessonMeld has two complementary UI regression layers:

- Model tests verify editor stage, inspector, timeline, recorder-bar, and responsive-toolbar layout contracts without launching AppKit.
- The rendered smoke launches the built macOS app with generated public-safe video, overlay, and caption data. It captures native window screenshots and the accessibility tree, then fails on missing required labels, clipped required controls, or overlapping named panes.

Run both automated layers locally with:

```sh
swift test --filter EditorWorkspaceLayoutTests
scripts/ui-regression-smoke.sh --skip-build
```

Omit `--skip-build` when the app has not been built. The rendered command exercises the overlay editor in Light and Dark appearances, the caption editor in Light and Dark, the 960×680 narrow editor, and the expanded annotation toolbar. It writes disposable screenshots, `report.json` accessibility diagnostics, and the generated fixture under `.build/ui-regression-artifacts/` by default.

## Rendered Gate and Baselines

The rendered gate uses semantic accessibility labels and frames as its primary oracle. Every required control must exist with its reviewed label and remain within a rendered app window. The video preview, editor inspector, and timeline pane must not overlap. The timeline lane viewport scrolls on both axes so content that does not fit remains reachable instead of being clipped.

The overlay editor also has reviewed Light and Dark structural screenshot fingerprints in `Tests/UIRegressionBaselines/`. Each fingerprint averages a dense set of luminance samples within an 8×6 grid. The fixture uses a fixed 1180×680 content size and accent tint so it renders consistently on the 1024×768 hosted runner and larger local displays. Cell averages catch a blank, missing, displaced, or materially changed surface while tolerating font rasterization, backing-scale, color-profile, and system-accent differences. It is intentionally not a byte-for-byte pixel snapshot.

To review a proposed baseline change:

1. Run `scripts/ui-regression-smoke.sh --skip-build --update-baselines`.
2. Inspect both overlay screenshots at identical 1680×980 fixture state and confirm the overlay, caption, inspector, timeline toolbar, and visible timeline lanes are correct.
3. Review the baseline JSON diff. Do not update a baseline merely to make an unexplained failure green.
4. Re-run `scripts/ui-regression-smoke.sh --skip-build` without the update flag.

PR CI runs the rendered command after unit and CLI smoke tests. The workflow retains the public-safe screenshots, AX tree, generated fixture, and error text for seven days on both success and failure. Hosted macOS runners can differ slightly in font antialiasing and backing scale; semantic frame assertions allow only subpixel coordinate tolerance and the structural screenshot comparison allows only the reviewed mean-difference threshold.

Failure triage:

- Read `report.json` first. `missing`, `clipped`, and `overlap` findings identify the failed semantic assertion.
- Compare `00-window.png` with the matching reviewed Light or Dark behavior. Additional numbered screenshots cover other app windows such as the annotation toolbar.
- If `harness-error.txt` exists without a report, inspect fixture generation or app startup before considering a baseline update.
- Reproduce a suspected assertion failure locally by temporarily hiding a required label, moving a required control outside its pane, or overlapping two named panes. Restore the mutation after proving the intended finding.

Increased Contrast and Reduce Transparency remain manual release checks because hosted runners cannot reliably or safely change the protected system accessibility preferences. Confirm those modes with the same fixture and sizes before a release; the annotation toolbar must remain content-independent and the floating materials must preserve separation with reduced transparency.

The rendered gate does not synthesize pointer or keyboard input. Use the visual smoke pass below to verify pointer placement, Tab traversal, native focus treatment, and shortcut activation whenever the affected controls or focus structure change.

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
