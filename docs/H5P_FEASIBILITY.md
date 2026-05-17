# H5P Feasibility

Last reviewed: 2026-05-16

H5P should remain a feasibility track, not a committed connector implementation, until package/runtime license boundaries are confirmed. LessonMeld can generate lesson metadata, media references, captions, transcripts, chapters, and checksums locally, but H5P Interactive Video packages also depend on H5P library metadata and runtime behavior that should not be casually bundled into the MIT app.

## Findings

- H5P is most useful for LessonMeld when the output becomes an Interactive Video activity, not as a plain video wrapper.
- A safe first prototype can generate a fixture `.h5p` outside the app bundle from a simple lesson with one video, captions, and chapter-derived interactions.
- The app should not embed H5P runtime libraries until license and redistribution terms are reviewed.
- LMS import behavior varies by H5P host/plugin version, so any implementation needs fixture import checks before it is documented as supported.

## Go/No-Go

Current recommendation: no product implementation yet. Keep H5P as a spike until a generated fixture can be validated in target H5P hosts and the license boundary is documented.

## Follow-Up Criteria

- Generate a fixture `.h5p` from a test project using a repeatable script.
- Document every included H5P library and license.
- Validate import in at least one target H5P host.
- File implementation issues only for the parts that can stay MIT-compatible and local-first.
