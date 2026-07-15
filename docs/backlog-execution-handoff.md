# Backlog execution handoff

Updated: 2026-07-15<br>
Repository: `BradGroux/dm-lessonmeld`

## Audited repository state

- State captured at the clean boundary immediately before the documentation-only `issue-288-refresh-backlog-handoff` branch.
- Branch: `main`
- HEAD and `origin/main`: `0443905ea33d09bc3932e623b620178a65abaf6f`
- Latest merged PR: [Accept the hosted community delivery baseline](https://github.com/BradGroux/dm-lessonmeld/pull/353)
- Latest `main` CI: [passed all gates](https://github.com/BradGroux/dm-lessonmeld/actions/runs/29391133343)
- Open pull requests: 0
- Open issues: 82
- Worktree baseline: only the two user-owned untracked prompt files below. Do not stage, edit, delete, or commit them.
  - `docs/dm-lessonmeld-backlog-execution-goal-prompt.md`
  - `docs/dm-lessonmeld-full-codebase-audit-issues-prompt.md`

Hosted repository state:

- Repository: private `BradGroux/dm-community`
- Branch: `main`
- HEAD and `origin/main`: `c5faac7cb3589d5c5e753bb860569b4ef8cd18e0`
- Bootstrap PR: [Bootstrap hosted community staging baseline](https://github.com/BradGroux/dm-community/pull/1), merged
- Latest `main` CI: [passed Verify and Security](https://github.com/BradGroux/dm-community/actions/runs/29392726003)
- Open pull requests: 0

## Completed queue

- The original audit backlog through architecture issue [Define community-platform architecture and product boundaries](https://github.com/BradGroux/dm-lessonmeld/issues/220) is complete through merged, green PRs.
- [Map community platform tracer backlog](https://github.com/BradGroux/dm-lessonmeld/pull/350) created and dependency-wired 62 tracer issues covering every community parent.
- [ADR 0002](adr/0002-hosted-community-runtime-and-deployment-baseline.md) is accepted and records the approved separate repository, runtime, deployment, security, rollback, and recovery baseline.
- The private hosted repository now has a protected `main`, required Verify and Security checks, pinned Gitleaks secret scanning, CODEOWNERS, squash-only merges, read-only workflow permissions, Dependabot security updates, and a `production` GitHub environment restricted to `main` with no deploy secret.
- The merged bootstrap provides Node.js 24 strict TypeScript, a Docker web process, PostgreSQL 18 migrations and rollback, migration-aware readiness, a metadata-safe hello-Tenant API/UI, accessibility and keyboard coverage, backup/restore smoke, and dependency, repository, and image security gates.
- Dependabot PRs that proposed Node.js 26 runtime drift and an unsupported TypeScript 7 upgrade received evidence-backed final dispositions and were closed.
- The community umbrella [Create community-platform feature map and release sequencing](https://github.com/BradGroux/dm-lessonmeld/issues/239) remains open until all parent and tracer issues are complete.

## Current blockers

### Release signing provenance

[Protect signing secrets behind reviewed release-tag provenance](https://github.com/BradGroux/dm-lessonmeld/issues/240) has no remaining agent-executable code or settings work until secret values are re-entered. PR [Gate release signing on reviewed provenance](https://github.com/BradGroux/dm-lessonmeld/pull/255) is merged and verified.

Applied GitHub controls:

- `release-signing` environment with BradGroux as required reviewer;
- custom deployment policy limited to `v*` tags;
- active [Protect release tags ruleset](https://github.com/BradGroux/dm-lessonmeld/rules/18969078) restricting tag creation, update, and deletion.

Remaining user action:

1. Re-enter the six Apple signing and notarization secret values in the `release-signing` environment.
2. Confirm the next explicitly approved real release consumes the environment-scoped secrets.
3. Remove the six repository-scoped copies only after that release succeeds.

Secret values cannot be read or moved through the GitHub API. Never place them in chat, logs, issues, commits, or pull requests.

### Hosted community staging

[Bootstrap the hosted community repository and delivery baseline](https://github.com/BradGroux/dm-lessonmeld/issues/288) remains open only for deployment-time acceptance. Paid Render staging in `ohio` is approved; production provisioning is not approved.

The Render Blueprint has not been applied because the handed-off Chrome tab remains at GitHub sign-in. No Render resource has been created and no charge has started.

After authentication, closure requires:

1. Apply `dm-community/render.yaml` and confirm it creates only the paid staging Docker web service and PostgreSQL database.
2. Restrict workspace access to the approved release administrator.
3. Verify `/health/live`, `/health/ready`, `/api/tenants/demo/hello`, and `/tenant/demo` against the deployed commit.
4. Prove a failed readiness deployment leaves the previously healthy deployment serving traffic.
5. Record managed backup/restore evidence and metadata-safe deployment evidence on the issue.
6. Run keyboard navigation and automated Axe checks against the deployed staging browser path.
7. Verify staging and production secret scopes remain separate, no values appear in source or logs, and pull-request jobs cannot access either scope.

GitHub native Secret Protection cannot be enabled for this user-owned private repository under GitHub's documented availability. The required Security job instead runs pinned Gitleaks scanning and fails closed on findings; [ADR 0002](adr/0002-hosted-community-runtime-and-deployment-baseline.md) records this control explicitly.

There is currently no unblocked implementation issue. The delivery map explicitly blocks [Prove tenant isolation, authorization, audit, and outbox end to end](https://github.com/BradGroux/dm-lessonmeld/issues/289) on [Bootstrap the hosted community repository and delivery baseline](https://github.com/BradGroux/dm-lessonmeld/issues/288). Do not start the contingent issue early.

## Resume procedure

1. Refresh both repositories, GitHub issues, pull requests, settings, CI, remote refs, and worktree state. Live state overrides this handoff.
2. Ask Brad to complete GitHub sign-in in the handed-off Render Chrome tab and say `ready`.
3. Apply and verify the approved paid staging Blueprint without provisioning production.
4. Close [Bootstrap the hosted community repository and delivery baseline](https://github.com/BradGroux/dm-lessonmeld/issues/288) only after every live route, readiness-preservation, backup/restore, access, and documentation acceptance check is evidenced.
5. Continue with [Prove tenant isolation, authorization, audit, and outbox end to end](https://github.com/BradGroux/dm-lessonmeld/issues/289) using [Community Platform Roadmap](COMMUNITY_PLATFORM_ROADMAP.md) as the authoritative frontier.
6. Keep one active implementation PR at a time, merge only after required checks pass, synchronize `main`, and update this handoff at the next clean boundary.
7. Keep [Protect signing secrets behind reviewed release-tag provenance](https://github.com/BradGroux/dm-lessonmeld/issues/240) open until the environment-scoped Apple secrets are proven by an explicitly approved release and the repository-scoped copies are removed.
