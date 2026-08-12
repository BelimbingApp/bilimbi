# Bilimbi AI Team Board

**Board Version:** 7
**Current Stage:** S1 — Platform Baseline business identity
**Coordination Steward:** amp/kimi-k3
**Integration Steward:** codex/sol-high
**Baseline Commit:** `163734d` (origin/main; `main` is PR-protected — all
coordination and product changes land via reviewed PR with green checks)
**Team Discussion:** [GitHub Discussions](https://github.com/BelimbingApp/bilimbi/discussions) — the team's cross-machine conversation space; this board remains the ledger of record
**Last Updated:** 2026-08-12

This file is edited only by the active coordination steward. Agents request
changes through their own mailbox as described in [`README.md`](./README.md).

## Stage gate

Stage S1 is in progress. Base Database, ModuleRegistry, Tenancy, Core Company,
Geonames schema/read APIs, Address, Compatibility, and Web shell exist. The
immediate goal is to finish reference-data operation and establish the
remaining Core identity contracts without opening optional Domains or
Extensions.

See [`PORTING_STAGES.md`](./PORTING_STAGES.md) for exit criteria.

## Active reservations

| Task | Status | Owner | Role | Write claim | Note |
|---|---|---|---|---|---|
| [BLB-S1-001](./tasks/BLB-S1-001.md) | review — changes required | parent-thread/codex | Module implementer | `apps/core/geonames/**` | Reviewed by codex/gpt-5; diffs unpublished (local worktree); rework then re-review |
| [BLB-S1-003](./tasks/BLB-S1-003.md) | review — changes required | parent-thread/codex | Module implementer | `apps/core/employee/**` | Reviewed by codex/gpt-5; diffs unpublished (local worktree); rework then re-review |
| [BLB-S1-004](./tasks/BLB-S1-004.md) | review — accept with follow-up | parent-thread/codex | Module implementer | `apps/core/company/**` | Reviewed by codex/gpt-5; follow-up assertion lands at integration |
| [BLB-S1-006](./tasks/BLB-S1-006.md) | active | claude/opus-5 | Module implementer | `apps/core/user/**` | Gated on BLB-S1-007; credentials are pre-hashed only (user-ratified deferral) |
| [BLB-S1-007](./tasks/BLB-S1-007.md) | active | claude/opus-5 | Module implementer | `apps/base/database/**` | SchemaVerifier `:uuid`/`{:char,n}`/`:jsonb`/`:inet`; user-decided scope; warrants careful independent review |

## Ready

| Task | Role sought | Dependencies | Allowed output |
|---|---|---|---|
| [BLB-S1-008](./tasks/BLB-S1-008.md) | Module implementer (codex/sol-high, proposed) | BLB-S1-007 handoff (same path); mailbox CLAIM via PR | `apps/base/database/**` |

Further contract tasks open once the [platform baseline
inventory](./research/platform-baseline-inventory.md) passes review.

## Backlog

The steward creates further implementation tasks only after the source
inventory establishes dependencies and ownership. User, Base Authz, Settings,
Audit, and their Web workflows must not be started as one broad parallel port.

## Review

| Task | Owner | Reviewer | Note |
|---|---|---|---|
| [BLB-S1-002](./tasks/BLB-S1-002.md) | claude/opus-5 | amp/kimi-k3 | Handed off (amended) 2026-08-12T20:44+08; §8.7 verifier finding already spawned BLB-S1-007 |

## Blocked

| Task | Owner | Blocked on | Evidence |
|---|---|---|---|
| [BLB-S1-009](./tasks/BLB-S1-009.md) | codex/sol-high | Review clearance for BLB-S1-001/003; publication of the module diffs via PR; rebase onto post-PR-#1 main | Reviews in `reviews/`; diffs exist only in the parent machine's worktree |

`BLB-S1-005` was closed 2026-08-12 as resolved-by-reversion: the `people`
Domain relocation it questioned was reverted by its owner, satisfying the
card's acceptance criterion. See the task card for the recorded evidence.

## Integration queue

| Task | Integration steward | Scope |
|---|---|---|
| [BLB-S1-009](./tasks/BLB-S1-009.md) | codex/sol-high | Compatibility registration, workspace-boundary tests, root docs/ADRs, fresh-schema replay, `mix precommit` |

## Recently completed checkpoints

| Commit | Outcome | Validation |
|---|---|---|
| `54b50b0` | Self-discovering module graph, Core Geonames schema/read API, and Address normalization constraints | Fresh migration/schema verification and 62-test precommit reported green |
| `1bf5a2e` | Physical deep-module packages and generic self-discovery | Repository history |
| `8d0e1ed` | Explicit-tenancy compatible Platform Baseline | Repository history |

## Steward startup checklist

The first coordinating agent may take the unassigned stewardship by making a
single board-only bootstrap edit and announcing it in its mailbox. It must not
also claim product paths in the same edit.

- Confirm `git status` and register every existing dirty path.
- Create its sender-owned mailbox from the template.
- Set `Coordination Steward` to its stable agent identity.
- Revalidate active claims against the worktree.
- Acknowledge or reject pending `CLAIM` messages.
- Keep product implementation and review assigned to other roles whenever
  more than one agent is available.
