# Bilimbi AI Team — onboarding

**Document Type:** Onboarding
**Last Updated:** 2026-08-17

Read once. Everything after that happens on Issues, PRs and the
[presence board](https://github.com/BelimbingApp/bilimbi/issues/208) — not in
this directory.

---

## What we are doing

Porting **Belimbing** (Laravel/PHP) to **Bilimbi** (Phoenix/Elixir). Belimbing
is canonical for business meaning and PostgreSQL schema — not for
implementation. We do not translate Laravel into Elixir; we reproduce the
durable contract behind a deep-module API.

Read root [`AGENTS.md`](../../AGENTS.md) and [`DESIGN.md`](../../DESIGN.md)
before touching code, then the
[port map](https://github.com/BelimbingApp/bilimbi/discussions/73) of what is
done and what remains. Correct the port map in a comment rather than working
around an error; others plan from it.

### The canonical source is a specific checkout

```
/home/kiat/repo/laravel/blb    at merge commit e70b4d33c0b10790e681f4c2b5095d85a53bc918
```

`/home/kiat/repo/Belimbing` is **planning material with no `app/` tree**. If
you cite "Belimbing", cite a `laravel/blb` path or you are citing the wrong
thing. This mistake has been made.

---

## How we work

**Take any unclaimed task. Do not ask permission — not from the user, not from
each other.** Claim it by opening a **draft PR before you write code**:

```bash
git commit --allow-empty -m "claim: <what>"
gh pr create --draft --title "<module>: <what> (#<issue>)"
gh pr edit <n> --add-label "agent:<your-id>"
```

Then add `task:active` to the issue and start.

Claim in the draft PR rather than an issue comment because that is the surface
everyone already queries — `gh pr list` is how each of us finds work, so the
claim registry comes free and nobody has to poll anything extra. Claims posted
as issue comments collided three times in one evening, including once where the
claimant followed the rule: a PR opening is the *end* of the work, so a comment
written at claim time cannot reach someone already building.

**Coordinate with each other, not through the user.** Blocked by a teammate's
path, a missing token, a permission gap? Say so on
[#208](https://github.com/BelimbingApp/bilimbi/issues/208), tag whoever can clear
it, and settle it between you. Nobody is monitoring the board on your behalf.

**One writer per path.** If someone holds it, take something else or agree a
split with them directly.

**Keep the queue full.** When you find work, open an issue. When you finish,
open a PR — green CI plus a review by someone who is not you, then merge. Then
take the next thing.

**Prefer a git worktree.** Agents share one checkout, and concurrent edits have
caused non-fast-forward pushes and a mid-edit branch merge.

Declare dependencies as `Blocked-By: #N` in the issue body so a sweep can clear
them when the blocker closes.

---

## Heartbeat

Set up an adaptive heartbeat, **10–30 minutes**, to continue your contribution
to the project. Be proactive in picking up tasks.

Post one comment on [#208](https://github.com/BelimbingApp/bilimbi/issues/208)
and edit it in place; its edit time is your liveness signal. Read the clock with
`date -Iseconds` — one agent's timestamps ran eleven hours ahead for a whole
session before anyone noticed.

---

## You have no GitHub identity

Two human accounts are shared by every agent, so **neither assignee nor
authorship identifies you.**

- Mark ownership with the `agent:<id>` label — **on the pull request as well as
  the issue.** Across the first run all 120 PRs carried none, and anything
  reasoning about PR ownership was blind.
- Name yourself in every claim, handoff and review: `**From:** <your-agent-id>`.
- Never infer who did something from GitHub metadata.

Sub-agents inherit their parent's label and a brief from the parent rather than
re-reading the corpus.

---

## Where things live

| What | Where |
|---|---|
| Tasks — one per issue | [Issues](https://github.com/BelimbingApp/bilimbi/issues) |
| Port map — what is done, what remains | [Discussion #73](https://github.com/BelimbingApp/bilimbi/discussions/73) |
| Claims, handoffs, blockers, review findings | Comments on that issue or PR |
| Owner and state | `agent:<id>` and `task:*` labels |
| Presence and heartbeat | [Issue #208](https://github.com/BelimbingApp/bilimbi/issues/208) |
| RFCs and open questions | [Discussions](https://github.com/BelimbingApp/bilimbi/discussions) |
| Durable architecture decisions | `docs/architecture/decisions/` |
| Stage order and exit gates | [`PORTING_STAGES.md`](./PORTING_STAGES.md) |

`docs/ai-team/` is these two files and nothing else. Coordination that
reappears here as new files is drift.

---

## Reviewing well

Review is the part of this process that has demonstrably worked — it caught a
wrong join type, five errors in a research document, and an operator-path bug
in a Mix task.

- **Verify the claim yourself** rather than accepting the description.
- **Name the exact path and line**, and say what observably breaks.
- **Say what you did not check.**
- **Withdraw findings that turn out to be wrong**, in writing.
- Do not review your own work — including work you specified in detail.

Verdicts: `accept`, `accept with follow-up`, `changes required`.

**`accept with follow-up` is not the default.** Use it when the finding is
genuinely separable — a different module, a decision someone else owns, or a
fix larger than the PR under review. If the finding is in a file this PR
already touches, or leaves the merged state incomplete, ask for the change
instead. A second PR costs a branch, four gates, a review round and a context
reload; a second commit costs none of those.

The test is whether the merged state works without it. One screen shipped
reachable only by typing its URL, and the button that fixed it was a second PR
against the same file the same hour — everything in it could have been a commit
on the first.

**Before merging someone else's PR, check the branch ref, not just the PR
head.** `gh api repos/:owner/:repo/git/refs/heads/<branch> --jq .object.sha`
against the PR's `headRefOid`. GitHub's PR head lags a push by minutes, so a
merge on green reviews can silently drop the commit the author just pushed.
That is how a known defect reached `main` while its fix sat on the branch.
A **404 from that endpoint on a PR whose state is already `MERGED`** means the
branch was deleted on merge, not that anything diverged — check the state
before reading a missing ref as a problem.

**`hold:author` stops the merge; the author sets it and the author clears
it.** Add the label the moment you find something you intend to fix on the PR,
remove it when the fix is pushed. Anyone may merge a green, reviewed PR they
did not author *unless* it carries that label. This is not an ACK — nobody
waits on anybody, and no reply is owed. It exists because the rule above
assumes a finding is visible when the merge lands, and an author mid-fix is
the one case where it is not.

**A review of a PR opened under your own account silently degrades to
`COMMENTED`.** GitHub blocks self-approval and we share two accounts, so the
review still costs full inference but cannot be recorded as an approval. If a
PR looks stuck with nothing actionable, check this before assuming the board is
quiet.

---

## Lessons that cost us something

Each of these shipped a defect or wasted hours. They are here so you do not
rediscover them.

**Verify against source at the moment you write.** Every wrong claim in this
project came from forming a thesis on one read, then writing it up from memory
— a join type, a count of discovery patterns, a failure mode that did not
exist. **Cite the function that produces a fact, never prose near it**; a
comment block listing five examples sat beside a function returning six
patterns.

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
`bilimbi.module.exs` and asserted it equalled a hand-written copy of the same
descriptor further up the file. It caught nothing, and it made every new module
edit one file owned by someone else: 17 commits, and on one night three
unrelated PRs each needing the same single line. Assert **invariants derived
from discovery**, never a mirror of the values.

**Never pipe a gate command.** `mix format --check-formatted | tail` reports
`tail`'s exit status, so it prints success over failure. This masked a real
failure twice.

**`missing plug dependency` in Geonames is a stale build artifact, not a bug.**
`apps/core/geonames` uses Req's plug adapter to stub HTTP, and
`deps/req/lib/req/plug.ex:1` is `if Code.ensure_loaded?(Plug) do` — evaluated at
*Req's* compile time. If Req compiled before `plug` (declared `only: :test`)
was available, a stub that raises is baked in and persists. Fix:

```bash
cd apps/core/geonames && MIX_ENV=test mix deps.compile req --force
```

Do not "fix" the source — there is nothing wrong with it. Suspect this whenever
a dependency's optional feature is missing despite being in `mix.lock` and
`deps/`.

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

## Fast orientation commands

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

# Serve YOUR branch to look at it (PORT is overridable, default 4000)
cd apps/web && PORT=4002 mix phx.server
```

**Never judge a screen from the long-lived dev server on :4000.** It is
somebody else's checkout, and its contribution snapshot is built once at boot:
a capability contributed after that boot renders as `Unknown` and a merged fix
is simply absent. Twice in one day that staleness was mistaken for a defect and
nearly filed as one. Serve the code under test, then look.
