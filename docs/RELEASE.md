# Release Guide

This project builds a local macOS app bundle plus versioned DMG and zip artifacts. Tagged public releases use Developer ID signing and Apple notarization by default. Tagged developer-preview releases can be unsigned and non-notarized only when the release workflow is explicitly placed in unsigned-preview mode.

## macOS requirements

- macOS 15 Sequoia or later.
- Screen Recording permission for display, window, and area capture.
- Microphone permission for instructor audio.
- Camera permission for webcam picture-in-picture.
- Accessibility and Input Monitoring permissions for richer local teaching interaction metadata when enabled.

## Version source

The app version is read from:

```text
Packaging/Info.plist
```

Check it with:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Packaging/Info.plist
```

## Verification

Run:

```sh
swift build
swift test
plutil -lint Packaging/Info.plist
plutil -lint Packaging/Entitlements.plist
bash -n scripts/build-app.sh
bash -n scripts/package-app.sh
bash -n scripts/package-dmg.sh
bash -n scripts/package-release.sh
bash -n scripts/verify-cask-release.sh
bash -n scripts/capture-device-matrix-smoke.sh
bash -n scripts/real-media-fixture-smoke.sh
ruby -c Casks/dm-lessonmeld.rb
brew style Casks/dm-lessonmeld.rb
scripts/verify-cask-release.sh
```

Run the app-level keyboard, VoiceOver, layout, capture-device, and real-media fixture checklists in `docs/ACCESSIBILITY_QA.md`, `docs/UI_REGRESSION_QA.md`, and `docs/CAPTURE_DEVICE_QA.md` before tagging a public release. The capture and real-media smoke commands are local-only and should run on a machine where recording permissions, test devices, and representative fixture media are available.

## Build an app bundle

```sh
scripts/build-app.sh release
```

Output:

```text
Packaging/Digital Meld LessonMeld.app
```

## Package a local preview release

```sh
scripts/package-release.sh
```

Output:

```text
.build/dist/dm-lessonmeld-VERSION-macos.dmg
.build/dist/dm-lessonmeld-VERSION-macos.zip
```

Ad-hoc signed preview builds are suitable for local and intentional developer-preview testing. General users should receive the Developer ID signed and notarized DMG.

Both local app bundles and Developer ID signed release bundles embed `Packaging/Entitlements.plist`. Keep the audio input and camera entitlements in that file aligned with the app's Microphone and Camera privacy usage descriptions; otherwise macOS can show the app enabled in Privacy settings while AVFoundation still reports access as unavailable.

## Sign

```sh
CODESIGN_IDENTITY="Developer ID Application: Example LLC (TEAMID)" scripts/package-release.sh
```

## Sign and notarize

For local packaging, use a stored notarytool profile:

```sh
CODESIGN_IDENTITY="Developer ID Application: Example LLC (TEAMID)" \
NOTARIZE_PROFILE="dm-lessonmeld" \
scripts/package-release.sh
```

For release-mode packaging without a local profile, use App Store Connect API key credentials:

```sh
CODESIGN_IDENTITY="Developer ID Application: Example LLC (TEAMID)" \
NOTARIZE_KEY_PATH="/path/AuthKey_ABC123.p8" \
NOTARIZE_KEY_ID="ABC123" \
NOTARIZE_ISSUER_ID="00000000-0000-0000-0000-000000000000" \
DM_LESSONMELD_REQUIRE_NOTARIZATION=1 \
scripts/package-release.sh
```

For release-mode enforcement with a stored profile, add:

```sh
DM_LESSONMELD_REQUIRE_NOTARIZATION=1
```

When this flag is set, packaging fails unless both Developer ID signing and notarization credentials are present. Apple ID/app-specific password notarization remains available for local non-release packaging, but release-mode packaging rejects password arguments to avoid exposing notarization credentials in process argv.

## GitHub release

The tag-driven workflow is:

```text
.github/workflows/release.yml
```

To publish a release, update `Packaging/Info.plist`, commit the change, then push a matching version tag:

```sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
git tag "v${VERSION}"
git push origin "v${VERSION}"
```

Before any secret-bearing job starts, the workflow fails unless all of these are true:

- The tagged commit is reachable from the repository's current default branch.
- The tag exactly matches `v` plus `CFBundleShortVersionString`.
- `CFBundleVersion` is valid numeric build metadata.

The `build-release` job is bound to the protected `release-signing` GitHub Environment. Configure that environment and the release-tag rules below before pushing a release tag. Workflow YAML alone is not the authorization boundary.

### Required GitHub release controls

Configure these repository controls before the next release:

1. Create a GitHub Environment named `release-signing`.
2. Add the approved release reviewer or team. Enable prevent-self-review when at least two maintainers can operate the release path.
3. Limit the environment's deployment tag pattern to `v*`; do not permit arbitrary branches or tags.
4. Store the six Apple signing and notarization secrets listed below as environment secrets. Confirm all six names exist there, then remove their repository-scoped copies so only the protected job can receive them.
5. Create an active tag ruleset for `refs/tags/v*` that restricts tag creation, update, and deletion to the approved maintainer or release automation path. Keep bypass access as narrow as recovery requires.
6. Inspect the environment and tag ruleset through the GitHub API before a release. Do not treat a successful workflow-file review as proof that the repository controls exist.

The provenance job runs without an environment or release secrets. Only after it succeeds can GitHub request approval for the secret-bearing `build-release` job. Publishing still depends on the verified artifacts produced by that job.

### Rejected-release recovery

- If provenance verification rejects the tag, do not approve or retry the secret-bearing job. Correct the version/build metadata on a reviewed default-branch commit, then create the intended tag through the approved tag-ruleset path.
- If an incorrect tag must be removed, use only the tag-ruleset recovery/bypass path and record why it was needed. Never move a tag for an artifact that was already published; increment the version instead.
- If environment approval is rejected, leave the run rejected until the reviewer concern is resolved. A retry must still pass provenance and receive a fresh environment decision.
- If environment secrets are incomplete, repair their names or values in the protected environment. Do not copy them back to repository scope as a workaround.
- If any signing credential may have been exposed, stop the release. Credential rotation is an explicit maintainer action and must not be performed as routine workflow recovery.

Set the release mode before pushing the tag:

- Signed public release: leave `DM_LESSONMELD_RELEASE_MODE` unset, or set the repository variable to `signed`.
- Unsigned developer preview: set repository variable `DM_LESSONMELD_RELEASE_MODE=unsigned-preview` before pushing the tag, then restore it when preview releases are no longer intended.

Signed mode fails closed unless every required Apple signing and notarization secret is present. Unsigned-preview mode is allowed only as an explicit repository decision; partial Apple secret sets fail in either mode. The `BradGroux/dm-lessonmeld` repository is configured with the complete signed-release secret set.

The workflow runs:

- `swift build`
- `swift test`
- `plutil -lint Packaging/Info.plist`
- packaging script syntax checks
- `scripts/package-release.sh`
- Developer ID signing and Apple notarization when release mode is `signed`
- unsigned, non-notarized artifact publication only when release mode is `unsigned-preview`
- SHA256 generation for DMG and zip artifacts
- SHA256 verification before publishing downloaded release artifacts
- mounted DMG content validation
- cask version checks

It then creates a GitHub Release and attaches:

- `dm-lessonmeld-VERSION-macos.dmg`
- `dm-lessonmeld-VERSION-macos.dmg.sha256`
- `dm-lessonmeld-VERSION-macos.zip`
- `dm-lessonmeld-VERSION-macos.zip.sha256`

## Signing secrets

Set these as environment secrets on the protected `release-signing` environment before publishing a signed and notarized release. Do not retain repository-scoped copies after the migration is verified. If any are missing while release mode is `signed`, the tag workflow fails. If only some are configured, the tag workflow fails in every release mode to avoid accidental partial signing state.

- `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64`: base64-encoded `.p12` export containing the Developer ID Application certificate and private key.
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`: password for the `.p12` export.
- `APPLE_DEVELOPER_IDENTITY`: full codesigning identity, for example `Developer ID Application: Example LLC (TEAMID)`.
- `APPLE_NOTARIZATION_KEY_BASE64`: base64-encoded App Store Connect API private key `.p8`.
- `APPLE_NOTARIZATION_KEY_ID`: App Store Connect API key ID.
- `APPLE_NOTARIZATION_ISSUER_ID`: App Store Connect issuer ID.

Create the certificate and notarization key payloads locally:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_ABC123.p8 | pbcopy
```

The Apple App ID is registered as:

```text
io.digitalmeld.dm-lessonmeld
```

## Homebrew Cask

The public Homebrew tap target is:

```text
github.com/BradGroux/homebrew-tap
```

This repository keeps a mirrored cask at:

```text
Casks/dm-lessonmeld.rb
```

Before tagging a cask-backed release, update the mirrored cask with the release version. After the GitHub Release is published, verify the mirrored cask against the downloaded release zip before updating the public tap. The current cask installs the zip artifact, so hash the zip unless the cask is intentionally switched to the DMG artifact:

```sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
tmpdir="$(mktemp -d)"
gh release download "v${VERSION}" \
  --repo BradGroux/dm-lessonmeld \
  --pattern "dm-lessonmeld-${VERSION}-macos.zip" \
  --dir "${tmpdir}"
shasum -a 256 "${tmpdir}/dm-lessonmeld-${VERSION}-macos.zip"
scripts/verify-cask-release.sh "${tmpdir}/dm-lessonmeld-${VERSION}-macos.zip"
rm -rf "${tmpdir}"
```

Validate the public tap before announcing the install path:

```sh
export HOMEBREW_GITHUB_API_TOKEN="$(gh auth token)"
brew untap BradGroux/tap >/dev/null 2>&1 || true
brew tap BradGroux/tap
brew audit --cask --strict --online dm-lessonmeld
brew install --cask --dry-run dm-lessonmeld
brew untap BradGroux/tap
```

Primary install path:

```sh
brew tap BradGroux/tap
brew install --cask dm-lessonmeld
```

Fallback direct tap path:

```sh
brew tap BradGroux/dm-lessonmeld https://github.com/BradGroux/dm-lessonmeld
brew install --cask bradgroux/dm-lessonmeld/dm-lessonmeld
```

## Opening unsigned preview builds

Ad-hoc signed and unsigned preview builds are not notarized. macOS may block them if they are downloaded or moved between machines.

For local testing only:

```sh
xattr -dr com.apple.quarantine "/Applications/Digital Meld LessonMeld.app"
open "/Applications/Digital Meld LessonMeld.app"
```
