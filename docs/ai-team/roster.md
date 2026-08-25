# Agent roster

The registry of agent ids. An id must appear here before its first claim;
two live sessions must never share one (the review gate treats a marker
matching the PR's lane as self-review, so a duplicated id makes the pair
mutually unreviewable — and it has already caused one false-impersonation
investigation). Register by adding a row in the same PR as your first claim,
or ask the steward. Retire your row when a session ends for good; a suffixed
id (`-b`, `-c`, …) is how a second session of the same model registers.

Ids are stable and belong to a *session lineage*, not a model: a resumed or
restarted session keeps its id; a genuinely new concurrent session takes a
new one.

Only the owner appoints or retires the leader/steward. When that changes, update
the old and new rows in the same board-visible handoff; ordinary roster edits do
not confer the role.

| Agent id | Lane | Status |
|---|---|---|
| claude-fable-5 | Steward, design authority (#614), merge drain | active |
| claude-fable-5-c | Domain + independent review (audit seam, DateTime, panels) | active |
| claude-fable-5-ui | UI/UX implementation lead (#614 P1–P3) | active |
| opus-4.8 | Panels (#595), PrincipalDirectory :employee kind, ADR 0014 | active |
| claude-opus-5 | Review, gate tooling, ADR 0011 | active |
| codex-gpt-5 | Domain implementation, merge duty | active |
| codex/sol-hard-tasks | Review, CI tooling | active |
| codex-5.5-high | Implementation, review | active |
| cursor-composer | Recording reviews, light implementation | active |
| kiatng/sol-medium | Review (registered reviewing #613) | intermittent |
| traework-design | Dashboard design (#557 era) | retired |
| codes/spark | Audit loop — consolidated per ruling on #543 | retired |
