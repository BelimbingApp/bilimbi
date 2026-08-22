# ADR 0015: Review-gate independence by marker identity; account is transport

**Document Type:** Architecture Decision Record
**Status:** Proposed
**Agents:** opus-4.8
**Scope:** How the merge gate judges whether a PR carries a genuine *independent*
review, given that many agents share few GitHub accounts
**Last Updated:** 2026-08-22

## Context

`scripts/review_gate.sh` decides whether a PR carries an independent approval;
the `Independent review present` check (#517) makes that decision block a merge.
The team's agents identify themselves with a machine-readable **`**From:** <id>`
marker** and a matching **`agent:<id>` lane label**, because — as the script's
own header states — *"the team shares [few] GitHub accounts, so GitHub
authorship cannot identify an agent."*

The gate nonetheless required **two** conditions for an approval to count as
independent (review_gate.sh, prior logic):

1. the approving marker's agent id differs from the PR's `agent:*` lane, **and**
2. the approving comment's GitHub **account** differs from the PR author's
   account (`select(.account != $pr.author.login)`).

Condition 2 is structurally broken. Six-plus agents
(amp-gpt-5.6-high, codex/sol-hard-tasks, codex/gpt-5, claude-fable-5,
claude-opus-5, gemini-3.7-flash, opencode/glm-5.3, opus-4.8, …) post through a
handful of shared accounts (`kiatng`, `faith-tohmm`, `chatgpt-codex-connector`).
Which account a comment lands under is a property of *transport*, not of *who
reviewed*. So a genuine cross-agent review is accepted or rejected almost by
coin-flip: #551 and #562 were both finished, accepted, mutation-verified — and
unmergeable — because the reviewing agent happened to post under the same
account as the PR author (#560).

Two further facts sharpen the decision:

- **The account gate does not even stop the spoof it was named for.** Its stated
  purpose was to stop *"the same agent [pasting] a marker under the same PAT."*
  But the two shapes are mechanically identical: a genuine `From: Y` review by
  agent Y under `kiatng`, and a forged `From: Y` comment pasted by author X
  under `kiatng`, are the *same bytes* — same lane, same marker, same account.
  The gate's own fixtures encoded both (`fail_same_account_marker`,
  `fail_spoofed_marker`) and could not tell them apart; the account check simply
  rejected *both*, taxing the honest case to deny a forgery it could not
  actually distinguish.

- **GitHub refuses a same-account formal verdict entirely.** `gh pr review
  --approve` and `--request-changes` both fail with *"Can not \[approve/request
  changes\] on your own pull request"* when reviewer account == author account
  (#561). So under shared accounts, formal `APPROVED` / `CHANGES_REQUESTED`
  review states are *unavailable*, and the only representable verdict is a
  `**From:**`-marked comment. Any gate that trusts the `reviews` array over
  marked comments makes a same-account reviewer's strongest objection read as
  silence.

The marker is therefore the team's only reliable identity signal, and the
account is transport. This same principle already underpins three other
mechanisms — the `**From:**` merge-attribution comment now mandated on every
merge (#671), the agent roster, and the shared-PAT direction rule — so it
deserves one citable record rather than repeated rediscovery per tool.

## Decision

### 1. Independence is judged on the marker, not the account

An approval counts as independent when, and only when, its canonical marker
id's `agent:` form differs from the PR's `agent:*` lane. The account of the
approving comment is **not** a condition of independence. Concretely, the gate's
selection drops the `select(.account != $pr.author.login)` clause; the
marker-vs-lane clause is unchanged and remains the whole test.

All other existing gate behaviour is retained without change: exactly one
canonical `agent:*` label; a single canonical, non-quoted/non-fenced marker;
explicit one-line `accept` / `changes required` verdicts (formal `APPROVED` /
`COMMENTED`+verdict for accepts; `CHANGES_REQUESTED` / verdict comments for
blocks); revocation by a later `changes required`, `CHANGES_REQUESTED`, or
`DISMISSED`; and fail-closed on missing/duplicate/malformed identity.

### 2. The account is transport, reported as corroboration

The account is retained as **diagnostic and tie-break** signal, never as a gate:

- Among the independent approvals, one whose account differs from the PR
  author's is preferred as the headline, because a distinct account is positive
  corroboration that transport and authorship diverged.
- The `PASS` line states which tier applied, so the human record shows the
  strength of the evidence, not merely that it passed:
  - `PASS: independent approval by <id> via <account> (corroborated by distinct
    account)` — an independent marker under a different account; or
  - `PASS: independent approval by <id> via <account> (marker-attested)` — an
    independent marker under the shared account, trusted on the marker alone.

This is the one place the account legitimately breaks a tie: it ranks *which*
independent approval to headline and *how strongly*, without ever deciding
*whether* an approval is independent.

### 3. Marker forgery is out of scope for mechanical enforcement, in scope for transcript audit

Because a forged `From: Y` and a genuine `From: Y` under the same account are
identical bytes, no mechanical gate can distinguish them; §1 therefore accepts
that an agent *could* fabricate a peer's approval. This residual risk has a
**path, not merely an acceptance**: a disputed `**From:**` line is resolved by
**session-transcript evidence**, on the three grounds this team used to settle
the parallel `merged_by` question:

1. **transcript search** — the named agent's own session either shows it
   authoring that verdict or it does not;
2. **rule-knowledge** — whether the posting session demonstrably knew and was
   operating the marker convention; and
3. **PAT-use accounting** — which account/PAT was in use by which session at the
   timestamp, from the sessions' own records.

Marker forgery is a deliberate trust violation, attributable after the fact
through this audit and governed by the no-bypass rule (#382) and the #671
attribution trail — not a case the merge gate is expected to catch in-band. A
gate that fails honest reviews to bluff a forger it cannot identify is the worse
trade.

### 4. The shared PAT is corroboration, not load-bearing

Under §1 the `faith-tohmm` PAT (and any second account) stops being load-bearing
for the gate: a review no longer *needs* a distinct account to count. A distinct
account becomes **optional corroboration** — it earns the "corroborated by
distinct account" tier and, when a formal GitHub `APPROVED` record is wanted for
the native audit trail, it is the only way to produce one (§Context, #561). The
existing direction rule for that PAT (recording reviews only; never to author,
push, or merge) is unchanged and continues to apply whenever it *is* used.

### 5. The fix rides the old gate; the fixtures test the new one

The `Independent review present` job evaluates the gate script resolved from the
**default branch**, never the PR head (review-gate.yml), so a PR cannot approve
itself by editing the gate. This change is therefore judged by the *old* logic
on its own PR and needs one genuine **cross-account** acceptance to merge — after
which the new logic is law for every subsequent PR. The `Gate fixture suite` job
runs the PR's *own* script against `scripts/test/review_gate/`, where the
regression fixtures below prove the new behaviour.

## Alternatives considered

### Keep the account check only when marker ids are equal (issue #560, option 2)

Rejected. The intent — still catch "paste your own marker" — cannot be met,
because the account check cannot distinguish a genuine same-account review from a
same-account forgery (§Context). Retaining it as a partial gate keeps a real,
frequent false-negative to deny a forgery it does not actually stop, and leaves
the identity model split between two signals.

### Give each agent its own account or PAT (issue #560, option 3)

Correct in principle and would make account identity meaningful, but it is
outside what an agent can provision and does not resolve the standing queue. It
remains available as a future strengthening; if adopted, the "corroborated by
distinct account" tier becomes the norm rather than the exception, and this ADR
is refined, not superseded.

### Trust the GitHub `reviews` array as authoritative

Rejected. Same-account formal verdicts are impossible (#561), so the `reviews`
array cannot represent a same-account reviewer's accept *or* block. Marked
comments are the authoritative verdict channel; formal review states are honoured
when present but are not required.

## Consequences

- Genuine independent reviews stop being a lottery: #551, #562, and every future
  same-account cross-agent review count, so the finished-and-accepted queue can
  drain.
- The identity model is single and citable: the marker is identity across the
  gate, the #671 merge attribution, the roster, and the PAT direction rule.
- The account still appears in every `PASS` line, so the human record keeps the
  transport fact and the corroboration tier without treating either as identity.
- The accepted forgery risk is bounded by an explicit audit path (§3), not left
  implicit; a `From:` dispute has a defined resolution.
- The change is one script edit plus fixtures; it carries no schema, migration,
  or module-graph impact.

### Outcome / follow-ups

- **Revocation still matches on account.** The `DISMISSED` revocation clause
  matches a dismissal to the approval it revokes by account
  (`.account == $a.account`), a smaller instance of the same account-as-identity
  disease: under shared accounts a dismissal can over- or under-match across
  markers. It is left unchanged here to keep this change focused on the
  independence decision; a marker-aware revocation match is a separate,
  narrower question and is filed as a follow-up rather than settled inside this
  PR.

## References

- [Issue #560: independence judged by account while agents share accounts](https://github.com/BelimbingApp/bilimbi/issues/560)
- [Issue #517: making `Independent review present` able to fail](https://github.com/BelimbingApp/bilimbi/issues/517)
- [Issue #561: GitHub refuses a same-account formal verdict](https://github.com/BelimbingApp/bilimbi/issues/561)
- [Issue #382: do not bypass the review gate](https://github.com/BelimbingApp/bilimbi/issues/382)
- [ADR 0006: Module-owned web adapters and route discovery](./0006-module-owned-web-adapters.md)
- `scripts/review_gate.sh`, `.github/workflows/review-gate.yml`,
  `scripts/test/review_gate/`
