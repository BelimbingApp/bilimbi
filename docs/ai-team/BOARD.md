# Bilimbi AI Team Board

**Board Version:** 4
**Current Stage:** S1 — Platform Baseline business identity
**Coordination Steward:** amp/kimi-k3
**Integration Steward:** Unassigned
**Baseline Commit:** `54b50b0`
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
| [BLB-S1-001](./tasks/BLB-S1-001.md) | active — grandfathered | parent-thread/codex | Module implementer | `apps/core/geonames/**` | Uncommitted work existed before this board; do not touch or stage it |
| [BLB-S1-003](./tasks/BLB-S1-003.md) | active — grandfathered | parent-thread/codex | Module implementer | `apps/core/employee/**` | A 19:34+08 relocation to a `people` Domain container was reverted by its owner; module is back in Core with a coherent descriptor; see `BLB-S1-005` |
| [BLB-S1-004](./tasks/BLB-S1-004.md) | active — grandfathered | parent-thread/codex | Module implementer | `apps/core/company/**` | Registered by amp/kimi-k3; do not touch or stage it |
| [BLB-S1-002](./tasks/BLB-S1-002.md) | active | claude/opus-5 | Source analyst | `docs/ai-team/research/platform-baseline-inventory.md` | Research only; no product path claimed |

## Ready

No tasks are currently ready. The steward opens contract tasks from the
accepted [platform baseline inventory](./research/platform-baseline-inventory.md)
once `BLB-S1-002` passes review.

## Backlog

The steward creates further implementation tasks only after the source
inventory establishes dependencies and ownership. User, Base Authz, Settings,
Audit, and their Web workflows must not be started as one broad parallel port.

## Review

No tasks are awaiting review.

## Blocked

No registered tasks are blocked. `BLB-S1-005` was closed 2026-08-12 as
resolved-by-reversion: the `people` Domain relocation it questioned was
reverted by its owner, satisfying the card's acceptance criterion. See the
task card for the recorded evidence.

## Integration queue

No shared-file integration task is currently assigned.

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
