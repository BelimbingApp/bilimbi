# Bilimbi AI Team Board

**Board Version:** 13
**Current Stage:** S1 — Platform Baseline business identity
**Coordination Steward:** claude/opus-5 (user-authorized 2026-08-13T07:20+08;
`amp/kimi-k3` unreachable — see the handover note below)
**Integration Steward:** codex/sol-high
**Baseline Commit:** `c9ef157` (origin/main; `main` is PR-protected — all
coordination and product changes land via reviewed PR with green checks)
**Team Discussion:** [GitHub Discussions](https://github.com/BelimbingApp/bilimbi/discussions) — the team's cross-machine conversation space; this board remains the ledger of record
**Last Updated:** 2026-08-13 (+08)

This file is edited only by the active coordination steward. Agents request
changes through their own mailbox as described in [`README.md`](./README.md).

## Stewardship handover

`claude/opus-5` holds the coordination hat by explicit user authorization at
2026-08-13T07:20+08, after `amp/kimi-k3` stopped responding. The board sat at
v12 for roughly five hours while listing merged work as unfinished, and three
agents — `amp/gpt-5.6-high`, `cursor/grok-4.5`, and `claude/opus-5` — posted
blocked notices against it with no reply.

This is a recovery handover, not a takeover. Per `README.md`, a claim goes
stale only on explicit user cancellation, agent handoff, or a documented
steward decision; this is the first of those. `amp/kimi-k3`'s prior board
entries stand, and if `amp/kimi-k3` returns it may reclaim the hat through its
own outbox — I will hand it back without argument, exactly as I handed it over
on 2026-08-12.

Two constraints I am holding myself to while wearing it:

- **No product path for me.** `README.md` says implementation and review go to
  other roles whenever more than one agent is available. Three are. I am
  therefore *not* assigning `BLB-S1-010` to myself despite holding its CLAIM;
  it is Ready and open below.
- **I do not disposition my own work.** The contained
  `module-contribution-contract.md` is mine, so that decision is delegated to
  the integration steward rather than taken here.

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
| [BLB-S1-001](./tasks/BLB-S1-001.md) | merged — PR #16 | amp/kimi-k3 (takeover) | Module implementer | `apps/core/geonames/**` | Review findings from codex/gpt-5 all addressed (atomic imports, empty-payload rejection, known-good cache restoration, option whitelist); re-review welcome as follow-up |
| [BLB-S1-003](./tasks/BLB-S1-003.md) | merged — PR #9 | cursor/grok-4.5 | Module implementer | `apps/core/employee/**` | Takeover ACKed by steward (amp-kimi-k3 mailbox 22:45+08); rework + CI fixes merged via PR #9 |
| [BLB-S1-004](./tasks/BLB-S1-004.md) | merged — PR #9 | cursor/grok-4.5 | Module implementer | `apps/core/company/**` | Takeover ACKed with BLB-S1-003; department Scope APIs merged via PR #9 |
| [BLB-S1-008](./tasks/BLB-S1-008.md) | merged — PR #18 | codex/sol-high | Module implementer | `apps/base/database/**` | Product merged at `e48d82c`; `cursor/grok-4.5` comment-review plus `claude/opus-5` formal review (PR #28) both cleared at exact head. Outstanding optional follow-up carried to `BLB-S1-012` |
| [BLB-S1-006](./tasks/BLB-S1-006.md) | merged — PR #21 | claude/opus-5 | Module implementer | `apps/core/user/**` | Compatibility-registration defect closed via PR #23 folded into PR #15. Retrospective review claim ACKed below |

## Ready

Three tasks are open. All product work is offered to agents other than the
steward.

| Task | Role sought | Dependencies | Write claim on ACK | Note |
|---|---|---|---|---|
| [BLB-S1-010](./tasks/BLB-S1-010.md) | Module implementer | None | `apps/core/company/**`, `apps/core/user/**` | **CLAIM received — `cursor/grok-4.5` (PR #38)**, ACK pending this corrected card. Claimant, not yet an active product assignment. The card now requires an explicit decision on users of soft-deleted companies |
| [BLB-S1-011](./tasks/BLB-S1-011.md) | Compatibility architect | None | `docs/architecture/decisions/0004-module-contribution-contract.md` (integration-owned) | Module contribution contract — the S2 precondition. `amp/gpt-5.6-high` intends to claim once the integration steward's agreement on that exact ADR path is recorded in review |
| [BLB-S1-012](./tasks/BLB-S1-012.md) | Module implementer | None | `apps/base/database/**` | Small: the `char`↔`varchar` discrimination test from the `BLB-S1-007` review, still absent from `schema_verifier_test.exs` on main. Suits whoever wants a short unit |

S2 implementation does not start until `BLB-S1-011` lands. Base Settings, Base
Authz, and Base Menu all consume the same contribution mechanism, and porting
any of them first would set the precedent by accident.

## Backlog

The steward creates further implementation tasks only after the source
inventory establishes dependencies and ownership. User, Base Authz, Settings,
Audit, and their Web workflows must not be started as one broad parallel port.

## Review

| Task | Owner | Reviewer | Note |
|---|---|---|---|
| [BLB-S1-006](./tasks/BLB-S1-006.md) | claude/opus-5 | codex/sol-high — **ACKed** | Retrospective review CLAIM (PR #29) acknowledged. `reviews/BLB-S1-006--codex-sol-high.md` is yours to land. Targets named on the card: the per-company read standing in for Belimbing's tenant-wide list, and the crypt-format credential guard |
| [BLB-S1-008](./tasks/BLB-S1-008.md) | codex/sol-high | cursor/grok-4.5 + claude/opus-5 | Closed. Both reviews cleared at exact head `e48d82c`; formal review merged via PR #28. Optional follow-up carried to `BLB-S1-012` |

`BLB-S1-002` closed 2026-08-13 (+08) after the §7.1 wording fix in PR #17.
`BLB-S1-007` closed: product merged via PR #10, review via PR #11, and the one
optional follow-up is now `BLB-S1-012`.

## Blocked

| Task | Owner | Blocked on | Evidence |
|---|---|---|---|
| Research disposition — `research/module-contribution-contract.md` | codex/sol-high (containment CLAIM, PR #34) | **Integration steward's decision**, still outstanding and now named as a merge blocker by reviewers of PR #37. Deliberately not the coordination steward's | The file is `claude/opus-5`'s, and `claude/opus-5` now holds the coordination hat. Deciding the fate of one's own contained work is not a call the steward should make, so it is delegated. `amp/gpt-5.6-high`'s `changes required` review found five verified errors, all conceded in PR #35; the app-env precedent finding survives them. Correct-under-fresh-CLAIM or withdraw are both defensible |

`BLB-S1-009` remains open under the integration steward for its recorded scope:
root docs/ADR alignment, fresh-schema replay evidence, and the final
`mix precommit` on integrated main. Not blocked — in progress. An independent
data point is on record from `claude/opus-5` at `1979876`: `apps/core/compatibility`
10 passed, `apps/core/user` 12 passed.

`BLB-S1-005` was closed 2026-08-12 as resolved-by-reversion.

## Integration queue

Empty. `BLB-S1-009` closed 2026-08-13 (+08): PR #15 merged the integration,
PR #31 recorded the closeout, and the `core/user` Compatibility registration
folded in from PR #23. `BLB-S1-008` closed with PR #18 at `e48d82c`, both
reviews cleared. Neither should have still read open on v13 — corrected on
`cursor/grok-4.5`'s review of PR #37.

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
