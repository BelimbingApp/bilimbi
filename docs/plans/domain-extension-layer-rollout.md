# docs/plans/domain-extension-layer-rollout.md

**Status:** In progress — Phases 1–4 shipped 2026-09-26; Phase 4's AX production-history import and Phase 3's Quality placement stay open
**Last Updated:** 2026-09-27
**Sources:**
- `docs/architecture/0010_composition-model.md`
- Review by sol (2026-08-16)
- ADR 0003 physical deep-module packages
- ADR 0004 module contribution contract
- `docs/PORTING_STAGES.md` (S5, S6, stage-change rule)
- `AGENTS.md` §4
- `apps/base/module_registry/`
- [Pull request 804](https://github.com/BelimbingApp/bilimbi/pull/804)
- Phase 2 pull requests: [812](https://github.com/BelimbingApp/bilimbi/pull/812) route overlap,
  [814](https://github.com/BelimbingApp/bilimbi/pull/814) nested discovery, host closure, release, completeness guard,
  [815](https://github.com/BelimbingApp/bilimbi/pull/815) composition lock overlay,
  [816](https://github.com/BelimbingApp/bilimbi/pull/816) migration provenance,
  [817](https://github.com/BelimbingApp/bilimbi/pull/817) mounted-code traversal,
  [819](https://github.com/BelimbingApp/bilimbi/pull/819) end-to-end with a mounted Domain,
  [820](https://github.com/BelimbingApp/bilimbi/pull/820) authenticated Scope actor
- Factory Domain repository [BelimbingApp/b-dom-factory](https://github.com/BelimbingApp/b-dom-factory) (public; pull requests 1–16)
- SBG Extension repository `SB-Tape/b-ext-sbg` (private; pull requests 1–3; only its public contract is recorded here)
- Factory plan `docs/plans/factory/0000-factory-domain.md`
- Inventory module plan `docs/plans/factory/0010-inventory-module.md`
- Customer plan `docs/plans/factory/mr-packaging-requirements.md`
- Customer plan `docs/plans/factory/sbg-requirements.md`

**Agents:** claude/claude-opus-5 (earlier work),
amp/medium-sol (architecture review only), codex/gpt-5 (earlier work),
codex/gpt-5.6-luna (earlier work), codex/gpt-6-luna-xhigh (earlier work), codex/gpt-6-sol-medium (Factory boundary revision),
claude/claude-opus-5.5 (Phase 1 runtime proof, no-mistakes review agent),
claude/claude-fable-5-1 (Phase 5 documentation alignment)

## Problem Essence

Bilimbi discovered its Base and Core modules, but until 2026-09-26 it had not
proved that independent Domain and Extension repositories mounted under
`apps/domains/` and `apps/extensions/` can become one valid release without
Platform code naming or depending on them.

## Desired Outcome

A company mounts the Domain and Extension repositories it needs, Bilimbi
discovers and validates the complete graph, and the company compiles it into a
binary containing all mounted capabilities and their routes, migrations, and
contributions.

Repository presence is the only composition choice. Bilimbi does not require a
second installed-capability list or prescribe how the company operates the
binary.

## Current Machinery

The mechanism shipped on 2026-09-26 and is used by two real repositories. The
normative rules live in `docs/architecture/0010_composition-model.md`; the
mechanics live with their owners:

- Discovery finds Base and Core as direct children of `apps/` and mounted
  containers under `apps/domains/<id>/` and `apps/extensions/<id>/` with no
  list naming them; the ID, layer, reserved-name, same-layer edge, cycle, and
  upward-edge rules are in `apps/base/module_registry/docs/README.md`.
- Web takes a path dependency on every discovered container, the `bilimbi`
  release is built around Web, and `ModuleRegistry.complete_modules!/0`
  refuses any runtime missing a graph module. Host boot, the database Mix
  tasks, and `BilimbiWeb.Release.migrate/0` and `seed/0` call it first.
- `BilimbiWeb.RouteOverlap` fails `mix compile` when two routes of the
  compiled host router overlap, using descriptor layer and source as owner.
- Mounted builds share one composition lock overlay with a pinned revision
  manifest (`mix/composition_lock.exs`, 0010 "Composition dependency lock").
- `bilimbi_migration_provenance` keeps an unmounted repository's applied
  migrations valid and refuses a remount that changes an applied file
  (`docs/architecture/database.md`).
- Formatter subdirectories, guard scans, Tailwind sources, `precommit.test`,
  and `compile.strict` derive their paths from discovery.
- Settings, authorization, menu, and schema contributions come from the same
  provider mechanism as Base and Core; conflicts fail
  `mix bilimbi.contributions.verify`, host boot, and the release seed command,
  not `mix compile`.

Sparse per-module selection, selection files, deployment repositories, and a
fixed environment topology are not requirements of the composition model and
are outside this plan.

## Design Decisions

### Select repositories by mounting them

**Mounted independent repositories** are recommended because repository presence selects source without a second registry. The nested role roots still need Mix and discovery changes. Git submodules need a company-owned parent; published packages add a package lifecycle; runtime
flags ship unselected code. Those alternatives remain deferred unless the
nested-repository proof fails.

Every valid module in a mounted repository participates. Finer module-level
selection is deferred until a real cohesive repository proves too coarse.

### Derive one graph

Container and module descriptors remain the sole composition declarations.
Git obtains source; Bilimbi discovers, validates, and builds what is mounted.
No second Domain, Extension, route, migration, or contribution registry may
name the same membership independently.

### Runtime visibility through the host closure

The source graph is visible at Mix time, while runtime consumers enumerate
loaded OTP applications. The proof compared four bridges: the host's OTP
closure plus a completeness check, a generated graph manifest loaded at
runtime, a runtime scan of the code path, and Core Compatibility depending on
mounted containers. The first is the mechanism: it adds one discovery function
and one registry check, changes no consumer, and a release built around Web
carries everything by construction. The manifest and scan variants still need
the host dependency and add a second membership artifact or blind spot; the
Compatibility variant is an upward Core dependency and is forbidden by 0010.
Package-local runs may see a subset, which is why every production entry
point calls the completeness check.

## Public Contract

- Mounting a valid Domain or Extension makes all of its valid modules part of
  the next build.
- Removing it removes its code and future contributions from the next build,
  but never deletes durable data automatically.
- Every dependency is declared; missing dependencies, forbidden directions,
  duplicate identities, cycles, and contribution conflicts fail the build.
- Web hosts contributed presentation without hard-coded capability names or
  owning contributor business rules.
- Migrations and metadata from mounted capabilities are available without an
  upward Platform dependency.
- The resulting binary boots without source, Mix, or a compiler.

## Phases

### Phase 1 — Disposable composition proof

Goal: prove or reject the complete model before production implementation.

Outcome: passed on 2026-09-26 in three disposable workspaces at Platform
`40779efd` and `115a38ea`, each cleaned afterwards; nothing from them shipped.
Three findings became Phase 2 work: the Platform's tracked lock was rewritten
by a mounted Hex dependency; the migration ledger refused an unmounted
repository's applied versions; and an overlapping mounted route was served by
Core's parameter route. One defect shipped on its own, the stale graph marker
fix in [pull request 811](https://github.com/BelimbingApp/bilimbi/pull/811).

- [x] Mount two throwaway Domain repositories under `apps/domains/` and two
  Extension repositories under `apps/extensions/`, each with a valid container
  and at least one module. Evidence: build and runtime proofs, four ignored
  nested Git repositories with no parent tracking.
- [x] Prove Mix includes both nested roots in builds and releases while Base,
  Core, and Web remain direct umbrella children, with the fixed-depth
  formatter, scan, Tailwind, precommit, and strict-compile gaps listed for
  Phase 2. Evidence: build proof; shipped as
  [814](https://github.com/BelimbingApp/bilimbi/pull/814) and
  [817](https://github.com/BelimbingApp/bilimbi/pull/817).
- [x] Prove a declared cross-repository Domain dependency and a declared
  Extension-to-Extension dependency, with cycle rejection for both. Evidence:
  runtime proof, alpha→beta and gamma→delta fixtures, both cycles refused at
  `mix compile`.
- [x] Treat those synthetic edges only as mechanism fixtures; every production
  same-layer dependency must separately pass 0010's business-necessity test.
  Evidence: no production same-layer edge exists; 0010 keeps the test.
- [x] Confirm the parent Bilimbi repository neither owns nor records the nested
  repositories. Evidence: `.gitignore` rules and empty `git ls-files` under
  both roots in the build proof.
- [x] Decide and prove lockfile ownership when a mounted repository adds a Hex
  dependency. Evidence: gaps proof found the tracked lock rewritten, chose a
  composition-owned overlay; shipped as
  [815](https://github.com/BelimbingApp/bilimbi/pull/815).
- [x] Prove a Domain repository's CI can check out a pinned Platform revision,
  mount itself, and run its build checks. Evidence: local rehearsal in the
  build proof; real workflow in
  [b-dom-factory pull request 1](https://github.com/BelimbingApp/b-dom-factory/pull/1).
- [x] Prove discovery includes every mounted module without a central list and
  rejects a missing dependency, duplicate identity, forbidden direction, and
  cross-repository cycle. Evidence: runtime proof, nine rejection cases each
  failing `mix compile`.
- [x] Prove Domain and Extension migrations run without Core depending on
  either capability; record the runtime-visibility mechanism and invariant.
  Evidence: runtime proof (host closure passes, Core-only closure silently
  skipped mounted migrations); mechanism recorded above and in 0010.
- [x] Prove Web compiles and serves mounted routes and rejects a route conflict
  without naming either capability. Evidence: runtime and gaps proofs; the
  conflict rejection shipped as
  [812](https://github.com/BelimbingApp/bilimbi/pull/812).
- [x] Prove settings, authorization, menu, and schema contributions derive from
  the same mounted graph. Evidence: runtime proof, snapshot fingerprint equal
  to the discovery fingerprint with all four repositories contributing.
- [x] Build a release and boot it without source, Mix, or a compiler.
  Evidence: build proof, dev-profile release booted with `apps/` and
  `mix.exs` renamed away; a production-profile boot is not yet checked in CI.
- [x] Remove one mounted repository, force a clean rebuild of every remaining
  graph application, and prove one fresh fingerprint, no removed code or
  contribution, and unchanged durable data. Evidence: build proof (one
  fingerprint, no removed app); gaps proof (table and row survived, ledger
  refused, fixed by [816](https://github.com/BelimbingApp/bilimbi/pull/816)).
- [x] Delete the throwaway repositories and experimental code after recording
  the result. Evidence: each proof's cleanup note; no `proof_*` code on `main`.

Validation: one disposable workspace demonstrates every item in the Public
Contract without a hard-coded Domain or Extension name.

### Phase 2 — Production composition mechanism

Goal: turn the successful proof into the smallest maintained implementation.

- [x] Implement generic mounted-container discovery from the two nested roots
  and build-time graph validation using the mechanism proven in Phase 1.
- [x] Permit declared cross-container Domain dependencies and declared
  Extension-to-Extension dependencies while retaining cycle and upward-edge
  rejection. No production cross-container Domain edge exists yet; this
  mechanism must pass 0010's proof before a real dependency needs it.
- [x] Include every graph application and its resources in the release.
- [x] Make migrations and runtime contributions consume the approved graph
  without reconstructing it or creating upward dependencies.
- [x] Keep an unmounted capability's applied migrations valid: durable
  migration provenance explains its ledger rows after removal, unexplained
  versions still fail, and a remount must match what was applied.
- [x] Compile Web routes from the same graph and fail collisions before the
  release is produced. Evidence:
  [812](https://github.com/BelimbingApp/bilimbi/pull/812),
  `apps/web/test/bilimbi_web/route_overlap_test.exs`.
- [x] Add boundary tests for absent repositories, invalid graphs, removal, and
  release contents. Evidence: `workspace_boundary_test.exs`,
  `complete_modules_test.exs`, and `composition_lock_test.exs` in
  `apps/base/module_registry/test/`; `migration_provenance_test.exs` and the
  mounted `platform_baseline_e2e_test.exs` in `apps/core/compatibility/test/`;
  `host_closure_test.exs` and `release_test.exs` in `apps/web/test/bilimbi_web/`.
- [x] Run focused tests and `mix precommit`. Evidence: green CI on every
  Phase 2 pull request listed in Sources.

### Phase 3 — First Factory build

Goal: Factory mounts as one repository and its first three modules support Mr Packaging's receipt-to-despatch workflow.

- [x] Create Factory as one independent repository with Inventory, Product Definition, and Production Execution modules, following `docs/plans/factory/0000-factory-domain.md`. Evidence: [b-dom-factory 1](https://github.com/BelimbingApp/b-dom-factory/pull/1), container `factory` at `apps/domains/factory`, CI against a pinned Platform revision.
- [x] Implement Inventory's public material contract following `docs/plans/factory/0010-inventory-module.md`; Production Execution depends on that API and registers as its production posting authority. Evidence: [b-dom-factory 2](https://github.com/BelimbingApp/b-dom-factory/pull/2), [4](https://github.com/BelimbingApp/b-dom-factory/pull/4), [5](https://github.com/BelimbingApp/b-dom-factory/pull/5).
- [x] Prove Factory can be absent when no mounted dependent requires it, and prove a missing Factory dependency fails composition. Evidence: [b-dom-factory 10](https://github.com/BelimbingApp/b-dom-factory/pull/10), the `absent` CI job and `missing_dependency.sh`.
- [x] Prove Inventory owns the only material ledger and genealogy while Production Execution adds run, step, and resource context through its public contract. Evidence: [b-dom-factory 6](https://github.com/BelimbingApp/b-dom-factory/pull/6), [7](https://github.com/BelimbingApp/b-dom-factory/pull/7), [8](https://github.com/BelimbingApp/b-dom-factory/pull/8).
- [ ] Keep Planning, Maintenance, and Costing as later Factory modules until an owner confirms each workflow. Decide Quality's module or Domain placement when its own workflow is built. Status: none of the four is built; Quality is an opaque token in Production Execution ([b-dom-factory 13](https://github.com/BelimbingApp/b-dom-factory/pull/13)), and its placement is undecided.
- [x] Validate the initial modules against Mr Packaging Sdn Bhd's receipt-to-despatch workflow in `docs/plans/factory/mr-packaging-requirements.md`; its current requirements are expected to use Factory configuration without an Extension. Evidence: [b-dom-factory 11](https://github.com/BelimbingApp/b-dom-factory/pull/11), a representative scenario through the public facades with no Extension; the plant values still to confirm are listed in that repository's `docs/mr-packaging-scenario.md`.

### Phase 4 — Second Factory build and first Extension

Goal: SBG validates the same Factory modules through glue, coating, and slitting work, with AX facts entering through the `SbGroup` Extension.

The Extension shipped as container `sbg` in the private repository
`SB-Tape/b-ext-sbg`, mounted at `apps/extensions/sbg`; the plans' `SbGroup`
name refers to it. Only its public contract is recorded in Bilimbi.

- [x] Validate Factory's contracts against SBG's glue, coating, and slitting workflows in `docs/plans/factory/sbg-requirements.md`. Evidence: [b-dom-factory 13](https://github.com/BelimbingApp/b-dom-factory/pull/13), a synthetic scenario through Factory's contracts; the values SBG must confirm and the contract gaps are in that repository's `docs/sbg-scenario.md`.
- [ ] Mount the `SbGroup` AX Connector for confirmed source mapping and submit production history through Production Execution's import contract. Keep process configuration in Factory and SBG-specific integration in `SbGroup`. Status: `sbg/ax_connector` is mounted with a read-only, contract-checked item capture and health read (b-ext-sbg 1 and 2); the production-history import into Production Execution has not merged.
- [x] Keep warehouse receipts and ordinary movements on Inventory's public contract; no Extension owns the common material ledger, genealogy, units of measure, production posting authority, or execution semantics. Evidence: [b-dom-factory 8](https://github.com/BelimbingApp/b-dom-factory/pull/8) proves an Extension cannot register as posting authority or post production context; the connector writes only its own tables.
- [x] Mount a `MrPackaging` Extension only if plant validation finds a specific gap in Factory's public contracts or configuration. Evidence: [b-dom-factory 11](https://github.com/BelimbingApp/b-dom-factory/pull/11) found no such gap; none is mounted.
- [x] Keep each Extension's ownership, visibility, and licensing independent of its architectural role. Evidence: Factory is public under MIT in `BelimbingApp`; SBG is private in `SB-Tape`; both mount through the same discovery.
- [x] Prove the application remains complete with the Extension absent and
  that removing it leaves durable data intact. Evidence: b-ext-sbg 1 (`absent` CI job) and 3 (`removal` CI job: capture a batch, park SBG, rebuild and migrate, remount, read the same batch).

### Phase 5 — Documentation alignment

Goal: architecture, implementation evidence, and roadmap describe the mechanism
that passed.

- [x] Record the proof outcome and chosen runtime mechanism in 0010 without
  duplicating its normative composition rules. claude/claude-fable-5-1
- [x] Update ADR 0003 and ADR 0004 only where the implementation changes their
  accepted contracts. claude/claude-fable-5-1
- [x] Revise `PORTING_STAGES.md` S5 and S6 and record the approved scope change
  under its stage-change rule. claude/claude-fable-5-1
