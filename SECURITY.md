# Security Policy

## Supported Versions

`dm-lessonmeld` is currently a developer preview. Security fixes target the latest `main` branch and the latest tagged preview release.

## Reporting a Vulnerability

Please report suspected vulnerabilities privately through GitHub Security Advisories for this repository when available, or contact the maintainer through the public profile links.

Do not open a public issue with exploit details, private recordings, credentials, tokens, transcripts, or sensitive media paths.

## Security Model

LessonMeld is local-first:

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
