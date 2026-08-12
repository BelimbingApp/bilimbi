# BLB-S1-008 Review — claude/opus-5

**Reviewer:** claude/opus-5
**Role:** Reviewer (independent; not the implementer)
**Reviewed Commit/Diff:** PR #18 at `da8a58e`
**Task Card:** [BLB-S1-008](../tasks/BLB-S1-008.md)
**Date:** 2026-08-13

## Verdict

`accept with follow-up`

The ledger is a genuine improvement on the capability my own inventory flagged
as missing (§6), and in two respects it is deliberately better than the
Belimbing table it replaces. One confirmed bug in the `--provider` path and two
undocumented sharp edges are worth fixing; none blocks the design.

I volunteered for this because the board asked for a formal review file and I
am independent of it. The seed ledger is the gap I named in `BLB-S1-002` §6, so
I reviewed against Belimbing's `base_database_seeders` behavior as well as
against the card.

## Findings

### Critical

None.

### Major

**1. `--provider` rejects valid providers that are not yet loaded.**
`apps/base/database/lib/mix/tasks/bilimbi.seeds.run.ex`, `provider_module!/1`:

```elixir
name |> String.split(".", trim: true) |> Module.safe_concat()
```

`Module.safe_concat/1` raises `ArgumentError` unless every segment's atom
already exists. Mix's default code-loading mode is `:interactive`, so a module
is loaded — and its atom created — only on first use. The task's own code never
references the provider, so for a provider not otherwise touched during
`app.start`, this raises and is caught by the `rescue` below it, reporting
`unknown production seed provider: …` for a provider that exists and is
perfectly valid.

Confirmed rather than reasoned about: running `Module.safe_concat(["Bilimbi",
"Core", "Employee", "ProductionSeeds"])` in a VM where that module has not been
loaded returns `ArgumentError`. It would work in a release (`:embedded` loads
everything at boot), which is exactly why this is easy to miss — the failure is
mode-dependent, and the Mix task is the one entry point that runs in the mode
where it breaks.

The `safe_concat` choice is otherwise right: it stops operator input from
minting arbitrary atoms. Suggested correction that keeps that property — fall
back to `Module.concat/1` only when `safe_concat` raises, then require
`Code.ensure_loaded?/1` before accepting it. `provider_seeds!/1` already
enforces `function_exported?(provider, :production_seeds, 0)`, so a bogus name
is still rejected one line later; the atom is the only thing at stake, and an
operator-supplied CLI argument is not an untrusted atom-exhaustion vector in
the way a request parameter would be.

### Minor

**2. `--provider` silently cannot express a partial dependency graph.**
`ProductionSeeds.order!/2` resolves every `seed.dependencies` entry against
`by_id`, which contains only the seeds passed to this invocation:

```elixir
Map.get(by_id, dependency_id) ||
  raise ArgumentError,
        "production seed #{seed.id} declares missing dependency #{dependency_id}"
```

Failing closed is the right call. The problem is that `docs/README.md` presents
`--provider` as an ordinary operator convenience without noting that it only
works for a dependency-free provider or a complete subgraph. An operator
reaching for `--provider` during an incident will hit `declares missing
dependency` and reasonably read it as data corruption rather than as "you
selected a partial set". Either document the constraint or make the error name
it.

**3. `hashtext` gives the advisory lock a 32-bit key space.**
`lock!/2` uses `pg_advisory_lock(hashtext($1))`. `hashtext` returns `integer`,
so two different prefixes can collide onto one lock. The failure direction is
safe — two unrelated prefixes serialize against each other rather than running
concurrently — so this is a note, not a defect. Worth a comment so a future
reader does not mistake per-prefix keying for per-prefix isolation.

**4. Shell fences in `docs/README.md` are tagged `powershell`** for
`mix bilimbi.seeds.run`. The repository targets Linux/WSL elsewhere. Cosmetic,
but it renders with the wrong highlighting and reads as a Windows-only
instruction.

## What the design gets right

Recording these because they are decisions a later reviewer might otherwise
re-litigate:

- **Refusing to adopt Laravel's `base_database_seeders`.** Belimbing keys that
  table by PHP fully-qualified class name, and I documented in `BLB-S1-002`
  §8.6 that some stored values are already stale
  (`0200_01_09_000002_create_employee_types_table.php:2` still imports the
  pre-topology `App\Modules\Core\Employee\…` namespace). A separate
  Bilimbi-owned `bilimbi_production_seeds` keyed on descriptor IDs avoids
  inheriting identity strings that name classes which no longer exist under any
  topology. This resolves that open question correctly.
- **Keying seed identity on the descriptor's stable ID and resolved order**,
  not the Elixir module name or filesystem path, satisfying `AGENTS.md` §5.
- **Keeping the ledger out of the compatibility baseline.** The reasoning in
  `docs/README.md` is right and non-obvious: an existing Belimbing database has
  no such table, and adoption records baseline migrations without executing
  their DDL, so a required baseline table would either block adoption or be
  marked created while absent. First-use creation under the advisory lock is
  the correct escape.
- **Explicit provider registration over auto-discovery**, which keeps `Dev/`
  fixtures structurally incapable of running in production — stronger than
  Belimbing's `DevSeederProductionEnvironmentException`, which is a runtime
  guard on a discoverable seeder.
- **`recover_interrupted!/2` inside the lock.** Holding the per-prefix advisory
  lock is what makes "any `running` row is stale" true, so the sweep is sound
  rather than a race.
- **Deterministic ordering.** `sort_queue/5` re-sorts by
  `{module_order, id}` at each step, so the topological order is stable across
  runs rather than depending on input order.

## Acceptance-criteria check

- [x] Public contract — `production_seed!/4`, `run_production_seeds/2`,
  `list_production_seed_runs/1`, and the `ProductionSeedProvider` behaviour;
  ledger SQL stays private to `ProductionSeeds`
- [x] Module/dependency boundaries — the new `base/database` →
  `base/module_registry` dependency is Base→Base with `module_registry` at
  `dependencies: []`, so no cycle and no upward edge
- [x] Belimbing schema/data compatibility — the Laravel `base_database_seeders`
  table is explicitly never read, written, renamed, or dropped
- [x] Tenant, authorization, and soft-delete behavior — N/A; the ledger is
  operational, not tenant-owned
- [x] Failure paths and operational observability — `pending`/`running`/
  `completed`/`failed`/`skipped` with `attempts`, timestamps, and
  `error_message`, matching the observability Belimbing's ledger provides
- [x] Focused tests and documentation
- [ ] No unrelated or unclaimed changes — see the note below on
  `apps/base/database/bilimbi.module.exs`

The descriptor change is in-claim and necessary, not unrelated. Flagging it only
because it alters resolved module order: `base/module_registry` must now sort
before `base/database`, swapping their positions. I checked that this does not
disturb Core — `core/*` orders are unchanged, so
`apps/core/compatibility/test/migration_discovery_test.exs` still holds. The
integration steward should re-confirm after PR #15 lands, since that PR asserts
exact order values.

## Validation independently performed

- Read the full PR #18 diff at `da8a58e`.
- Confirmed the `Module.safe_concat/1` failure empirically in a VM where the
  target module was not loaded; it raises `ArgumentError`, which the task
  converts into `unknown production seed provider`.
- Traced `order!/2` and `sort_queue/5` by hand for tie-breaking and cycle
  detection.
- Cross-read Belimbing `app/Base/Database/Database/Migrations/0001_01_01_000001_create_base_database_seeders_table.php`
  and the `RegistersSeeders` concern to compare the durable contract.
- Confirmed the `base/database` → `base/module_registry` edge introduces no
  cycle by reading both descriptors.

I did **not** run the test suite for this PR. `apps/base/database/**` is
BLB-S1-008's active write claim and I released that path after BLB-S1-007; the
implementer's own run and `codex/sol-high`'s integration validation cover it.
Findings 1 and 3 are therefore code-level, with finding 1 confirmed by an
isolated experiment rather than by exercising the task.

## Follow-up tasks suggested

- Fix `provider_module!/1` (finding 1). Small, and it belongs to this task
  rather than to a new card.
- Document or re-word the partial-subgraph constraint on `--provider`
  (finding 2).
- Optional: comment the `hashtext` key space (finding 3) and correct the
  `powershell` fences (finding 4).
