---
status: accepted
---

# Bootstrap the hosted community on TypeScript, PostgreSQL, and Render

Issue [#288](https://github.com/BradGroux/dm-lessonmeld/issues/288) needs an explicit repository, runtime, and deployment decision before hosted implementation can begin. This ADR records the accepted baseline below. Brad approved repository creation, the named production dependencies, and paid Render staging on 2026-07-15. Production provisioning, credentials, and secrets remain outside that approval.

## Decision

| Concern | Baseline |
| --- | --- |
| Repository | Private `BradGroux/dm-community` repository with `main` as the protected default branch |
| Runtime | Node.js 24 LTS, strict TypeScript, one npm package, and one lockfile |
| Application | One modular monolith with Fastify 5 for HTTP/API seams and a Vite-built React plus React Router member/admin UI |
| Process | One portable Dockerfile running the bootstrap web process; issue #289 adds a worker entrypoint only when the outbox exists |
| Data | One managed PostgreSQL database; every tenant-owned relationship remains tenant-qualified and domain authorization stays mandatory above database row policies |
| Async work | Deferred to issue #289; the bootstrap adds no queue, outbox, Redis, or worker service |
| Local development | Docker Compose for PostgreSQL, deterministic seed data, and the same migration and health commands used in CI |
| Deployment | Render Blueprint with isolated `staging` and protected `production` environments in the Ohio region |
| Production topology | Docker web service and paid Render Postgres with point-in-time recovery; issue #289 adds the background worker |
| Delivery | Production auto-deploy is off; a manual GitHub workflow restricted to `BradGroux` verifies an exact `main`-reachable commit and its required checks before environment-scoped credentials trigger Render; migrations run as a pre-deploy command; readiness gates traffic |
| Deferred adapters | OIDC identity, object storage, email, payments, live video, analytics, AI, and push providers remain separate issue-backed decisions |

The first tracer exposes only a metadata-safe hello-Tenant path, health/readiness endpoints, a migration, and backup/restore evidence. It does not introduce tenant-isolation policy, an outbox, a worker, member identity, content, uploads, analytics, or vendor credentials ahead of their dependency issues.

## Why this baseline

- Node.js 24 is an LTS release and is supported through April 2028. The Node project recommends Active or Maintenance LTS lines for production applications. This gives the new repository a current runtime without selecting the newer Current line. [Node.js release schedule](https://nodejs.org/en/about/previous-releases)
- Strict TypeScript lets the web process, browser client, API contracts, migration tooling, and later worker share one language while keeping domain modules independent of Fastify, React, and Render.
- Fastify 5 supports Node.js 20 and later, provides JSON Schema request/response validation, and has a plugin boundary that can map cleanly to the modular-monolith domains. [Fastify 5 migration guide](https://fastify.dev/docs/latest/Guides/Migration-Guide-V5/) and [Fastify technical principles](https://fastify.dev/docs/latest/Reference/Principles/)
- React Router supports client rendering, server rendering, and static pre-rendering. The first authenticated tracer can remain simple without preventing later SEO-sensitive site pages. [React Router rendering strategies](https://reactrouter.com/start/framework/rendering)
- Render supports Docker builds, Blueprint infrastructure as code, pre-deploy migrations, private networking, and zero-downtime service replacement. A standard Dockerfile keeps the runtime portable to another OCI-capable platform. [Docker on Render](https://render.com/docs/docker) and [Render deploys](https://render.com/docs/deploys)
- A Render Blueprint can define web and worker services, databases, health paths, shutdown windows, projects, and environments. Secret values can remain out of source with `sync: false`. [Render Blueprint specification](https://render.com/docs/blueprint-spec)
- Render deploy hooks can target a specific Git commit, allowing the protected GitHub deployment workflow to name the reviewed SHA instead of a branch tip. The deploy-hook URL is itself a secret. [Render deploy hooks](https://render.com/docs/deploy-hooks)
- GitHub environment secrets are available to private repositories on GitHub Pro, but required environment reviewers on Free, Pro, and Team are limited to public repositories. The private personal-repository baseline therefore uses an allowlisted manual workflow actor instead of claiming an unavailable reviewer gate. [GitHub deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- GitHub reruns use the original run actor's privileges even when another person initiates the rerun. The production workflow must therefore validate both the original and triggering actor and reject reruns. [GitHub rerun behavior](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs)
- Render health checks gate new traffic and retain the prior healthy service when a new deployment never becomes ready. [Render health checks](https://render.com/docs/health-checks)
- Paid Render Postgres provides point-in-time recovery and logical export/restore. Free Postgres does not satisfy the recovery acceptance criteria. [Render PostgreSQL recovery and backups](https://render.com/docs/postgresql-backups)
- Render environments can block private cross-environment traffic and restrict resource deletion, secret access, shell access, and other listed operations to administrators. Render explicitly warns that non-admins can still modify Blueprint-managed protected resources through `render.yaml`, so protected GitHub review is part of the control rather than an optional backstop. [Render projects and environments](https://render.com/docs/projects)

Ohio is the initial region because the first operated Tenant is US-based and this is the closest listed Render region to the maintainer's operating location. This is an inference, not a data-residency conclusion. Render documents that a service region cannot be changed after creation, so the approved region is recorded before provisioning. [Render Blueprint specification](https://render.com/docs/blueprint-spec)

## Repository shape

The bootstrap should remain one repository, one npm package, one lockfile, and one Dockerfile. Directories do not become modules merely to mirror infrastructure:

```text
dm-community/
  src/
    web/                  # Fastify composition root and React application
  modules/
    hello-tenant/         # Deep bootstrap module and its small interface
  platform/
    postgres/             # Database adapter, migrations, transactions, tenant context
    http/                 # Fastify adapter and runtime-validated transport contracts
  test/
    architecture/         # Dependency direction and forbidden-import checks
    integration/          # PostgreSQL, migration, and restore tests
    browser/              # Rendered hello-Tenant and accessibility smoke
  Dockerfile
  compose.yaml
  render.yaml
```

The `web` composition root calls the deep hello-Tenant module through its interface. PostgreSQL and HTTP implementations sit behind internal adapters. A port is added for a true external system only when both production and test adapters justify the seam. Transport types, logging helpers, and configuration stay local to the module that owns their behavior until a second caller proves shared leverage. Issue #289 can deepen the Tenant module and add the worker entrypoint when tenant isolation, audit, and the outbox become real behavior. A service split requires measured load, isolation, or lifecycle evidence and a separate decision.

## Initial dependency boundary

Approval of this ADR should include permission to add the minimum production dependency families needed by the bootstrap:

- Fastify and only the official Fastify plugins required for static assets and HTTP hardening.
- React, React DOM, and React Router.
- `pg` and Kysely for PostgreSQL access, explicit transactions, typed queries, and migrations.
- Ajv for one JSON Schema validation format across HTTP and environment inputs; static type inference may use a development-only JSON Schema type package.

TypeScript, the build tool, linting, unit/integration test tooling, Playwright, accessibility checks, and container scanners are development dependencies. Exact packages and versions must be pinned and reviewed in the bootstrap PR. Authentication, object storage, email, payments, realtime transport, analytics, and AI dependencies are not approved by this baseline.

## Environment and secrets boundary

- Local development uses disposable credentials in ignored files and Docker Compose only.
- CI uses an ephemeral PostgreSQL service and synthetic hello-Tenant data. It receives no staging or production credentials.
- Staging and production are separate Render environments with cross-environment private traffic blocked.
- Production Render auto-deploy is disabled. The normal production deployment path is a manual GitHub Actions workflow that runs only from the default branch and rejects every actor except `BradGroux`.
- The workflow requires both `github.actor` and `github.triggering_actor` to equal `BradGroux` and requires `github.run_attempt == 1`. A retry requires a fresh manual dispatch.
- Before the `production` job receives its environment-scoped deploy hook, it verifies that the requested SHA is reachable from `main` and that required CI completed successfully for that exact SHA.
- The Render workspace launches with only named release administrators. Administrators retain a break-glass ability to deploy or roll back manually; every such use must be reason-coded in the incident/deployment record.
- A `main` ruleset requires a pull request, required CI, linear history, and no force-push or deletion for application, workflow, Dockerfile, migration, and `render.yaml` changes. `CODEOWNERS` records ownership, but required code-owner approval waits until a second maintainer can review Brad's changes without deadlocking the personal repository.
- Render production protection limits resource deletion, secret access/change, shell access, and the other operations documented by Render. It is not described as a complete deploy-approval control.
- `render.yaml` declares secret names with `sync: false`, never values. Generated internal secrets use Render's generated-value mechanism where appropriate.
- Infrastructure changes receive protected GitHub review because a Blueprint commit can alter protected Render resources even when the Render environment is protected.
- Vendor credentials wait for their own issue and are never shared between staging and production.

## Migration, deploy, and rollback contract

1. CI builds the Dockerfile, runs type, lint, unit, integration, migration, architecture, browser, accessibility, and container checks, and records the reviewed source commit plus build evidence.
2. Staging deploys only from a green reviewed commit. The pre-deploy command runs forward-compatible migrations before the new web process becomes eligible for traffic.
3. Readiness checks cover process, database connectivity, migration version, and required internal configuration. Liveness checks do not depend on external vendors.
4. Brad manually dispatches production for an exact SHA. The workflow rejects any other actor, any SHA not reachable from `main`, and any SHA without successful required CI before the `production` environment exposes its deploy hook. Render may rebuild the Dockerfile, but it never builds an unreviewed branch tip or mutable source reference.
5. Application rollback deploys the prior known-good commit. Database changes use expand/contract sequencing; destructive schema changes wait until old application versions can no longer run.
6. A down migration is used only when its data safety is proven. Otherwise, forward repair is the default.
7. Restore verification creates an isolated database, restores a current logical export or recovery point, runs integrity checks, proves the hello-Tenant record, and then destroys the isolated test resource after evidence is retained.

## Required bootstrap evidence

Issue #288 is not complete until the separate repository demonstrates all of the following:

- A private repository with a `main` ruleset, required CI, recorded CODEOWNERS ownership, dependency updates, and secret scanning.
- A clean checkout can install, lint, typecheck, test, build the Dockerfile, migrate up, migrate back where safe, and run the web process.
- `GET /health/live`, `GET /health/ready`, and the hello-Tenant API/UI operate in local, CI, and authorized staging environments.
- The migration path is repeatable from empty and from the prior schema version.
- A failed readiness check leaves the previously healthy deployment serving traffic.
- Production deployment tests prove that a different actor, a different triggering actor, and every rerun attempt fail before environment credentials are available.
- Staging and production secrets are separate, absent from source and logs, and inaccessible to pull-request builds.
- A PostgreSQL backup can be restored into an isolated database and verified with recorded metadata-only evidence.
- The staging browser path passes keyboard and automated accessibility smoke checks.
- Operations documentation covers deploy, rollback, migration failure, restore, secret rotation, incident ownership, and platform exit.

## Alternatives considered

### Azure Container Apps and Azure Database for PostgreSQL

Azure Container Apps has immutable revisions, traffic control, and startup/liveness/readiness probes, so it remains a credible migration target. [Azure Container Apps revisions](https://learn.microsoft.com/en-us/azure/container-apps/revisions) and [health probes](https://learn.microsoft.com/en-us/azure/container-apps/health-probes)

It is not proposed for the first tracer because it requires assembling and operating more separate infrastructure surfaces before proving the product boundary. Reconsider it when enterprise contracts, regional controls, private networking, or existing Digital Meld Azure operations outweigh the simpler Render control plane.

### AWS ECS/Fargate and RDS

AWS can satisfy the target and offers the deepest long-term infrastructure control. It is deferred because the initial one-Tenant tracer does not justify the IAM, networking, registry, load-balancer, container-service, database, secrets, logging, and backup composition burden. The OCI and PostgreSQL boundaries preserve this exit path.

### Vercel plus separate managed vendors

This is rejected for the bootstrap because the mandatory worker, durable jobs, relational recovery, and environment boundary would be distributed across several vendors before the first tracer. It can remain a frontend delivery option later if measured needs justify it.

### Extend the Swift repository or use a Swift server

This repeats the repository-boundary problem already rejected by ADR 0001 and narrows the hosted web ecosystem around the native author's implementation language. The explicit Publication protocol, not a shared runtime, is the supported native/hosted integration boundary.

## Approval record

Brad approved the following scope on 2026-07-15:

1. Create private repository `BradGroux/dm-community`.
2. Configure the new repository's `main` ruleset, required checks, CODEOWNERS ownership, and GitHub `production` deployment environment. The production workflow is manually dispatched and allowlists `BradGroux`; it does not depend on private-repository required reviewers.
3. Use Node.js 24 LTS, strict TypeScript, one npm package, Fastify, React, React Router, PostgreSQL, `pg`, Kysely, and Ajv.
4. Target Render in `ohio` with a Docker web service and paid PostgreSQL. Disable auto-deploy and restrict launch workspace access to named release administrators.
5. Create paid staging resources first. Protected production resources remain deferred until staging evidence passes and Brad separately approves production provisioning.

The approval was explicit: `Approve #240 settings and #288 scaffold plus paid Render staging`. It authorizes items 1 through 4 and the staging portion of item 5. It does not authorize production resources, a public launch, credentials beyond what staging needs, or release publication.

## Consequences

- Create the private repository and execute the bootstrap evidence list through issue-linked work there.
- Provision staging only after the repository baseline and its CI controls are verified.
- Amend this ADR before encoding a materially different repository, runtime, data, or deployment decision.
- Keep production provisioning blocked until staging evidence passes and Brad gives separate approval.
