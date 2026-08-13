# Bilimbi AI Team — onboarding

**Document Type:** Onboarding
**Status:** Active
**Last Updated:** 2026-08-13

Read this once when you join. Everything operational — tasks, claims, status,
liveness — lives in **GitHub Issues**, not in this directory.

## Where things live

| What | Where | Why |
|---|---|---|
| Tasks, one per issue | [Issues](https://github.com/BelimbingApp/bilimbi/issues) | Searchable, filterable, timeline-ordered |
| Your claim, handoff, blocked notice | A comment on that issue | Same place as the work |
| Who owns a task | `agent:<id>` **label** | See the identity note below |
| Task state | `task:ready` / `active` / `review` / `blocked` / `done` | Filterable; no hand-maintained board |
| Presence, heartbeat, wake, halt | Pinned issue [#43](https://github.com/BelimbingApp/bilimbi/issues/43) | One editable comment per agent |
| Team conversation | [Discussions](https://github.com/BelimbingApp/bilimbi/discussions) | RFCs and open questions |
| Code, tests, migrations | The repository | Reviewed through PRs |
| Durable architecture | `docs/architecture/decisions/` | Changing a rule needs review |
| What is ported and what remains | [`research/platform-baseline-inventory.md`](./research/platform-baseline-inventory.md) | The map you should read before claiming a port |
| Stage order and exit gates | [`PORTING_STAGES.md`](./PORTING_STAGES.md) | Why work is sequenced the way it is |

There is no `BOARD.md`. Hand-maintained status drifted from git and idled the
team for five hours; an issue's labels *are* its status.

## Agents have no GitHub identity — this matters

`suggestedActors(CAN_BE_ASSIGNED)` returns two human users, and every PR is
authored by one of them. Six-plus agents share those accounts.

So **assignee cannot identify you** and neither can authorship. Use the
`agent:<id>` label to mark ownership, and name yourself in the text of every
claim, handoff and review:

```
**From:** <your-agent-id>
```

That convention is the only identity the system has. Do not rely on GitHub
metadata to say who you are.

## Working on something

1. **Read** the issue, the inventory, and `AGENTS.md` at the repository root.
2. **Claim** by commenting on the issue and adding your `agent:<id>` label.
   Say which paths you will write.
3. **Check** nobody else holds those paths. One writer per path.
4. **Work narrowly.** New paths you did not claim mean a new comment first,
   not a quiet expansion.
5. **Open a PR.** Product code needs green CI and an independent review — not
   by you.
6. **Hand off** in a comment: changed paths, validation run, known limitations.

Shared and hot paths — `AGENTS.md`, `README.md`, `mix.lock`,
`apps/base/module_registry/**`, `apps/core/compatibility/**`, ADRs — need the
integration steward, whoever currently holds that role on
[#43](https://github.com/BelimbingApp/bilimbi/issues/43).

## Heartbeat

Post **one** comment on [#43](https://github.com/BelimbingApp/bilimbi/issues/43)
and **edit it in place** each tick. Its edit time is your liveness signal.

```
tick <agent-id> · <ISO-8601 with offset> · <working on | idle | blocked: reason>
```

Read the timestamp with `date -Iseconds`. Do not extrapolate it — one agent's
headings ran eleven hours ahead for a whole session before anyone noticed.

If you are rate-limited or must stop, comment `halt <agent-id> · <reason>` and
say what state you are leaving your work in.

## Ask for permissions

If your token cannot do something — post to Discussions, create a Project,
assign an issue — **ask @kiatng directly** on
[#43](https://github.com/BelimbingApp/bilimbi/issues/43). Do not work around
it silently. One agent's Discussions token returned `FORBIDDEN` and another
mirrored their posts by hand for a day before anyone said so.

## Two rules worth internalising

**Verify against source at the moment you write.** Belimbing is canonical.
Every wrong claim in this project's history came from forming a thesis on one
read and then writing it up from memory — a join type, a count of discovery
patterns, a failure mode that did not exist. Cite the function that produces a
fact, never prose near it.

**The cheap guard is not the expensive one.** Path conflicts are rare and git
detects them. The defect that actually shipped was Core User running inert
with green CI because it was missing from Compatibility's dependency closure —
no claim step was aimed at that. Structural checks catch what ceremony cannot.
