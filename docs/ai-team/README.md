# Bilimbi AI Team — onboarding

**Document Type:** Onboarding
**Last Updated:** 2026-08-17

Read this once when you join, then work from Issues. This is the only
coordination document; there is no board and no mailbox.

---

## 0. What to read, and when

The mandatory corpus — root `AGENTS.md`, `DESIGN.md`, this file and the port map
— is ~78KB ≈ 20K tokens. Reading all of it on every cold start, multiplied by 33
agent identities, was the largest single inference cost of the first run. Read
it in stages.

- **Joining:** §1–§5 below. Enough to claim a task and tick correctly.
- **Before writing code:** `AGENTS.md`, `DESIGN.md`, and the port map entry for
  the capability you are porting — not the whole map.
- **On demand:** §6–§9 below, the ADR your task actually names, and
  [`PORTING_STAGES.md`](./PORTING_STAGES.md) when a stage gate is in question.

**An issue should name its own context set.** "Read `AGENTS.md`" is a 30KB
instruction; "read `AGENTS.md` and ADR 0006" is a targeted one. If you open an
issue, name what the claimant must read. If you claim one that does not, ask
rather than reading everything.

**Sub-agents skip this entirely** — they inherit a brief from their parent (§3).

---

## 1. What we are doing

Porting **Belimbing** (Laravel/PHP) to **Bilimbi** (Phoenix/Elixir). Belimbing
is canonical for business meaning and PostgreSQL schema — not for
implementation. We do not translate Laravel into Elixir; we reproduce the
durable contract behind a deep-module API.

Read before touching code: root [`AGENTS.md`](../../AGENTS.md) and
[`DESIGN.md`](../../DESIGN.md), then the
[Platform Baseline Inventory](https://github.com/BelimbingApp/bilimbi/discussions/73)
— the port map of what is done and what remains. Correct it in a comment
there rather than working around an error; other agents plan from it.

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
| Port map — what is done, what remains | [Discussion #73](https://github.com/BelimbingApp/bilimbi/discussions/73) |
| Claim, handoff, blocked, review findings | Comments on that issue or PR |
| Who owns it | `agent:<id>` **label** |
| State | `task:ready` / `active` / `review` / `blocked` / `done` |
| Presence, heartbeat, wake, halt | Pinned issue [#43](https://github.com/BelimbingApp/bilimbi/issues/43) |
| RFCs, open questions, the port map | [Discussions](https://github.com/BelimbingApp/bilimbi/discussions) |
| Durable architecture decisions | `docs/architecture/decisions/` |
| Stage order and exit gates | [`PORTING_STAGES.md`](./PORTING_STAGES.md) |

**`docs/ai-team/` is these two files and nothing else.** No board, no
mailboxes, no task cards, no review files. If you are about to add one, the
content belongs in an issue comment instead.

A CI gate enforced this briefly while the change bedded in. It was removed once
the team had adopted the norm — so this is now a convention you keep, not a
wall that stops you. Coordination that reappears here is drift, and the first
person to notice should say so.

---

## 3. You have no GitHub identity

`suggestedActors(CAN_BE_ASSIGNED)` returns two human users, and every PR is
authored by one of them. Six-plus agents share those accounts.

So **assignee cannot identify you and neither can authorship.** Two
consequences:

1. Mark ownership with the `agent:<id>` label, not the assignee field — **on the
   pull request as well as the issue.** Across the first run, all 120 PRs
   carried no `agent:` label at all; the convention was applied only to issues.
   Anything that reasons about PR ownership is blind until this holds.
2. Name yourself in the text of every claim, handoff and review:
   `**From:** <your-agent-id>`.

That convention is the only identity this system has. Never infer who did
something from GitHub metadata. Anything automated that needs to know who owns
a PR — a wake gate, a review check — must key off the `agent:` label, because
it is the only identity that exists in machine-readable form.

### Identity is a lane, not a task

The first run created **33 `agent:` labels**; 25 were single-task sub-agents
(`codex-terra-employee-lock-1`, `-user-admin-read-1`, …). Each new identity paid
the cold-start corpus — `AGENTS.md`, `DESIGN.md`, this file and the port map are
~78KB ≈ 20K tokens **before any product code is read**. That was the single
largest inference bill of the run.

**A sub-agent inherits its parent's `agent:` label and receives a written brief
from the parent** — the task, the paths it may write, and the few rules that
bite on those paths. It does not re-read the corpus. Spawn sub-agents freely;
give them new *labels* only when they own work independently and durably.

The same cost shape applies to environment setup: a cold workspace plus the
mandatory corpus is paid before the first token of product work, so keep setup
fast and dependency-cached.

### Spend inference by risk

| Tier | Work |
|---|---|
| Cheap/fast | Wake gates, label hygiene, formatting, rebases, mechanical fixture updates, focused test runs |
| Mid | Implementation inside one declared module boundary |
| Frontier | Schema contracts, cross-module design, ADRs, adversarial and security review |

Parallelise only disjoint tasks with disjoint write sets. Never parallelise
duplicate research. After two failed attempts on the same path, stop and surface
the blocker rather than spending another full context.

---

## 4. Working on something

1. **Read** the issue, the [port map](https://github.com/BelimbingApp/bilimbi/discussions/73), and `AGENTS.md`.
2. **Claim** — comment on the issue saying which paths you will write, and add
   your `agent:<id>` label and `task:active`.
3. **Check** nobody holds those paths. One writer per path.
4. **Work narrowly.** A path you did not claim needs a new comment first, not
   a quiet expansion.
5. **Open a PR.** Green CI plus an independent review — not by you.
6. **Hand off** in a comment: changed paths, validation actually run, known
   limitations, suggested reviewer.

Keep the claim and the handoff to those fields. Long status narratives are the
expensive way to say what a claim packet says in six lines, and they make
resumption cost a re-read.

**Declare blockers machine-readably: `Blocked-By: #N`** in the issue body, not
only in prose. Prose blockers went stale repeatedly — one grooming sweep found
six issues labelled `task:blocked` whose blockers had already closed, and the
next sweep found more, including an issue blocked on a closed issue while its
own implementation sat in open review. A cheap sweep can flip
`task:blocked` → `task:ready` on blocker close only if the dependency is a
field rather than a sentence.

**Push shared seams before the work that depends on them.** Shared contracts,
types and UI primitives belong on a remote branch as soon as they are coherent.
Holding them locally forced sibling screens to hand-roll their own copies, and
the divergence had to be found and corrected afterwards.

**Shared and hot paths** need the integration steward: `AGENTS.md`,
`README.md`, `mix.lock`, `apps/base/module_registry/**`,
`apps/core/compatibility/**`, `.github/**`, and ADRs. Only one active task may
hold `mix.lock`.

**Claim ACKs:** either live steward hat (coordination or integration) may ACK
an uncontested claim. After 30 minutes without an ACK, a claimant may proceed
only when its non-shared, non-hot paths remain uncontested, and only after
announcing on [#43](https://github.com/BelimbingApp/bilimbi/issues/43) that it
is proceeding under the timeout. Shared and hot paths always require an
explicit ACK. The one-writer-per-path rule and independent review before merge
remain mandatory.

**Prefer a git worktree.** Agents share one checkout, and concurrent edits have
caused non-fast-forward pushes and a mid-edit branch merge. `git worktree add`
against a branch off `origin/main` avoids it; symlink `deps/` from the main
checkout so you skip a full fetch.

---

## 5. Heartbeat: cap model invocations, not wake-ups

**There is no shared scheduler.** Each harness has its own — Claude Code uses
`/loop` in dynamic mode calling `ScheduleWakeup`; other agents use their own
timers. The *mechanism* is yours; the *policy* below is shared, so the team can
predict each other.

The first run burned most of its idle budget here. One agent reached
`tick 181, unchanged`: 181 wake-ups, each loading full context, to emit a string
identical to the one before it. The fix is not a longer interval. It is to
separate a **wake-up** (cheap, deterministic) from a **model invocation**
(expensive).

### The pre-LLM gate

Every wake-up runs a deterministic check **before** any model is invoked. If the
gate says nothing is actionable, the tick costs one API call and zero tokens.

```bash
export MY_AGENT_LABEL="agent:<your-id>"

ACTIONABLE=$(gh pr list --state open \
  --json number,isDraft,reviewDecision,labels,statusCheckRollup \
  --jq '[.[]
    | select(.isDraft == false)
    | select(.reviewDecision != "CHANGES_REQUESTED" and .reviewDecision != "APPROVED")
    | select((.labels | map(.name)) as $l
             | ($l | any(startswith("agent:")))
               and ($l | any(. == env.MY_AGENT_LABEL) | not))
    | select((.statusCheckRollup // []) as $c
             | ($c | length) > 0
               and ($c | map(.conclusion // .state // "")
                       | all(. == "SUCCESS" or . == "NEUTRAL" or . == "SKIPPED")))
    | .number] | length')
```

`gh --jq` takes no `--arg`; read the label from `env` as above, or pipe raw
`gh` output to system `jq --arg`. Both are verified. This exact form was run
against the live repo: it correctly excludes a `CHANGES_REQUESTED` PR, a draft,
and a PR whose checks contain a `FAILURE`, while passing PRs whose four checks
all succeeded.

A PR with **no checks yet** is deliberately not actionable — treating an empty
rollup as green would wake you on work CI has not judged. `statusCheckRollup` is
the costly field here; it is fetched because the gate uses it, and if you drop
the CI condition, drop the field with it.

**This gate is blind until PRs carry `agent:` labels** (§3). Verify the
precondition before trusting a zero — an empty result and a broken predicate
look identical.

Quantify over the label **set**, as above. Testing `.labels[].name` element-wise
is wrong twice over: `.labels[].name != $my` is satisfied by any unrelated
label, so the agent wakes on **its own** PRs, and `.labels[]` iterates inside
`select()`, so the result counts labels rather than PRs. A three-PR fixture
returned 4 matches instead of 1 under the element-wise form.

**Notifications are advisory only, never the primary signal.** `gh api
notifications` is scoped to the *account*, and the team shares two accounts —
one agent clearing a notification clears it for everyone driving that PAT.
Mentions and review requests may hint, but revalidate against PR state before
spending tokens.

### Cadence

| Situation | Interval |
|---|---|
| A review or claim is pending **on you** | 15–30 min |
| You hold an active task | 15–30 min |
| Waiting on someone else's PR or ACK | 30–45 min |
| Board quiet, nothing assigned | 45–60 min |
| Steward hat | shorter — ACK latency is the job |

- **Cap model invocations with no material state change at four**, then **park
  at the backoff ceiling — do not stop.** This applies to every role, stewards
  included. Parking is not halting: you keep waking, keep running the gate, and
  keep ticking; you simply stop spending model tokens until the gate says
  something changed.
- **Do not cap wake-ups.** Cheap deterministic observation is what keeps ACK
  latency low.
- **One sleeper, never two.** Either an event watcher or a long fallback
  schedule, not both — the dual arrangement cost roughly two model turns per
  idle cycle, because killing the watcher raised its own notification.
- **Back off:** after two consecutive unchanged ticks, double the interval, cap
  4h, reset on any state change.
- **A self-terminating tick count (`COUNT=N`) is a halt, not a cap.** Use it
  only when you mean to exit, and then §Halt applies — including `wake-on:`.

**Round 2 stopped because this section only knew how to stop.** Every agent
declared a terminal cap — `COUNT=3`, "≤4", "no further check-back",
`stop: true` — and none had a documented way back. Heartbeats went quiet at
`2026-08-17T04:09Z` while work continued until `06:27Z`: #43 was silent through
three open PRs. A cap that ends the agent is not a budget, it is an exit.

Post **one** comment on [#43](https://github.com/BelimbingApp/bilimbi/issues/43)
and **edit it in place** each tick. Its edit time is your liveness signal — a
new comment per tick from six agents buries the signal. #43 collected 58
comments against this rule.

```
tick <agent-id> · <ISO-8601 with offset> · <working on … | idle | blocked: reason>
```

**A tick is one line, ≤140 characters, no prose.** If it needs a paragraph it is
not a tick — it is a comment on the issue it concerns.

**Tick at least once every 4h even when parked, and emit it from the gate
script rather than a model.** An edit-in-place is one API call and zero model
tokens, so an idle tick costs nothing worth saving. This is the floor that makes
silence *mean* something: if a lane has not ticked in 4h it is dead, not quiet,
and someone should say so. Without the floor, an idle agent and a stopped agent
are indistinguishable — which is how round 2 lost two hours before anyone
noticed.

**Read the clock every time: `date -Iseconds`.** Do not carry a remembered
offset. One agent's timestamps ran eleven hours ahead for a whole session
before anyone noticed, and message ordering is the tiebreaker for interleaved
claims.

### Halt

Halt means you are **leaving**, not resting. If you are merely out of useful
work, park (§Cadence) — do not halt.

```
halt <agent-id> · <reason> · wake-on: <observable condition>
```

**No halt without a `wake-on:`.** Name a condition someone else can observe and
act on — `wake-on: PR #202 reviewed`, `wake-on: quota reset ~14:00Z`,
`wake-on: operator`. A halt with no wake condition is an unannounced exit, and
four of them in one round is how the team went dark. Say what state you are
leaving your work in, as before.

A steward may post `halt all · <reason>`; while that stands with no matching
`resume all`, start no new product work. This is not hypothetical — an agent
hit provider usage limits mid-task and the Integration Steward role stalled.

**Restarting is not an agent's job.** Every lane can halt itself, so nothing
inside the team is guaranteed to be awake to restart it. The wake owner must sit
outside the cap: a scheduled workflow that finds lanes whose last tick is older
than the 4h floor, or claims older than their `wake-on:`, and says so on
[#43](https://github.com/BelimbingApp/bilimbi/issues/43). `blocked-by-sweep.yml`
already runs on a 30-minute cron with `issues: write` — extend it rather than
adding a second scheduler.

On a usage-limit signal, stop the watchers too. Background pollers that outlive
the agent keep spending.

### Report one number

Add `tokens: <total>` to your halt line. That is the whole telemetry ask,
because it is the only figure no query can recover — time-to-ACK, stale-blocker
duration and review rework rounds all derive from the GitHub API after the fact,
and a self-reported metric that *could* be derived is just another
hand-maintained mirror. Every cost claim behind this section's policies was
inferred from corpus sizes and comment counts rather than measured; one honest
number per agent per session ends that.

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

**A hand-maintained copy of discoverable state is a coordination bottleneck
wearing a test's clothes.** `workspace_boundary_test.exs` read each
`bilimbi.module.exs` and then asserted it equalled a hand-written copy of the
same descriptor further up the file — a file compared against a copy of itself.
It caught nothing, and it made every new module, and every module that gained a
`web:` key, edit one file owned by someone else: 17 commits, a steward
reservation, and on one night three unrelated PRs from two agents each needing
the same single line. Assert **invariants derived from discovery** — closure
completeness, composition without naming children — never a mirror of the
values. Before adding a fixture that lists modules, paths or descriptors, check
whether discovery can produce the list instead.

**Never pipe a gate command.** `mix format --check-formatted | tail` reports
`tail`'s exit status, so it prints success over failure. This masked a real
failure twice.

**`missing plug dependency` in Geonames is a stale build artifact, not a bug.**
`apps/core/geonames` uses Req's plug adapter to stub HTTP, and
`deps/req/lib/req/plug.ex:1` is `if Code.ensure_loaded?(Plug) do` — evaluated at
*Req's* compile time. If Req compiled before `plug` (declared `only: :test`)
was available, a stub that raises is baked in and persists. Three tests fail
with `** (RuntimeError) missing plug dependency`. Fix:

```bash
cd apps/core/geonames && MIX_ENV=test mix deps.compile req --force
```

18/18 after that. Do not "fix" the source — there is nothing wrong with it.
Suspect this whenever a dependency's optional feature is missing despite being
in `mix.lock` and `deps/`.

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

### Approval has a fan-out of two, and it degrades silently

The team drives two GitHub accounts. GitHub blocks self-approval, so a review of
a PR opened under *your own* account **silently degrades to `COMMENTED`** — the
review still happens and still costs full inference, but cannot be recorded as
an approval. Measured on merged PRs: #184 (opened under one account, reviewed
under the other) shows `CHANGES_REQUESTED` ×3 then `APPROVED`, while #161 shows
**four `COMMENTED` reviews and no approval**, all under one account.

The consequence is structural: **whichever account opened the PR decides which
half of the team may approve it.** When the eligible account's agents were
halted — and two were, on usage limits and on operator stop — a PR could not be
approved no matter how many agents sat idle. If a PR looks stuck with nothing
actionable, check this before assuming the board is quiet.

Until a merge gate exists that reads the `**From:**` convention, say the verdict
in text *and* register the GitHub review when your account allows it. A gate
that automates this must check **both** that the approver's declared `agent:` id
differs from the PR's `agent:` label **and** that the approving account differs
from the PR author account — a text marker alone is author-controlled, and
either check alone leaves the self-approval loop open.

### Bring a second discipline to the problem

Software framing is the default, not the only one. Several of the sharpest
findings in this project came from framing a problem as something other than
code: review availability as a **graph fan-out** problem, heartbeats as
**polling versus interrupts**, coordination overhead as **transaction cost**,
stale blockers as **cache invalidation**, and a token budget as a **constrained
resource** to be allocated by marginal value. When a problem resists, ask how a
mathematician, an economist, an accountant or a control engineer would frame it.

Two guards, because this technique fails in a specific way. **The framing must
end in a claim you can verify** — a path, a line, a command, a number. And
**adopt disciplines, not personalities.** Writing in character optimises for
voice, and every wrong claim in this project came from producing confident prose
faster than it was checked. A framing that makes the analysis better survives
§7; one that only makes it sound better is the failure §7 describes.

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
