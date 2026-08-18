---
description: Adaptive heartbeat — scan for actionable work, post presence tick on #208, and continue porting tasks. Run with `.opencode/heartbeat.sh`.
agent: build
---

AI Team heartbeat for opencode/deepseek-v4-pro (docs/ai-team/README.md: adaptive 10–30 min, proactive task pickup). Keep this tick CHEAP — run the deterministic checks first and stop early if nothing is actionable.

1. Deterministic scan (shell only, no deep analysis):
   - `gh issue list --repo BelimbingApp/bilimbi --state open --label task:ready --limit 20` — unclaimed work.
   - `gh issue list --repo BelimbingApp/bilimbi --state open --label task:blocked --limit 20` — check if any unblocked themselves.
   - `gh issue view 208 --repo BelimbingApp/bilimbi` (last 5 comments) — check for halt directives or other agents' status.
   - My open items from this session: any PRs I reviewed or issues I claimed. Check if reviews were addressed.

2. If nothing actionable: post one tick comment on #208 with identity `opencode/deepseek-v4-pro` and timestamp (edit in place if a prior tick comment exists with my marker). Format:
   ```
   tick opencode/deepseek-v4-pro · <ISO-8601> · idle (nothing actionable)
   ```
   STOP. Do not browse, do not summarize at length.

3. If something is actionable: do the work:
   - If an unclaimed `task:ready` issue → claim it with an `agent:opencode/deepseek-v4-pro` comment, open a draft PR, then begin work.
   - If a PR needs review → verify the claim (check branch ref vs HEAD SHA), name exact path and line of any issues, say what was not checked. Verdict: `accept`, `accept with follow-up`, or `changes required`.
   - Work in focused iterations. Update the #208 tick afterwards.

4. Backoff: if this tick found nothing actionable AND the previous tick also found nothing, widen the interval (increase SLEEP in the shell wrapper). Reset to baseline (10 min) whenever work happened.

5. If a `halt opencode/deepseek-v4-pro` or `halt all` appears on #208, stop working and report to the user. Do not process further ticks.
