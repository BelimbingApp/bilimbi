# Bilimbi AI Team — onboarding

**Document Type:** Onboarding
**Last Updated:** 2026-08-20

Read once. Everything after that happens on Issues and PRs — not in this
directory. Where a rule can be a script, it is a script; run those rather than
remembering this page.

---

## What we are doing

Porting **Belimbing** (Laravel/PHP) to **Bilimbi** (Phoenix/Elixir). Belimbing
is canonical for business meaning and PostgreSQL schema — not for
implementation. We do not translate Laravel into Elixir; we reproduce the
durable contract behind a deep-module API.

Note that Belimbing is not perfect: when we discover inconsistencies,
mistakes, or entropy in the course of this project, we should not blindly build
the entropy into Bilimbi. We should correct them in Bilimbi, and raise an issue
in Belimbing so that it can benefit from our discovery.

Read root [`AGENTS.md`](../../AGENTS.md) and [`DESIGN.md`](../../DESIGN.md)
before touching code, then the
[port map](https://github.com/BelimbingApp/bilimbi/discussions/73) of what is
done and what remains. Correct the port map in a comment rather than working
around an error; others plan from it.

### The canonical source is a specific checkout

```
/home/kiat/repo/laravel/blb    operational citation pin 769bc31ddb632f5d2c5acb0fd05b777197df87cc
```

`/home/kiat/repo/Belimbing` is **planning material with no `app/` tree**. If
you cite "Belimbing", cite a `laravel/blb` path or you are citing the wrong
thing. This mistake has been made.

This is the operational citation pin for the checkout agents read, not a
blanket replacement for historical compatibility evidence. ADRs, schema
contracts, and compatibility code may keep older commit citations when that
older commit is the source for the decision they record.

That checkout moves, and a pin written on this page cannot notice by itself.
`.github/scripts/orient.sh` reports where it actually is, whether the pinned
commit is still an ancestor, and which `app/` files changed after it. If an
agent ports or cites a post-pin file, either advance this operational pin in the
same change or cite that newer SHA explicitly. Do **not** advance the pin merely
because Belimbing has new commits.

---

## How we work

**Take any unclaimed task. Do not ask permission — not from the user, not from
each other.** Claim it by opening a **draft PR before you write code**. The
claim script checks the live issue and open-PR registry before it writes
anything, then creates the branch, empty claim commit, draft PR, and labels:

```bash
CLAIM_AGENT=<your-stable-agent-id> .github/scripts/claim.sh <issue-number>
```

It refuses a closed or already-labelled issue and reports any open PR that
already references the issue or carries its claim branch. `CLAIM_BRANCH` and
`CLAIM_TITLE` may override the generated branch and issue-title PR title.

Claim in the draft PR rather than an issue comment because that is the surface
everyone already queries — `gh pr list` is how each of us finds work, so the
claim registry comes free and nobody has to poll anything extra. Claims posted
as issue comments collided three times in one evening, including once where the
claimant followed the rule: a PR opening is the *end* of the work, so a comment
written at claim time cannot reach someone already building.

**Coordinate with each other, not through the user.** Blocked by a teammate's
path, a missing token, a permission gap? Say so **on the issue or PR that the
decision belongs to**, tag whoever can clear it, and settle it between you.
Nobody is monitoring anything on your behalf.

Put it there rather than in a shared thread because that is where the next
person to hit the same question will look. We ran a central presence board for
three rounds; it produced about one comment per delivery event, 89% of them
superseded within the hour, and the rulings written on it became unfindable.
Both are retired: #352's ruling is useful precisely because it lives on #352.

**One writer per path.** If someone holds it, take something else or agree a
split with them directly.

**Keep the queue full.** When you find work, open an issue. When you finish,
open a PR — green CI plus a review by someone who is not you, then merge. Then
take the next thing.

**Merging is a duty, not an assumption.** Eight green, fully-reviewed PRs once
sat unmerged for hours because everyone assumed "anyone may merge" meant
someone would. If you see a PR that is green, reviewed, and unheld — gate it
through *now*, whoever you are (except its author). The steward's heartbeat
runs a drain pass over the whole queue each tick as the backstop, not the
default path.

**Decisions only the owner can make go to the pinned queue** ([#648](https://github.com/BelimbingApp/bilimbi/issues/648)) with the
options pre-analyzed and a recommendation, and the source issue gets
`task:kiatng`. Then move on — do not block, do not re-ask on the issue. One
security decision once waited a full day because it had no surface of its own.

**Decompose before you collide.** A screen file above ~500 lines serving more
than one owner-domain is a coordination bomb: one such file needed three
merge-in cycles on a single PR and serialized an entire lane. Split it into
discovered panels (ADR 0006) *before* continuing feature work on it — panels
gave two agents independent lanes on the same screen the day they landed.

**Prefer a git worktree.** Agents share one checkout, and concurrent edits have
caused non-fast-forward pushes and a mid-edit branch merge.

Declare dependencies as `Blocked-By: #N` in the issue body so a sweep can clear
them when the blocker closes.

---

## Heartbeat

Set up an adaptive heartbeat, **10–30 minutes**, to continue your contribution
to the project. Be proactive in picking up tasks. Read the clock with
`date -Iseconds` — one agent's timestamps ran eleven hours ahead for a whole
session before anyone noticed.

**Before you claim, look at what is already claimed.** One command, always
current:

```bash
gh pr list --repo BelimbingApp/bilimbi --state open \
  --json number,title,isDraft,labels,headRefName
```

Two PRs touching the same file were opened by the same agent within a day of
each other, and one would have silently reverted a capability check from the
other.

If the queue is empty and nothing is unblocked, **say so and idle**. An honest
idle tick costs a few hundred tokens; manufactured work costs a review.

---

## Mechanisms, not rules

Everything in this section is enforced by something that can say no. Prefer it
to anything you remember from this page.

**Merge through the gate.** Run it as its own command and chain the merge to it:

```bash
.github/scripts/gate.sh <pr> <the-sha-you-reviewed> \
  && gh api -X PUT repos/BelimbingApp/bilimbi/pulls/<pr>/merge -f merge_method=merge
```

It checks the branch contains `main`, that every check-run is green **on the SHA
you reviewed**, that no hold is set, that the head has not moved under you, and
that the PR is neither a draft nor conflicting. Pass the reviewed SHA — omit it
and you are gating whatever was pushed since.

Never write the checks and the merge as one command where the merge can still
run. #382 reached `main` **behind** it that way: the warning printed and the
merge went ahead on the next line.

**`gh pr merge` is not the gate and never merges anything here.** It refuses
every PR client-side because `mergeStateStatus` is permanently `BLOCKED`, so its
verdict carries no information in either direction. Use the REST call above.

**Branch protection will not save you.** The "Protect main" ruleset sets
`strict_required_status_checks_policy`, which would have refused that #382
merge — but it also lists both shared accounts as bypass actors with
`bypass_mode: always`, and those accounts are every agent we have. Read it with
`gh api repos/BelimbingApp/bilimbi/rulesets`; the old branch-protection API
returns 404. Until agents have distinct identities, the script is the only
enforcement that exists.

**Holds are labels, never prose.** A hold written as a PR comment was ignored
five times in one session; the label has never been.

| Label | Set by | Cleared by | Means |
|---|---|---|---|
| `hold:author` | the author | the author | mid-fix — do not merge yet |
| `hold:review` | a reviewer | that reviewer | an open finding — do not merge yet |

Add it the moment you have something you intend to fix, and remove it when the
fix is pushed. Neither is an ACK: nobody waits on anybody, and no reply is owed.
Anyone may merge a green, reviewed PR they did not author unless a hold is on it.

---

## You have no GitHub identity

Shared human accounts post for every agent, so **neither assignee nor
authorship identifies you.**

- Your id must be **registered in [`roster.md`](./roster.md)** and unique —
  two concurrent sessions sharing one id caused a false-impersonation
  investigation and made the pair mutually unreviewable to the gate (a marker
  matching the PR's lane is refused as self-review). Starting a session under
  an id the roster shows active elsewhere: pick a suffixed id and register it.
- Mark ownership with the `agent:<id>` label — **on the pull request as well as
  the issue.** Across the first run all 120 PRs carried none, and anything
  reasoning about PR ownership was blind.
- Name yourself in every claim, handoff and review: `**From:** <your-agent-id>`.
- Never infer who did something from GitHub metadata.

**The recording token.** A reviewer PAT (account `faith-tohmm`) lets reviews
*record* on PRs authored under the shared default account. Policy, exactly the
`GH_DISCUSSION_TOKEN` shape: scope it per command, never reconfigure `gh`
globally, never print or commit it, and use it **only** to record a review
(`gh pr review`) on a PR **your agent did not author** — never to author,
push, or merge. The review body still carries your `**From:**` line; the token
supplies the account independence, your marker supplies the agent identity.

```bash
GH_TOKEN=$(cat ~/.secrets/faith_pat) gh pr review <n> --approve --body "..."
```

The token buys independence only against the *default-account* author.
External agents author as `faith-tohmm` too (#635 was), and there the PAT
records a self-review the gate rejects — record from the default account
instead. Rule of thumb: **review from whichever account did not author the
PR**; the gate's verdict line names both sides, so a mistake is visible, not
silent.

Session/socket names are transport, not identity: they rotate (three
misdirected redirects in one night). Address agents by roster id in the
message body and let the recipient disclaim; only `**From:**` lines and
`agent:*` labels identify anyone.

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
| Merge holds | `hold:author`, `hold:review` |
| Gates and sweeps you can run | `.github/scripts/` |
| Who is who — registered agent ids and lanes | [`roster.md`](./roster.md) |
| Owner decisions pending | pinned issue [#648](https://github.com/BelimbingApp/bilimbi/issues/648), label `task:kiatng` |
| UI/UX program — quality bar, review lanes | issue #614 |
| RFCs and open questions | [Discussions](https://github.com/BelimbingApp/bilimbi/discussions) |
| Durable architecture decisions | `docs/architecture/decisions/` |
| Stage order and exit gates | [`PORTING_STAGES.md`](./PORTING_STAGES.md) |

`docs/ai-team/` is these three files and nothing else. Coordination that
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

**Review after the merge when you did not get there first.** Teammates merge
within minutes and that is working as intended — a post-hoc review is a normal
step here, not a failure. It is how the escalation test in #393 was caught
asserting a flash where it should have asserted the store.

**A review of a PR opened under your own account silently degrades to
`COMMENTED`.** GitHub blocks self-approval and we share two accounts, so the
review still costs full inference but cannot be recorded as an approval. If a
PR looks stuck with nothing actionable, check this before assuming the board is
quiet.

---

## Lessons that cost us something

Each of these shipped a defect or wasted hours. They are here so you do not
rediscover them.

**A rule that is not a mechanism is a rule you will break.** Everything in
this file that stayed prose was violated at least once — including by the agent
who wrote it. Everything that became a label or a script held. When you find
yourself writing guidance, ask what would have to exit non-zero for it to be
unnecessary, and write that instead. Then delete the prose: this page is read
cold by every agent that starts, so its length is a tax on all of us.

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

**Never pipe a command whose exit code you are about to read.** `mix compile
--warnings-as-errors | tail` reports `tail`'s zero, and a broken commit was
pushed over exactly that. Paid three separate times in one round, once by the
review gate itself. Capture output to a file or a variable; check `$?` bare.

**A capture is truthful only about its own branch.** Audit-environment
screenshots composite whatever fixes that worktree carries — one showed an
unmerged PR's button as if it were live, and another showed a long-fixed bug
that simply wasn't on that branch. Verify the PR *diff* contains what it
claims; read pixels as evidence about the branch that rendered them.

**Under fail-fast, "CI shows one failure" never means "one failure exists."**
Container test commands halt at the first non-zero child, so a red suite early
in the chain hides every later red. "No such failure reported" and "passing"
are different claims.

**A green claim names the sha the suite actually ran against, checked out
clean.** "Re-verified green at `<sha>`" was once written about a commit that
did not compile: a script had edited the working tree, verification ran
against that dirty tree, and the push missed the uncommitted edit. Three
agents hit variants of claim-before-verify in one night. Before reporting
green: commit everything, confirm `git status` is empty and `HEAD` equals the
sha you are about to name, then run the suite — in that order.

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

## Fast orientation

```bash
.github/scripts/orient.sh
```

Where the canonical checkout really is, what `main` is at, every open PR and who
holds it, unclaimed `task:ready` issues, what is blocked, issues whose labels
make them invisible to those queries, the installed modules in resolved order,
and the three commands worth knowing.

Run it instead of reading this file again. Orientation is our largest repeated
cost — every agent pays it on every start — so it belongs in something that
answers with the current state rather than with what was true when this
paragraph was written.
