# Bilimbi AI Team — onboarding

**Document Type:** Onboarding
**Last Updated:** 2026-08-13

Read this once when you join, then work from Issues. This is the only
coordination document; there is no board and no mailbox.

---

## 1. What we are doing

Porting **Belimbing** (Laravel/PHP) to **Bilimbi** (Phoenix/Elixir). Belimbing
is canonical for business meaning and PostgreSQL schema — not for
implementation. We do not translate Laravel into Elixir; we reproduce the
durable contract behind a deep-module API.

Read before touching code: root [`AGENTS.md`](../../AGENTS.md) and
[`DESIGN.md`](../../DESIGN.md), then
[`research/platform-baseline-inventory.md`](./research/platform-baseline-inventory.md)
for what is ported and what remains.

### The canonical source is a specific checkout

```
/home/kiat/repo/laravel/blb    at merge commit e70b4d33c0b10790e681f4c2b5095d85a53bc918
```

`/home/kiat/repo/Belimbing` is **planning material with no `app/` tree**. If
you cite "Belimbing", cite a `laravel/blb` path or you are citing the wrong
thing. This mistake has been made.

---

## 2. Where things live

| What | Where |
|---|---|
| Tasks — one per issue | [Issues](https://github.com/BelimbingApp/bilimbi/issues) |
| Claim, handoff, blocked, review findings | Comments on that issue or PR |
| Who owns it | `agent:<id>` **label** |
| State | `task:ready` / `active` / `review` / `blocked` / `done` |
| Presence, heartbeat, wake, halt | Pinned issue [#43](https://github.com/BelimbingApp/bilimbi/issues/43) |
| RFCs and open questions | [Discussions](https://github.com/BelimbingApp/bilimbi/discussions) |
| Durable architecture decisions | `docs/architecture/decisions/` |
| Stage order and exit gates | [`PORTING_STAGES.md`](./PORTING_STAGES.md) |

**CI refuses coordination writes to `docs/ai-team/`.** Only `README.md`,
`PORTING_STAGES.md` and `research/**` may be added or modified; the
`docs-onboarding` label bypasses it for a genuine onboarding change.
Deletions always pass. If your PR fails that job, your content belongs in an
issue comment.

---

## 3. You have no GitHub identity

`suggestedActors(CAN_BE_ASSIGNED)` returns two human users, and every PR is
authored by one of them. Six-plus agents share those accounts.

So **assignee cannot identify you and neither can authorship.** Two
consequences:

1. Mark ownership with the `agent:<id>` label, not the assignee field.
2. Name yourself in the text of every claim, handoff and review:
   `**From:** <your-agent-id>`.

That convention is the only identity this system has. Never infer who did
something from GitHub metadata.

---

## 4. Working on something

1. **Read** the issue, the inventory, and `AGENTS.md`.
2. **Claim** — comment on the issue saying which paths you will write, and add
   your `agent:<id>` label and `task:active`.
3. **Check** nobody holds those paths. One writer per path.
4. **Work narrowly.** A path you did not claim needs a new comment first, not
   a quiet expansion.
5. **Open a PR.** Green CI plus an independent review — not by you.
6. **Hand off** in a comment: changed paths, validation actually run, known
   limitations, suggested reviewer.

**Shared and hot paths** need the integration steward: `AGENTS.md`,
`README.md`, `mix.lock`, `apps/base/module_registry/**`,
`apps/core/compatibility/**`, `.github/**`, and ADRs. Only one active task may
hold `mix.lock`.

**Prefer a git worktree.** Agents share one checkout, and concurrent edits have
caused non-fast-forward pushes and a mid-edit branch merge. `git worktree add`
against a branch off `origin/main` avoids it; symlink `deps/` from the main
checkout so you skip a full fetch.

---

## 5. Heartbeat and adaptive cadence

**There is no shared scheduler.** Each harness has its own — Claude Code uses
`/loop` in dynamic mode calling `ScheduleWakeup`; other agents use their own
timers. The *mechanism* is yours; the *policy* below is shared, so the team can
predict each other.

Post **one** comment on [#43](https://github.com/BelimbingApp/bilimbi/issues/43)
and **edit it in place** each tick. Its edit time is your liveness signal — a
new comment per tick from six agents buries the signal.

```
tick <agent-id> · <ISO-8601 with offset> · <working on … | idle | blocked: reason>
```

### Choosing your interval

| Situation | Interval |
|---|---|
| A review or claim is pending **on you** | 15–30 min |
| You hold an active task | 15–30 min |
| Waiting on someone else's PR or ACK | 30–45 min |
| Board quiet, nothing assigned | 45–60 min |
| Steward hat | shorter — ACK latency is the job |

Shorten when others are waiting on you; lengthen when you are waiting on them.
Idle ticks more frequent than the work needs are pure cost.

**Read the clock every time: `date -Iseconds`.** Do not carry a remembered
offset. One agent's timestamps ran eleven hours ahead for a whole session
before anyone noticed, and message ordering is the tiebreaker for interleaved
claims.

### Halt

Rate-limited or otherwise stopping? Comment
`halt <agent-id> · <reason>` and say what state you are leaving your work in.
A steward may post `halt all · <reason>`; while that stands with no matching
`resume all`, start no new product work. This is not hypothetical — an agent
hit provider usage limits mid-task and the Integration Steward role stalled.

---

## 6. Ask for permissions

Tokens differ per agent. Known gaps: one agent's token returns `FORBIDDEN` on
Discussions; another lacks `project` scope, so there is no Project board view.

**Ask @kiatng directly on [#43](https://github.com/BelimbingApp/bilimbi/issues/43).**
Do not silently work around it. One agent mirrored another's Discussion posts
by hand for a day before anyone mentioned it.

---

## 7. Lessons that cost us something

Each of these shipped a defect or wasted hours. They are here so you do not
rediscover them.

**Verify against source at the moment you write.** Every wrong claim in this
project came from forming a thesis on one read, then writing it up from memory
— a join type, a count of discovery patterns, a failure mode that did not
exist. Three occurrences from one agent. **Cite the function that produces a
fact, never prose near it**; a comment block listing five examples sat beside a
function returning six patterns.

**Green CI is not evidence that your module runs.** Core User merged, passed
CI, and was **inert** — its migration never ran, because it was missing from
Compatibility's dependency closure and `ModuleRegistry` discovers from
`Application.loaded_applications/0`. The module's own suite passed because it
builds temporary tables and never needs the migration. A test that builds its
own tables is not coverage of migration behaviour.

**A fixture that invents a constraint name stops testing the real one.** A
temporary table declared `email varchar UNIQUE` gets PostgreSQL's
`users_email_key`, while the migration creates `users_email_unique`. The
changeset error became a raised `ConstraintError`. Name constraints in fixtures
exactly as the migration does.

**Never pipe a gate command.** `mix format --check-formatted | tail` reports
`tail`'s exit status, so it prints success over failure. This masked a real
failure twice.

**Root `mix` needs deps first.** `credo`, `sobelow`, `dialyxir` and `mix_audit`
are pinned but not fetched, so root `mix format` and `mix precommit` fail until
`mix deps.get`. Module-level `mix test` works without it — run
`cd apps/<layer>/<module> && mix test`.

**Cross-module foreign keys belong to the *depending* module's migration**, and
the owning module declares them as an `optional_groups` entry. Add every member
of a group in one migration; a partly-present group is reported as an
incomplete contribution.

**Check the driver branch before copying a constraint.** Belimbing's Authz
ownership rule is a `CHECK` on PostgreSQL and *triggers* on SQLite. Requiring
the triggers in a Bilimbi contract would leave verification permanently red.

---

## 8. Reviewing well

Review is the part of this process that has demonstrably worked — it caught a
wrong join type, five errors in a research document, and an operator-path bug
in a Mix task. Reviews here are expected to be adversarial and specific.

- **Verify the claim yourself** rather than accepting the description. Several
  accepted-looking changes were wrong; several review findings were also wrong.
- **Name the exact path and line**, and say what observably breaks.
- **Say what you did not check.** A review that hides its own scope is worse
  than a narrow one.
- **Withdraw findings that turn out to be wrong**, in writing. One reviewer
  required a change that would have made verification permanently red.
- Do not review your own work — including work you specified in detail.

Verdicts: `accept`, `accept with follow-up`, `changes required`.

---

## 9. Fast orientation commands

```bash
# What is installed, and in what resolved order
grep -r 'id:' apps/*/*/bilimbi.module.exs

# Run one module's tests (works without root deps)
cd apps/core/user && mix test

# The real gate: migrate + verify against PostgreSQL
cd apps/core/compatibility && mix test

# Find a Belimbing table's owner
grep -rl "create('<table>'" /home/kiat/repo/laravel/blb/app/*/*/Database/Migrations/

# Raw palette classes outside @theme are defects
grep -rnE '\b(bg|text|border)-(slate|gray|red|green|blue)-[0-9]+' apps/*/lib
```
