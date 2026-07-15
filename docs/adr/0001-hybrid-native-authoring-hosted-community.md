---
status: accepted
---

# Keep native authoring local and place community services behind an explicit publication boundary

LessonMeld will be a hybrid product: this repository remains the native local-first authoring suite, while the community becomes a separately deployed, multi-tenant hosted service. A private `.dmlm` Lesson Project, raw capture, local transcript, media path, and authoring history never leave the Mac unless a person explicitly creates a Publication containing selected derived assets and metadata for one Tenant. Hosted credentials, member content, commerce, messaging, analytics, and moderation do not belong in the native process or its local storage model.

## Considered options

- **Extend this Swift repository into the hosted platform** was rejected because native capture/release concerns and continuously deployed tenant data have different security, runtime, dependency, and operational boundaries.
- **Remain entirely local or self-hosted first** was rejected because identity, messaging, payments, email, push, moderation, and live events require a dependable shared control plane for the intended product.
- **Upload and synchronize complete Lesson Projects** was rejected because it breaks the current privacy posture and couples private source material to hosted availability.

## Consequences

- The first production community launches as one operated Tenant on a tenant-aware model; white-label and self-hosted distribution are deferred.
- A separate hosted codebase and deployment must be approved and bootstrapped before community implementation begins. This repository may add publication contracts and an explicit client, but no implicit cloud sync, hosted credential store, telemetry, or background media upload.
- External identity authenticates; the hosted platform owns Member, role, profile, content, entitlement, consent, and audit records.
- Integration vendors remain replaceable behind owned domain ports. Vendor selection and production dependencies require their own reviewed decisions.
