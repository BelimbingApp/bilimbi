# docs/plans/domain-extension-layer-rollout.md

**Status:** Proposed — Phase 1 must prove the composition model
**Last Updated:** 2026-09-25
**Sources:**
- `docs/architecture/0010_composition-model.md`
- Review by sol (2026-08-16)
- ADR 0003 physical deep-module packages
- ADR 0004 module contribution contract
- `docs/PORTING_STAGES.md` (S5, S6, stage-change rule)
- `AGENTS.md` §4
- `apps/base/module_registry/`
- [Pull request 804](https://github.com/BelimbingApp/bilimbi/pull/804)
- Factory plan `docs/plans/factory/0000-factory-domain.md`
- Inventory module plan `docs/plans/factory/0010-inventory-module.md`
- Customer plan `docs/plans/factory/mr-packaging-requirements.md`
- Customer plan `docs/plans/factory/sbg-requirements.md`

**Agents:** claude/claude-opus-5 (earlier work),
amp/medium-sol (architecture review only), codex/gpt-5 (earlier work),
codex/gpt-5.6-luna (earlier work), codex/gpt-6-luna-xhigh (earlier work), codex/gpt-6-sol-medium (Factory boundary revision),
claude/claude-opus-5.5 (no-mistakes review agent)

## Problem Essence

Bilimbi discovers its current Base and Core modules, but it has not proved that
independent Domain and Extension repositories mounted under `apps/domains/` and
`apps/extensions/` can become one valid release without Platform code naming
or depending on them.

## Desired Outcome

A company mounts the Domain and Extension repositories it needs, Bilimbi
discovers and validates the complete graph, and the company compiles it into a
binary containing all mounted capabilities and their routes, migrations, and
contributions.

Repository presence is the only composition choice. Bilimbi does not require a
second installed-capability list or prescribe how the company operates the
binary.

## Current Machinery

The following facts have already been verified:

- Domain and Extension are accepted descriptor layers.
- Discovery finds Base and Core containers as direct children of `apps/` and
  mounted containers under `apps/domains/{domain}` and
  `apps/extensions/{extension}`, as described in
  `apps/base/module_registry/docs/README.md`. Formatter, Tailwind, guard-glob,
  precommit, and strict-compile traversal of the nested roots remain open.
- The graph validator already rejects missing dependencies, duplicate
  identities, and cycles within the graph it sees.
- The dependency validator permits declared same-layer edges across mounted
  repositories (Domain to Domain, Extension to Extension) and still rejects
  cycles and upward edges.
- Runtime consumers see mounted modules through Web's host closure, and
  `ModuleRegistry.complete_modules!/0` refuses a runtime missing any graph
  module; `docs/architecture/database.md` owns the database-task consequence.
- Web's route manifest is generated from descriptors on disk. That matches
  repository-presence selection, but a release still must prove that every
  routed application is included and that conflicts fail before compilation.
- The repository has no proven company release containing independently
  mounted capabilities.

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

### Prove runtime visibility before choosing a mechanism

The source graph is visible at Mix time, while some current runtime consumers
depend on OTP dependency closure. The spike must prove the smallest bridge
that includes optional applications and their contributions without Base or
Core depending upward. This plan does not preselect a generated manifest,
runtime scan, or release-loading design.

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

- [ ] Mount two throwaway Domain repositories under `apps/domains/` and two
  Extension repositories under `apps/extensions/`, each with a valid container
  and at least one module.
- [ ] Prove Mix includes both nested roots in builds and releases while Base,
  Core, and Web remain direct umbrella children. Update discovery, graph
  fingerprint inputs, root formatter subdirectories, route and boundary scans,
  and every fixed-depth `apps/*/*` guard glob for the two nested roots without
  a list of optional capability names. Include Domain templates in Tailwind
  sources and mounted modules in precommit and strict compilation. Prove Web
  includes mounted container dependencies without hard-coded capability names.
  Verify that Git ignore rules prevent accidental tracking of repositories.
- [ ] Prove a declared cross-repository Domain dependency and a declared
  Extension-to-Extension dependency, with cycle rejection for both.
- [ ] Treat those synthetic edges only as mechanism fixtures; every production
  same-layer dependency must separately pass 0010's business-necessity test.
- [ ] Confirm the parent Bilimbi repository neither owns nor records the nested
  repositories.
- [ ] Decide and prove lockfile ownership when a mounted repository adds a Hex
  dependency; unmounting it must not silently rewrite another owner's lockfile.
- [ ] Prove a Domain repository's CI can check out a pinned Platform revision,
  mount itself, and run its build checks without an unpublished local workspace.
- [ ] Prove discovery includes every mounted module without a central list and
  rejects a missing dependency, duplicate identity, forbidden direction, and
  cross-repository cycle.
- [ ] Prove Domain and Extension migrations run without Core depending on
  either capability; record the runtime-visibility mechanism and invariant.
- [ ] Prove Web compiles and serves mounted routes and rejects a route conflict
  without naming either capability.
- [ ] Prove settings, authorization, menu, and schema contributions derive from
  the same mounted graph.
- [ ] Build a release and boot it without source, Mix, or a compiler.
- [ ] Remove one mounted repository, force a clean rebuild of every remaining
  graph application, and prove one fresh fingerprint, no removed code or
  contribution, and unchanged durable data.
- [ ] Delete the throwaway repositories and experimental code after recording
  the result.

Risks: the proof may show that the current umbrella, Phoenix router, or runtime
application model needs a different composition mechanism. That is a valid
result; revise 0010 rather than weakening its boundaries.

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
- [ ] Compile Web routes from the same graph and fail collisions before the
  release is produced.
- [ ] Add boundary tests for absent repositories, invalid graphs, removal, and
  release contents.
- [ ] Run focused tests and `mix precommit`.

### Phase 3 — First Factory build

Goal: Factory mounts as one repository and its first three modules support Mr Packaging's receipt-to-despatch workflow.

- [ ] Create Factory as one independent repository with Inventory, Product Definition, and Production Execution modules, following `docs/plans/factory/0000-factory-domain.md`.
- [ ] Implement Inventory's public material contract following `docs/plans/factory/0010-inventory-module.md`; Production Execution depends on that API and registers as its production posting authority.
- [ ] Prove Factory can be absent when no mounted dependent requires it, and prove a missing Factory dependency fails composition.
- [ ] Prove Inventory owns the only material ledger and genealogy while Production Execution adds run, step, and resource context through its public contract.
- [ ] Keep Planning, Maintenance, and Costing as later Factory modules until an owner confirms each workflow. Decide Quality's module or Domain placement when its own workflow is built.
- [ ] Validate the initial modules against Mr Packaging Sdn Bhd's receipt-to-despatch workflow in `docs/plans/factory/mr-packaging-requirements.md`; its current requirements are expected to use Factory configuration without an Extension.

### Phase 4 — Second Factory build and first Extension

Goal: SBG validates the same Factory modules through glue, coating, and slitting work, with AX facts entering through the `SbGroup` Extension.

- [ ] Validate Factory's contracts against SBG's glue, coating, and slitting workflows in `docs/plans/factory/sbg-requirements.md`.
- [ ] Mount the `SbGroup` AX Connector for confirmed source mapping and submit production history through Production Execution's import contract. Keep process configuration in Factory and SBG-specific integration in `SbGroup`.
- [ ] Keep warehouse receipts and ordinary movements on Inventory's public contract; no Extension owns the common material ledger, genealogy, units of measure, production posting authority, or execution semantics.
- [ ] Mount a `MrPackaging` Extension only if plant validation finds a specific gap in Factory's public contracts or configuration.
- [ ] Keep each Extension's ownership, visibility, and licensing independent of its architectural role.
- [ ] Prove the application remains complete with the Extension absent and
  that removing it leaves durable data intact.

### Phase 5 — Documentation alignment

Goal: architecture, implementation evidence, and roadmap describe the mechanism
that passed.

- [ ] Record the proof outcome and chosen runtime mechanism in 0010 without
  duplicating its normative composition rules.
- [ ] Update ADR 0003 and ADR 0004 only where the implementation changes their
  accepted contracts.
- [ ] Revise `PORTING_STAGES.md` S5 and S6 and record the approved scope change
  under its stage-change rule.
