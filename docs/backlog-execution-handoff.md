# Backlog execution handoff

Updated: 2026-07-15<br>
Repository: `BradGroux/dm-lessonmeld`

## Audited repository state

- Branch: `main`
- HEAD and `origin/main`: `ca7a76898926b37ed8309c3558c6bd0d75ecc6cf`
- Latest merged PR: [Propose hosted community delivery baseline](https://github.com/BradGroux/dm-lessonmeld/pull/351)
- Latest `main` CI: [passed all gates](https://github.com/BradGroux/dm-lessonmeld/actions/runs/29389199875)
- Open pull requests: 0
- Open issues: 82
- Worktree baseline: only the two user-owned untracked prompt files below. Do not stage, edit, delete, or commit them.
  - `docs/dm-lessonmeld-backlog-execution-goal-prompt.md`
  - `docs/dm-lessonmeld-full-codebase-audit-issues-prompt.md`

## Completed queue

- The original audit backlog through architecture issue [Define community-platform architecture and product boundaries](https://github.com/BradGroux/dm-lessonmeld/issues/220) is complete through merged, green PRs.
- [Map community platform tracer backlog](https://github.com/BradGroux/dm-lessonmeld/pull/350) created and dependency-wired 62 tracer issues, #288 through #349, for every community parent #221 through #238.
- [ADR 0002](adr/0002-hosted-community-runtime-and-deployment-baseline.md) reduces the first community frontier to a concrete proposed repository, runtime, dependency, deployment, security, rollback, and recovery decision.
- The community umbrella [Create community-platform feature map and release sequencing](https://github.com/BradGroux/dm-lessonmeld/issues/239) remains open until all parent and tracer issues are complete.

## Current blockers

### Release signing provenance

[Protect signing secrets behind reviewed release-tag provenance](https://github.com/BradGroux/dm-lessonmeld/issues/240) has no remaining repository-code work. PR [Gate release signing on reviewed provenance](https://github.com/BradGroux/dm-lessonmeld/pull/255) is merged and verified.

Read-only GitHub inspection on 2026-07-15 confirms:

- no GitHub Environments;
- no repository rulesets;
- unprotected `main`;
- all six Apple signing/notarization secrets remain repository-scoped.

Explicit approval is required to:

1. Create and protect the `release-signing` environment.
2. Create an active `v*` tag ruleset restricting creation, update, and deletion to the approved release path.
3. Re-enter the six Apple secrets at environment scope, verify their names, and remove the repository-scoped copies.

Secret values cannot be read or moved through the GitHub API. Brad must supply them again without placing values in chat, logs, issues, commits, or PRs.

### Hosted community bootstrap

[Bootstrap the hosted community repository and delivery baseline](https://github.com/BradGroux/dm-lessonmeld/issues/288) is the only community implementation frontier. Its body contains the durable approval checklist and links to proposed ADR 0002.

Repository scaffolding requires approval to:

1. Create private repository `BradGroux/dm-community`.
2. Configure its `main` ruleset, required checks, CODEOWNERS ownership, and GitHub `production` environment.
3. Add Fastify, React, React Router, `pg`, Kysely, and Ajv on Node.js 24 LTS with strict TypeScript.

Hosted staging additionally requires approval to use Render `ohio` and create paid Docker web and PostgreSQL resources. Production resources wait until staging evidence passes.

## Resume procedure

1. Refresh GitHub issues, pull requests, settings, `main` CI, remote refs, and worktree state. Live state overrides this handoff.
2. If #240 approval is granted, apply and verify the environment and tag controls without printing secret values. Keep the issue open until all six secrets are confirmed at environment scope and repository copies are removed.
3. If #288 repository/runtime approval is granted, change ADR 0002 to `accepted`, create `BradGroux/dm-community`, apply the approved repository controls, and implement the local/CI bootstrap through an issue-linked PR there.
4. Do not provision Render or incur charges unless paid staging approval is explicit.
5. After #288 is fully demonstrated and closed, continue the topological community sequence from #289. The delivery map in [Community Platform Roadmap](COMMUNITY_PLATFORM_ROADMAP.md) remains authoritative.
6. Keep one active implementation PR at a time, merge only after required checks pass, synchronize `main`, and update this handoff at the next clean boundary.
