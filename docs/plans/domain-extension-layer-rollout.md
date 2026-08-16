# docs/plans/domain-extension-layer-rollout.md

**Status:** Proposed — Phase 1 must prove the composition model
**Last Updated:** 2026-08-16
**Sources:** `docs/architecture/0010_composition-model.md`; review by sol
(2026-08-16); ADR 0003 physical deep-module packages; ADR 0004 module
contribution contract; `docs/ai-team/PORTING_STAGES.md` (S5, S6,
stage-change rule); `AGENTS.md` §4; `apps/base/module_registry/`; sibling
plan `docs/plans/commerce-material-flow-ledger.md`
**Agents:** claude/claude-opus-5, amp/medium-sol

## Problem Essence

Bilimbi discovers its current Base and Core modules, but it has not proved that
independent Domain and Extension repositories mounted under `apps/` can become
one valid release without Platform code naming or depending on them.

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
- A valid container mounted as a direct child of `apps/` is visible to the
  existing source scan without central registration.
- The graph validator already rejects missing dependencies, duplicate
  identities, and cycles within the graph it sees.
- The current dependency validator permits Domain-to-Domain dependencies only
  inside one container and rejects every Extension-to-Extension dependency.
  Both rules must change to implement 0010's declared, acyclic same-layer
  contract across mounted repositories.
- Runtime migration discovery sees only applications in
  `core/compatibility`'s dependency closure. An optional Domain cannot enter
  that closure through an upward Core dependency, so its migrations currently
  remain invisible.
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

**Mounted independent repositories** are recommended because they satisfy the
current requirement with the existing workspace topology. Git submodules need
a company-owned parent; published packages add a package lifecycle; runtime
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

- [ ] Mount two throwaway Domain repositories and two Extension repositories
  beneath `apps/`, each with a valid container and at least one module.
- [ ] Prove a declared cross-repository Domain dependency and a declared
  Extension-to-Extension dependency, with cycle rejection for both.
- [ ] Confirm the parent Bilimbi repository neither owns nor records the nested
  repositories.
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

- [ ] Implement generic mounted-container discovery and build-time graph
  validation using the mechanism proven in Phase 1.
- [ ] Permit declared cross-container Domain dependencies and declared
  Extension-to-Extension dependencies while retaining cycle and upward-edge
  rejection.
- [ ] Include every graph application and its resources in the release.
- [ ] Make migrations and runtime contributions consume the approved graph
  without reconstructing it or creating upward dependencies.
- [ ] Compile Web routes from the same graph and fail collisions before the
  release is produced.
- [ ] Add boundary tests for absent repositories, invalid graphs, removal, and
  release contents.
- [ ] Run focused tests and `mix precommit`.

### Phase 3 — First real Domains

Goal: stock and sheet-goods repositories behave exactly like the disposable
Domain proved in Phase 1.

- [ ] Create the stock Domain as an independent repository with one cohesive
  initial module.
- [ ] Create the sheet-goods Domain as an independent repository with a
  declared dependency on stock's public contract.
- [ ] Prove either repository can be absent when no mounted dependent requires
  it, and prove a missing stock dependency fails composition.
- [ ] Begin the vertical slices in
  `docs/plans/commerce-material-flow-ledger.md` only after the repository and
  migration path works end to end.

### Phase 4 — First real Extension

Goal: prove adaptation through a supported contract when a real requirement
exists.

- [ ] Mount an Extension only when an actual Platform or Domain adaptation is
  identified; do not invent one merely to populate the layer.
- [ ] Keep its ownership, visibility, and licensing independent of its
  architectural role.
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
