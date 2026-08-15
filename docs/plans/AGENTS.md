# Plans Docs Guide

## Purpose

A plan is the **whiteboard** of a live discussion: capture what's agreed and why so future readers see it. `docs/plans/` is the in-repo single source of truth, the **status surface** (no parallel observability doc). Early on it holds intent; as the *how* firms up it **becomes the task list** (Phases checklists) in place. Plans should let a capable agent work autonomously after the user says to build: record contracts, invariants, coordination state, and proof of done rather than line-by-line instructions. **Prose only** for design — no code/patches/full-file dumps. Recommendation-driven copy, stable section names, a preamble for quick orientation.

## Problem first

Plans are problem-first, not feature-first. State what is broken, missing, or risky before naming solutions. When the user leads with a solution, backfill the problem and check it still fits.

In **Design Decisions**: name 2–3 real options, weigh trade-offs plainly, then recommend one and say why it wins under root `AGENTS.md` (entropy, strategic cost, deep modules, honesty, UX, module boundaries). Prefer solutions that optimize real operational work — not demo breadth, hypothetical configurability, or feature checklists. Do not open with implementation tasks or a preferred stack before **Problem Essence** and **Desired Outcome** exist.

## Workflow

1. User opens a discussion (problem, goal, constraint).
2. When asked, the agent records a coherent plan on an md file — recommendations and tradeoffs stated plainly, not questionnaires or "Decision Needed" dumps.
3. On user reaction, describe the proposed revision in the md file (short prose, naming affected sections + follow-on edits). Exempt: trivial mechanical fixes the user already specified.
4. **HALT** — wait for explicit approval before implementing.
5. A plan is the parent record; the active task queue is one or more GitHub issues. Each issue is a logical grouping of phases and is the operative work item for an agent. Plans are not the execution unit unless no issue exists.

Session/tool-only plans are fine as scratch **only** if mirrored here. Anyone opening the plan should see design, current phase, done vs open (checkboxes), and what changed.

Plans may be promoted into GitHub issues and then taken up by different agents. When that happens, the plan remains the canonical design record and the issue should carry only the current execution slice, status, and handoff details; the source of truth is still the plan, not the issue thread. If a GitHub issue exists, record its number in **Sources** and keep the plan and issue synchronized on status and scope.

## Keep plans current

Work that implements/fixes something in a plan must **update the plan**, not just the code:
- Tick/adjust checklists (`- [x]` when truly done; suffix completed lines with `{agent}/{model}`; add/split rows on scope change; delete dropped tasks and dead prose).
- Refresh narrative in prose when reality diverges from Design Decisions / Desired Outcome (no patches/code).
- Bump **Last Updated** and set **Status** when story/status meaningfully changes.
- If a plan is linked to one or more GitHub issues, include the issue numbers in the relevant source references and mark which phase(s) belong to which issue.
- If a phase is delegated to an issue, record the issue number on that phase so the task boundary is explicit to the next agent.

A stale checklist or design text is a false source of truth.

Because plans may be implemented by different agents, leave an accurate handoff: current status, completed checkboxes with `{agent}/{model}`, evidence, changed assumptions, and any newly discovered work that belongs in the same build. Once the linked issues are closed and the plan has no remaining active work, the plan may be marked complete and disposed of as a historical record.

## Document shape

**Title:** the filename/path (optional lone `#` matching it). No filler "Plan"/"Notes" sections.

**Preamble** (substantive plans): **Status**, **Last Updated** (`YYYY-MM-DD`), **Sources** (issue numbers/URLs/ADRs/parent plans/paths, or `None`), **Agents** (`{agent}/{model}` contributors, kept current).

Status describes current reality; it is not a permission gate. Keep it short and action-oriented, for example `Proposed`, `In progress`, `Complete`, or `Superseded`. When GitHub issues exist, include the issue numbers in **Sources** so the plan remains traceable to the executing work items.

**Body** — use a section only when it has real content; flow intent → system → why → contract → execution; never open with low-level tasks:
1. **Problem Essence** (required) — 1–2 sentences.
2. **Desired Outcome** (required) — what "done" achieves.
3. **Top-Level Components** — nameable responsibilities.
4. **Design Decisions** — 2–3 real options, trade-offs, recommended direction, and why it wins under root `AGENTS.md`.
5. **Public Contract** — surface/promises once clear.
6. **Phases** — chunked work. (Use `Build Sequence` only to match an external artifact's wording; otherwise always `Phases`.)

## Phases = build sheet

Markdown tasks: `- [ ]` open, `- [x]` done (tick only when truly finished; remove stale unchecked items for merged work). **Checklists are the source of truth** for remaining work. Grouping headings get **no** checkboxes.

When a phase is delegated to GitHub work, attach the issue number to the phase or checklist entry, for example `Issue #123` or `- [ ] Issue #123 — ...`. A plan may contain multiple issues, and an issue may group several phases. Issue numbers are the task boundary for agents; phases are the scoped execution units underneath that boundary.

Optional per-phase, plain `label:` form (no bold, no checkbox): `Affected pages`, `Goal`, `Scope`, `Assumptions`, `Risks`, `Evidence`.
- `Affected pages` — routes/URLs to open to verify that result in-browser.
- `Goal` — the expected result, stated as what a reviewer should observe on the `Affected pages`.
- `Evidence` — proof (files, tests).
- `Validation` — commands or manual checks expected to prove the phase.

Write tasks as observable outcomes. Use stable anchors such as classes, methods, routes, or paths; avoid brittle line numbers. Refine checklists as reality sharpens. Plans guide known work but do not suspend root `AGENTS.md`: make small nearby corrections, and add larger related work as checklist rows for the next agent. Keep coupled follow-ups inline; finish independent work after the current phase.

## Filenames, splitting, legacy

- **Prefix** filenames with the owning module/subsystem (primary module if multi-module); cross-cutting/project-wide plans need no prefix.
- **Split** only when a file is hard to use: (a) master — essence/outcome/components/decisions/contract; (b) per-phase build sheets with checklists. Master indexes them via Sources/phase index; each phase file links back; predictable paths.

## Hard Rules

- No questionnaire plans or chat prompts.
- No neutral option-padding when a recommendation exists.
- No solution-first or feature-first plans before **Problem Essence** and **Desired Outcome**.
- No observability-only sections duplicating this doc.
- No plan kept only in session state unless explicitly asked.
- No stale or contradictory content.
- No prose-only **Phases** when steps are concrete — use checkboxes.
- No code in the plan.
- No artificial permission/status gates beyond explicit user approval and project hard rules.
- No line-by-line implementation scripts when contracts, invariants, and acceptance criteria would give a capable agent more useful freedom.

## Litmus

Can a reader quickly answer: what problem, what outcome, what design, what's open vs done, what changed, who did what, where to push back, where constraints came from (**Sources**), and how done is proven? If not, fix the doc first.
