# Security Policy

## Supported Versions

`dm-lessonmeld` is currently a developer preview. Security fixes target the latest `main` branch and the latest tagged preview release.

## Reporting a Vulnerability

Please report suspected vulnerabilities privately through GitHub Security Advisories for this repository when available, or contact the maintainer through the public profile links.

Do not open a public issue with exploit details, private recordings, credentials, tokens, transcripts, or sensitive media paths.

## Native Security Model

The current native LessonMeld app is local-first:

- No accounts during normal operation
- No telemetry
- No analytics
- No cloud sync
- No hosted media processing
- No license activation

Security-sensitive areas:

- macOS Screen Recording, Microphone, Camera, Accessibility, and Input Monitoring permissions
- Local app-control commands
- Agent-readable manifests
- Project media paths and transcripts
- Git backup/export settings
- Release signing and notarization

Local app-control commands must remain authenticated. Settings, project manifests, and agent output should avoid exposing media paths or transcript contents unless the user explicitly requests them.

## Hosted Community Boundary

The optional community platform is an accepted architecture, not a currently supported production service. It will be separately deployed and will receive only explicit Publications of selected derived assets and metadata. Native `.dmlm` projects, raw captures, local paths, and unselected transcripts remain local by default.

Before hosted production launch, the hosted codebase must publish its own supported-version policy, private vulnerability-reporting path, tenant-isolation threat model, authorization and audit controls, data retention/export/deletion behavior, dependency and infrastructure gates, and incident ownership. See `docs/COMMUNITY_PLATFORM_ARCHITECTURE.md` for the required baseline. This native policy must not be read as security coverage for a future hosted deployment.
