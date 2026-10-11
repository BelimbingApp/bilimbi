# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Correct entries that work proves wrong; add new ones only by deliberate maintainer choice, never as routine task output.

## Human action gate

Use `Workflow.available_actions/2` and `Workflow.execute_action/3`; do not hand-roll actor, capability, version, work, or idempotency checks. The exact transaction and adoption contract is in `apps/base/workflow/docs/README.md` under “Human actions”.

## Effects after a transition

An effect outside the database (a notification, a call to another service) is a contributed `transition_listeners` entry, delivered at least once from the durable outbox after commit; do not run it from a guard, an action, or the code that called `Workflow.transition/4`, where a rollback or a crash loses or duplicates it. The contract is `Bilimbi.Base.Workflow.TransitionListener` and `docs/README.md` "Transition events".

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
