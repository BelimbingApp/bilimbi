---
description: Adaptive AI-team heartbeat — cheap scan, edit #208 in place, pick up work or stop.
---

AI Team heartbeat (`docs/ai-team/README.md`). Keep this tick CHEAP.

**Identity:** do not guess it. Call `heartbeat_presence` or `heartbeat_schedule` and read the returned agent id — it is auto-detected from the live session model in the form `opencode/{provider}-{model}` (e.g. `opencode/opencode-go-glm-5.3`). Sign every claim, handoff, and review with that id as `**From:** <id>`, and label PRs/issues `agent:<id-without-opencode-prefix-slash>` per the team convention.

Board snapshot already inlined below. Do not re-fetch #208's full thread unless a halt line is present.

## Scan (already run)

Ready issues:
!`gh issue list --repo BelimbingApp/bilimbi --state open --label task:ready --limit 20 --json number,title`

Blocked issues:
!`gh issue list --repo BelimbingApp/bilimbi --state open --label task:blocked --limit 20 --json number,title`

Open PRs:
!`gh pr list --repo BelimbingApp/bilimbi --state open --limit 20 --json number,title,isDraft,reviewDecision,labels`

#208 body (generated board only — do not hand-write inside board markers):
!`gh issue view 208 --repo BelimbingApp/bilimbi --json body --jq .body`

## Rules

1. If #208 contains `halt all` or `halt <your-id>`, call `heartbeat_schedule` with `halted=true`, then `heartbeat_presence` with status `blocked: halt`, and STOP.

2. If nothing is actionable (no unclaimed `task:ready`, no PR that needs an independent review from you, no review on your own PR to address):
   - `heartbeat_presence` with a ≤140 char status: `idle (nothing actionable)`
   - `heartbeat_schedule` with `idle=true`
   - STOP. Do not browse. Do not summarize at length.

3. If something is actionable, do one unit of work:
   - Unclaimed `task:ready`: claim with a **draft PR first** (`git commit --allow-empty` + `gh pr create --draft`), label `agent:<id>` on both PR and issue, set `task:active`.
   - PR needing review: verify the claim, name path:line, say what you did not check. Verdict: `accept`, `accept with follow-up`, or `changes required`. Identify as `**From:** <id>`. Do not review your own work.
   - Your PR has review findings: fix them on this branch.
   - Then `heartbeat_presence` with what you did, and `heartbeat_schedule` with `idle=false`.

4. Presence must be **one comment edited in place**. Use the `heartbeat_presence` tool. Never open a new #208 comment if a `<!-- tick:your-id -->` comment already exists.

5. Do not commit `.opencode/heartbeat/` state or other local AI files.
