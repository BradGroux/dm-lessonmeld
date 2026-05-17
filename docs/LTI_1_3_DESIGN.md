# LTI 1.3 Connector Design

Last reviewed: 2026-05-16

LTI 1.3 is not a package export like LearnHouse, Common Cartridge, SCORM, or xAPI. It is a credentialed launch and deep-link integration that assumes a platform registration, OpenID Connect login initiation, signed JWTs, JWKS key management, and a hosted tool endpoint. LessonMeld currently has no backend and should not add one just to satisfy an LTI checkbox.

## Recommendation

Defer implementation until LessonMeld has one of these:

- A hosted lesson endpoint controlled by the user or Digital Meld.
- A partner platform that hosts the tool endpoint and registration.
- A deliberate server component with key rotation, tenant isolation, audit logs, and support ownership.

## Minimum Architecture

- Tool registration metadata with redirect URIs, JWKS URL, login initiation URL, and deep-link response URL.
- Secure private-key storage and rotation outside `.dmlm` project bundles.
- Launch validation for issuer, audience, nonce, deployment ID, message type, and expiration.
- Deep-link response signing for selected LessonMeld package or hosted lesson resources.
- Explicit user confirmation before returning links or publishing metadata to an LMS.
- Audit records that avoid storing learner data or private course content in app logs.

## Risks

- A local-only desktop app cannot reliably serve LTI launch URLs without tunneling or a hosted endpoint.
- Mismanaged JWT keys or platform registrations can expose course launch data.
- LTI platform behavior differs across LMS vendors; certification-level compatibility needs a real test matrix.

## Non-Goals

- No LTI implementation in the current local-first app.
- No project-bundle credential storage.
- No background publish or deep-link response without explicit confirmation.
