# Accessibility and Keyboard QA

Run this checklist before tagging a release or after changing primary app surfaces.

## System setup

- Test in Light and Dark appearances.
- Enable VoiceOver and Full Keyboard Access.
- Enable Reduce Motion and verify toolbar locate actions do not animate.
- Use at least one narrow supported window size and one desktop-size window.

## App navigation

- `Command-K` opens the command palette, focuses search, and every result announces title, state, shortcut, and disabled reason.
- `Command-,` opens Settings, search filters sections, dirty sections announce unsaved changes, and Save/Revert controls are keyboard reachable.
- Sidebar workflow, project, tools, and app rows announce selected state and open the expected surface.
- Onboarding permission rows announce permission name, required/optional state, grant status, and action.

## Recorder

- `Option-Command-R` opens the floating recorder controls.
- Tab reaches capture target, camera, microphone, system audio, annotate, options, start, pause/resume, restart, delete, and stop controls.
- Each icon-only recorder control has a meaningful VoiceOver label, value, and hint.
- During recording, the camera popover announces that capture settings are locked; disabled setup controls cannot change future defaults, while the floating-preview toggle remains keyboard reachable.
- Stopping state announces that recording is stopping and remains keyboard reachable for cancel/retry paths.

## Video Editor

- Space toggles preview playback.
- Left/Right Arrow move the playhead by one second when the timeline is focused.
- `Option-I` and `Option-O` set trim in/out.
- `Option-B`, `Option-Z`, `Option-V`, `Option-S`, `Option-T`, `Option-C`, and `Option-H` add cut, zoom, volume, speed, overlay, caption, and cursor-hide regions.
- Delete removes the selected timeline item.
- `Option-1` through `Option-0`, `Option--`, and `Option-=` switch inspector panels.
- Timeline lanes and blocks announce lane, item title, enabled/selected state, and start/end times.
- Overlay and caption preview items announce selectable edit targets, and all drag-only actions have inspector fields for keyboard editing.
- Zoom enable, seek, and delete controls announce the zoom start time; reaction enable/delete and caption seek/delete controls announce their item type and start time.

## Annotation Tools

- `Option-Command-A` opens and closes annotation tools.
- Tab reaches toolbar orientation, collapse, tools, color swatches, width, text size, undo/redo, lock, visibility, pin, display, copy, clear, settings, and close controls.
- Tool and color controls announce selected state.
- Escape exits the active drawing tool without closing the whole app.

## Export

- Export/package controls announce running/disabled state and remain reachable from the keyboard.
- Render, package, raw asset, frame, and sidecar paths are selectable or revealable without mouse-only interactions.
