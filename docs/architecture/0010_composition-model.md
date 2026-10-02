# Bilimbi Composition Model

**Document Type:** Normative architecture standard
**Status:** Current — realized; the proof passed on 2026-09-26
**Architecture ID:** 0010 (reserved; do not reuse for an ADR)
**Agents:** claude/claude-opus-5, amp/medium-sol, codex/gpt-6-sol-medium,
claude/claude-fable-5-1 (realization outcome)
**Scope:** Platform, Domain, Extension, composition, and nested-Git rules
**Last Updated:** 2026-09-27

## Purpose

This document is Bilimbi's normative source of truth for composition. The three
principles define the product model, the constraints protect its boundaries,
and the nested-Git section defines the mechanism.

The realization proof validated the mechanism before optional capabilities
shipped; [Realization outcome](#realization-outcome) records what it chose.
Any later result that changes these rules must revise this standard rather
than silently weakening it.

## Vocabulary

- **Platform:** The mandatory Base and Core foundation.
- **Web:** The Platform-owned presentation host, not a business layer.
- **Business application:** The Platform, selected Domains and Extensions, and
  deployment configuration that a company builds and operates.
- **Domain:** An optional, cohesive business capability with meaning of its own,
  such as Factory, People, or CRM. A Domain can contain several modules that an adopter installs together.
- **Extension:** An optional capability whose meaning comes from adding to or
  adapting existing Platform, Domain, or Extension capabilities.
- **Module:** A deep implementation boundary with a small public API. A module
  is not automatically a repository, installation choice, package, or release
  unit.
- **Composition:** The selected source and its descriptor-derived dependency
  graph for one business application.

## Principle 1 — Bilimbi provides the Platform

Bilimbi provides Base and Core as the mandatory foundation for many kinds of
business application, including a complete ERP. The main Bilimbi repository
owns this Platform source and its Web host.

Platform code must remain broadly useful. Optional industry workflows and
company-specific behavior belong outside Base and Core.

## Principle 2 — Companies compose applications from Domains

A company chooses the business capabilities it needs. It may develop its own
Domains or obtain them from GitHub or another source. Different selections
produce different business applications from the same Platform.

Selected source determines composition membership; there is no second
hand-maintained list of installed Domains.

## Principle 3 — Companies adapt applications with Extensions

A company may select or develop Extensions to adapt the Platform, Domains, or
other Extensions to its needs.

An Extension may be public or private, reusable or bespoke, and owned by
anyone. Architectural role does not depend on ownership, visibility, licensing,
or distribution.

## Architectural constraints

### Respect ownership boundaries

Each module owns its implementation and related resources. Other modules use
its public API and supported contribution points, not its private internals. A
missing extension point requires an improved public contract or an integration
outside that boundary, not an accidental private API.

### Keep dependencies explicit and downward

```diagram
Extension
    │ depends on
    ▼
Domain
    │ depends on
    ▼
Core
    │ depends on
    ▼
Base
```

Dependencies may point to the same or a lower layer toward Base. Every
dependency is declared and the graph is acyclic. Base and Core never depend on
optional capabilities, and a Domain never depends on an Extension.

A same-layer dependency is legitimate only when a concrete business invariant
requires the other capability's public contract and lower-layer contracts
cannot satisfy it. Before adding the edge, consider whether the capabilities
should merge or whether a genuinely shared contract belongs lower in the
architecture. Code reuse, repository proximity, and implementation convenience
are insufficient reasons. The dependency must be declared and acyclic and
grants no access to private internals. This rule applies equally to Domain-to-
Domain and Extension-to-Extension dependencies.

### The company owns its build

The company selects trusted source and compiles it into its own binary. It is
responsible for reviewing the owner, source, and revision it selects; mounting
code does not establish provenance or safety. Bilimbi supplies source and
composition tooling but neither owns the binary nor prescribes how the company
operates it. Selected capabilities are trusted application code, not sandboxed
plugins.

Removing source removes its code from the next build; it does not delete
durable data.

## Nested-Git composition

A company starts with the main Bilimbi checkout and mounts each selected Domain
under `apps/domains/` and each Extension under `apps/extensions/`. These folders
group repository roles; each named child, such as `factory/`, is the independent
repository and composition container:

```text
business-application/
├── apps/
│   ├── base/                    # Platform, main Bilimbi Git
│   ├── core/                    # Platform, main Bilimbi Git
│   ├── web/                     # Web host, main Bilimbi Git
│   ├── domains/
│   │   └── factory/             # Domain, owns factory/.git
│   └── extensions/
│       ├── tax_adapter/         # Extension, owns tax_adapter/.git
│       └── acme_operations/     # Extension, owns its own .git
├── mix.exs
└── mix.lock
```

The role folders make a repository's architectural role visible from its path
and keep the Platform-owned `apps/*` allowlist fixed. They follow Belimbing's
Domain and Extension source grouping; mounted repositories still follow
Bilimbi's Mix and descriptor contracts.

Each mounted repository is a container Mix project and descriptor boundary;
each immediate child module is also a Mix project and descriptor boundary:

```text
factory/
├── .git/
├── bilimbi.container.exs
├── mix.exs
├── inventory/
│   ├── bilimbi.module.exs
│   └── mix.exs
├── product_definition/
│   ├── bilimbi.module.exs
│   └── mix.exs
└── production_execution/
    ├── bilimbi.module.exs
    └── mix.exs
```

These are ordinary independent repositories, not Git submodules. Each owns its
Git history and access. The enclosing Bilimbi repository ignores and does not
record them. The company decides how to record, reproduce, mirror, or back up
its selected sources. Ignore rules prevent accidental tracking; they are not a
security boundary.

### Composition flow

1. A mounted repository presents one Domain or Extension container through
   `bilimbi.container.exs` and a container `mix.exs` using generic discovery.
2. Its immediate child modules declare identities, dependencies, migrations,
   and contributions through `bilimbi.module.exs`; each module's `mix.exs`
   derives its application metadata and path dependencies from that descriptor.
3. Bilimbi discovers every mounted container and rejects malformed descriptors,
   missing or forbidden dependencies, cycles, and duplicate identities.
4. The company compiles the validated graph and its contributions into one
   binary release.
5. The binary runs without source, Mix, a compiler, or runtime installation of
   unmounted code.

Repository presence is the selection boundary: every valid module in a mounted
repository participates. Finer module-level selection is deferred until a real
capability requires it.

Git obtains source; discovery does not search GitHub or download dependencies.
A dependency from another repository must already be mounted.

### Composition dependency lock

The Platform's tracked `mix.lock` is authoritative only when no optional
repository is mounted. Once any Domain or Extension is mounted, every Mix
project uses the same ignored `.scratchpad/composition-lock/mix.lock` overlay,
selected by `mix/composition_lock.exs`. The Platform lock is the initial
input for a new overlay; mounted dependency resolution and
`deps.unlock --unused` write only the overlay. The manifest beside the overlay
records the Platform lock SHA-256 the overlay was derived from. When the
checked-out Platform lock differs, the next Mix project load re-derives the
overlay: every package the Platform lock contains takes the Platform's locked
entry, mounted-only packages are kept, and `mix deps.get` resolves the rest.
Pinned CI refuses that mismatch instead of re-deriving. Unmounting the last
repository selects the Platform lock again without deleting or rewriting either lock.
Mounted container and module `mix.exs` files must require that helper from the
Platform root and set `lockfile: Bilimbi.CompositionLock.lockfile!(workspace_root)`;
they must not point at a repository-local or Platform lock.

One composition build resolves **all** selected Domain and Extension
dependencies together with `mix deps.get`, then checks the complete graph with
`mix deps.loadpaths`. Individual repository lockfiles are not merged: one lock
entry serves every repository, so transitive version requirements that entry
cannot satisfy together fail dependency checking, and a dependency given from
divergent sources is rejected, rather than selecting one repository's
transitive version. After the sources and lock are settled,
run `mix bilimbi.composition.lock --pin` at the Platform root. It writes
`manifest.txt` beside the overlay with the exact Platform and mounted Git HEAD
revisions plus the Platform and overlay lock SHA-256s. The repositories must
be independent Git checkouts with clean tracked files. The company owns and
publishes the overlay and manifest together as one build artifact; neither
belongs in Platform Git or any mounted repository's Git history.

Pinned CI checks out the manifest's Platform revision, mounts **every** listed
repository at its listed revision, and restores both artifact files to the
composition lock directory. It sets `BILIMBI_COMPOSITION_PINNED=1` and runs
`mix deps.get --check-locked`, then `mix deps.loadpaths`. Project loading rejects
a missing artifact, changed revision, changed mounted set, or changed lock bytes
before dependency fetching. `--check-locked` refuses dependency resolution that
would change the pinned lock. A new selection or dependency constraint requires
one new composition resolution and published artifact, rather than a Domain CI
copy of a whole lock.

### Contributions

Selected modules may contribute routes, migrations, schema contracts, settings,
authorization definitions, menus, and other supported metadata. Generic
Platform tooling consumes them without naming or depending on optional
capabilities.

The composition graph declares database contributors and their dependencies;
the ownership, migration, verification, and adoption semantics are defined in
[Database Architecture](./database.md). Do not create a separate database
dependency graph beside the module descriptors.

Workflow status definitions use the same snapshot through the `:workflow`
consumer ([ADR 0018](./decisions/0018-workflow-status-contribution-consumer.md)).
Owner-proven adapters execute business rules; exact legacy aliases interpret
retained data without introducing an upward dependency or another registry.

Web hosts selected presentation contributions without knowing Domain or
Extension names. Contributors retain ownership of their business rules and
presentation adapters. Invalid or conflicting contributions fail the build.

The compile-time and runtime mechanisms that meet these requirements are
recorded under [Realization outcome](#realization-outcome).

## Deferred alternatives

- **Git submodules:** need a company-owned parent repository to record links.
- **Outer deployment repository:** needs a different workspace or overlay.
- **Published packages:** add package and compatibility lifecycles before they
  are needed.
- **Runtime installation:** complicates artifact contents, routes, and
  migrations and is not the initial model.

## Realization proof

One disposable workspace must demonstrate, without hard-coded capability names,
that Bilimbi can:

1. discover one mounted Domain and one mounted Extension;
2. validate their identities and dependency graph before building;
3. accept declared, public, acyclic same-layer dependencies and reject cycles
   and forbidden directions;
4. compile and serve their Web contributions;
5. consume their migrations and metadata without upward Platform dependencies;
6. remove their code and contributions without deleting durable data; and
7. produce a binary that boots without source, Mix, or a compiler.

The implementation plan used the proof to choose the concrete mechanisms
below. Any result that changes these rules must revise this standard
explicitly.

## Realization outcome

Three disposable workspaces ran the proof on 2026-09-26 with four throwaway
repositories (two Domains, two Extensions, with a cross-repository Domain edge
and an Extension-to-Extension edge). All seven items passed once three gaps
were closed: a mounted Hex dependency rewrote the Platform's tracked lock, the
migration ledger refused an unmounted repository's applied versions, and a
mounted route overlapping a Core parameter route was served by Core. The
production mechanism shipped the same day and is exercised by the first two
real compositions, the public Factory Domain
(`BelimbingApp/b-dom-factory`, mounted at `apps/domains/factory`) and a
private customer Extension mounted under `apps/extensions/`.
The rollout record is `docs/plans/domain-extension-layer-rollout.md`.

The chosen mechanisms, each owned where it is enforced:

- **Discovery.** Mounted containers are found one level below the two role
  roots with no list naming them; the container ID equals its directory and
  its OTP application name, the layer must match the root, and `base`,
  `core`, and `web` are reserved. Same-layer edges may cross repositories.
  Owner: `apps/base/module_registry/docs/README.md`.
- **Runtime visibility.** The host application's OTP closure is the
  discovered graph: Web takes a path dependency on every discovered container
  through `optional_container_dependencies/1`, and the `bilimbi` release is
  built around Web. Every production entry point (host boot, the database Mix
  tasks, and the release migrate and seed commands) calls
  `ModuleRegistry.complete_modules!/0` first and refuses a runtime that has
  loaded only part of the graph. Package-local test runs may see a subset.
  The rejected alternatives were a generated graph manifest loaded at
  runtime, a runtime scan of the code path, and Core Compatibility depending
  on mounted containers; the last is an upward dependency this standard
  forbids. Owner: `apps/base/module_registry/docs/README.md` and
  `docs/architecture/database.md`.
- **Routes.** `BilimbiWeb.RouteOverlap` runs after the host router compiles
  and fails `mix compile` when two routes of the compiled table can match the
  same request, owner taken from descriptor layer and source. A stricter
  route placed earlier by the same owner is the one allowed overlap. Owner:
  `apps/web/lib/bilimbi_web/route_overlap.ex`.
- **Migrations and durable data.** Mounted migrations run through the one
  ledger from the host closure, and `bilimbi_migration_provenance` records
  each applied version's owner, disposition, and checksum, so unmounting keeps
  data and ledger valid and a remount cannot change an applied file. Owner:
  `docs/architecture/database.md`.
- **Dependency lock.** The composition lock overlay and pinned manifest in
  [Composition dependency lock](#composition-dependency-lock).
- **Contributions.** Mounted modules use the same descriptor-owned provider as
  Base and Core, and one snapshot serves every consumer. Conflicts fail
  `mix bilimbi.contributions.verify`, host boot, and the release seed command;
  `mix compile` and `mix release` do not run them, so precommit and CI are the
  build gate for this rule.
- **Mounted-code traversal.** Formatter subdirectories, guard scans, Tailwind
  sources, `precommit.test`, and `compile.strict` derive their paths from
  discovery rather than fixed-depth globs.
- **Repository CI.** A mounted repository's CI checks out the Platform at a
  pinned revision, mounts itself, resolves the composition lock, and runs the
  Platform's precommit, once mounted and once absent; the Factory workflow is
  the reference shape.

One item remains open and is tracked in the rollout plan: a production-profile
release boot is not checked in CI; the proof booted a development-profile
release without source or Mix. The cross-repository same-layer edge is proven
mechanism with no production user yet; the first real one must pass the
business-necessity test above.
