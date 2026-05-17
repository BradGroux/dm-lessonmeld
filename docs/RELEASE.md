# Release Guide

This project builds a local macOS app bundle plus versioned DMG and zip artifacts. Tagged public releases must be Developer ID signed and notarized; local preview builds can remain ad-hoc signed for development.

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
bash -n scripts/build-app.sh
bash -n scripts/package-app.sh
bash -n scripts/package-dmg.sh
bash -n scripts/package-release.sh
bash -n scripts/capture-device-matrix-smoke.sh
bash -n scripts/real-media-fixture-smoke.sh
ruby -c Casks/dm-lessonmeld.rb
brew style Casks/dm-lessonmeld.rb
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

Ad-hoc signed preview builds and older zip-only preview releases are suitable for local testing. General users should receive the Developer ID signed and notarized DMG when a release includes one.

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

The workflow fails if the tag does not match `CFBundleShortVersionString`.

The workflow runs:

- `swift build`
- `swift test`
- `plutil -lint Packaging/Info.plist`
- packaging script syntax checks
- `DM_LESSONMELD_REQUIRE_NOTARIZATION=1 scripts/package-release.sh`
- Developer ID signing
- Apple notarization with App Store Connect API key credentials and stapler validation
- SHA256 generation for DMG and zip artifacts

It then creates a GitHub Release and attaches:

- `dm-lessonmeld-VERSION-macos.dmg`
- `dm-lessonmeld-VERSION-macos.dmg.sha256`
- `dm-lessonmeld-VERSION-macos.zip`
- `dm-lessonmeld-VERSION-macos.zip.sha256`

## Required signing secrets

Set these repository secrets before publishing a notarized release:

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

## Homebrew Cask

The public Homebrew tap target is:

```text
github.com/BradGroux/homebrew-tap
```

This repository keeps a mirrored cask at:

```text
Casks/dm-lessonmeld.rb
```

After publishing a GitHub Release, update the mirrored cask and the public tap cask with the release version and SHA256. The current cask installs the zip artifact, so hash the zip unless the cask is intentionally switched to the DMG artifact:

```sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
tmpdir="$(mktemp -d)"
gh release download "v${VERSION}" \
  --repo BradGroux/dm-lessonmeld \
  --pattern "dm-lessonmeld-${VERSION}-macos.zip" \
  --dir "${tmpdir}"
shasum -a 256 "${tmpdir}/dm-lessonmeld-${VERSION}-macos.zip"
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

## Opening local preview builds

Ad-hoc signed preview builds are not notarized. macOS may block them if they are downloaded or moved between machines.

For local testing only:

```sh
xattr -dr com.apple.quarantine "/Applications/Digital Meld LessonMeld.app"
open "/Applications/Digital Meld LessonMeld.app"
```
