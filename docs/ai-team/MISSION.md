# Bilimbi AI Team — current mission

**Document Type:** Repository-specific mission
**Last Updated:** 2026-08-25

This file supplies the facts that the reusable [AI Team operating
guide](./README.md) intentionally does not know. Replace it when the mission or
repository changes; do not copy these Bilimbi-specific values into another
repository.

## Objective and instructions

Port **Belimbing** (Laravel/PHP) to **Bilimbi** (Phoenix/Elixir). Belimbing is
canonical for business meaning and the compatible PostgreSQL schema, not for
implementation. Reproduce the durable contract behind deep-module APIs rather
than translating Laravel code.

Read root [`AGENTS.md`](../../AGENTS.md) and [`DESIGN.md`](../../DESIGN.md)
before touching code. The
[port map](https://github.com/BelimbingApp/bilimbi/discussions/73) tracks what is
done and what remains; correct errors in a comment because other agents plan
from it. [`PORTING_STAGES.md`](./PORTING_STAGES.md) defines stage order and exit
gates.

When Belimbing contains an inconsistency, mistake, or avoidable entropy, do not
blindly reproduce it. Correct it in Bilimbi when compatibility permits and
raise an upstream issue so Belimbing benefits from the discovery.

## Canonical source checkout

The operational source checkout and citation pin are:

```text
/home/kiat/repo/laravel/blb    769bc31ddb632f5d2c5acb0fd05b777197df87cc
```

`/home/kiat/repo/Belimbing` is planning material with no `app/` tree. Cite a
`laravel/blb` path or you are citing the wrong source. The pin identifies the
checkout agents read; it does not replace older historical citations when an
older commit is the actual source for a compatibility decision. Do not advance
the pin merely because Belimbing has new commits.

`scripts/project-orient.sh` reports where the checkout is, whether the pin still
holds, and which source files changed after it. If an agent ports or cites a
post-pin file, either advance the operational pin in the same change or cite the
newer SHA explicitly.

## Repository coordination surfaces

| Purpose | Bilimbi location |
|---|---|
| Owner-only decisions | pinned issue [#648](https://github.com/BelimbingApp/bilimbi/issues/648), label `task:kiatng` |
| Port map | [Discussion #73](https://github.com/BelimbingApp/bilimbi/discussions/73) |
| UI/UX quality program | issue [#614](https://github.com/BelimbingApp/bilimbi/issues/614) |
| RFCs and open questions | GitHub Discussions |
| Durable architecture decisions | [`docs/architecture/decisions/`](../architecture/decisions/) |
| Database architecture | [`docs/architecture/database.md`](../architecture/database.md) |

## Local commands and environment

The project orientation hook prints the commands worth knowing. In particular:

```bash
cd apps/core/user && mix test
cd apps/core/compatibility && mix test
cd apps/web && PORT=4002 mix phx.server
```

Do not judge a screen from the long-lived development server on port 4000. It
belongs to another checkout and its contribution snapshot is built once at
boot. Root `mix` commands require dependencies first; module-level tests can run
without fetching the root tool dependencies.

If Geonames tests report a missing optional Plug feature even though Plug is in
the lockfile, refresh Req in that module's test environment:

```bash
cd apps/core/geonames && MIX_ENV=test mix deps.compile req --force
```

## Shared GitHub account

The `Protect main` ruleset has shared-account bypass actors, so the merge gate
is load-bearing even when GitHub reports branch protection. Inspect the current
ruleset through `gh api repos/BelimbingApp/bilimbi/rulesets`. In this repository
`gh pr merge` refuses client-side because `mergeStateStatus` remains `BLOCKED`;
use the operating guide's explicit gate-and-REST sequence.

The optional reviewer account is `faith-tohmm`. Its credential may only record
a review on work the agent did not author; never use it to author, push, or
merge. Scope it to the one command, never reconfigure `gh`, never print or
commit it, and record the stable agent id in the review body:

```bash
GH_TOKEN=$(cat ~/.secrets/faith_pat) gh pr review <n> --approve --body "..."
```

The merge gate judges independence from the `**From:**` marker and PR lane, not
from shared GitHub account metadata. Use whichever account did not author the
pull request; a distinct account is corroboration, not the identity source.
