# Connector Roadmap

Last reviewed: 2026-05-16

LessonMeld should stay local-first. LearnHouse export remains the active connector surface until its package path is stable across real projects, release builds, and docs. The next connector work should add portable package formats before direct publishing APIs because package exports preserve the current privacy model and avoid storing LMS or video-host credentials.

## Current Architecture Fit

- Project bundles already contain a manifest, media sidecars, captions, transcripts, chapters, editor settings, and optional LearnHouse package metadata.
- `LearnHousePackageBuilder` and `LocalSharePackageBuilder` already produce deterministic directory/package outputs with checksums.
- Render and package flows already run locally, so connector outputs can be built without a backend.
- Direct publish actions are intentionally gated in the UI; future credentialed connectors need explicit confirmation, preview, audit logs, and no background publishing.

## Prioritized Backlog

1. Common Cartridge export
   - Best first expansion because it is a manifest/package format, not a credentialed publish flow.
   - Build a `.imscc` archive with lesson metadata, web content, captions/transcripts as resources, and the rendered video or video-host link when available.
   - Keep Thin Common Cartridge/LTI link cartridges out of the first pass unless an external hosted lesson URL exists.
   - Source: 1EdTech Common Cartridge and Thin Common Cartridge 1.4 candidate final docs: https://www.1edtech.org/standards/cc

2. SCORM package export
   - Useful because buyers and older LMS installations still ask for SCORM even when the content is mostly video.
   - Start with SCORM 1.2 plus a conservative SCORM 2004 option after a compatibility test matrix exists.
   - Package a single launchable HTML player, media assets, caption sidecars, `imsmanifest.xml`, and completion/progress hooks.
   - Do not claim conformance until packages pass ADL/runtime validation against target LMS fixtures.
   - Source: ADL SCORM 2004 testing requirements: https://www.adlnet.gov/assets/uploads/SCORM_2004_4ED_v1_1_TR_20090814.pdf

3. xAPI activity package
   - Good fit for local-first export when paired with a user-supplied LRS endpoint at launch/runtime.
   - Generate a package with an xAPI statement profile, launch page, video events, chapter events, completion events, and local fixture statements for tests.
   - Do not store LRS credentials in project bundles. Runtime endpoints should be user-provided or integrated later through a secure settings store.
   - Source: ADL xAPI specification repository: https://github.com/adlnet/xAPI-Spec

4. Video-host publish handoff
   - Build metadata-first exports before API publishing: title, description, chapters, tags, thumbnail, captions, transcript, and rendered video path.
   - Produce host-specific handoff bundles for YouTube/Vimeo/Kaltura/Panopto-style workflows without requiring credentials.
   - Add direct API publish only after OAuth, credential storage, quota handling, resumable upload, and explicit confirmation are designed.

5. H5P feasibility spike
   - Treat H5P as interactive-content generation, not just a video wrapper.
   - Evaluate whether LessonMeld can create useful H5P Interactive Video content without embedding GPL-incompatible runtime code into the app.
   - A safe first deliverable is an export feasibility report plus a fixture `.h5p` generated from a simple lesson.
   - Source: H5P package definition and technical overview: https://h5p.org/documentation/developers/json-file-definitions and https://h5p.org/technical-overview

6. LTI 1.3 deep-link connector
   - Defer until LessonMeld has a hosted/publishable lesson endpoint or a partner platform to launch.
   - LTI 1.3 is credentialed, server-facing integration work with OpenID Connect/JWT flows and platform registration, which does not match the current no-backend architecture.
   - Source: 1EdTech LTI 1.3 docs: https://site.imsglobal.org/standards/lti/lti-1p3/1p3

## Constraints

- License: avoid bundling GPL or platform-specific runtime code into the MIT app unless the boundary is explicit and legally reviewed.
- Auth: keep API credentials out of `.dmlm` bundles and generated packages.
- Privacy: package exports should not send files or learner data over the network.
- Hosting: package formats can ship now; direct publishing needs user-selected destinations and explicit confirmation.
- Compatibility: each format needs fixture packages and documented target LMS/video-host smoke checks before being advertised as supported.

## Non-Goals For The Next Pass

- No direct LMS or video-host publish implementation before package exports have stable fixtures.
- No hosted LessonMeld backend as a shortcut for LTI.
- No broad connector settings UI until at least one non-LearnHouse package format is implemented.

