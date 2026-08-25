# AI-team mechanisms

These scripts enforce the reusable operating guide. Copy this directory with
`../README.md` when adopting the model in another GitHub repository.

Most scripts are repository-independent and resolve the current GitHub
repository through `gh`. `project-orient.sh` is the deliberate exception: it is
the local hook for source pins, assembly checks, and project commands. Replace
or remove it when copying the package.

The scheduled blocked-task workflow remains under `.github/workflows/` because
GitHub owns its trigger and permissions; its implementation and tests live here
with the board contract they enforce.
