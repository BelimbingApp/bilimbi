# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Correct entries that work proves wrong; add new ones only by deliberate maintainer choice, never as routine task output.

## Human action gate

Use `Workflow.available_actions/2` and `Workflow.execute_action/3`; do not hand-roll actor, capability, version, work, or idempotency checks. The exact transaction and adoption contract is in `apps/base/workflow/docs/README.md` under “Human actions”.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
