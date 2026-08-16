# Bilimbi Composition Model

**Document Type:** Proposed architecture reference
**Status:** Proposed for review
**Agents:** claude/claude-opus-5, amp/medium-sol
**Scope:** The product meaning of Platform, Domains, and Extensions, and a
tentative nested-Git realization
**Last Updated:** 2026-08-16

## Purpose

The three principles define the product model. The constraints protect its
boundaries. The nested-Git realization is a hypothesis to prove, not an
authorized implementation or amendment to `AGENTS.md`.

If the realization fails, change the mechanism rather than the principles.

## Vocabulary

- **Platform:** The mandatory Base and Core foundation.
- **Web:** The Platform-owned presentation host, not a business layer.
- **Business application:** The Platform, selected Domains and Extensions, and
  deployment configuration that a company builds and operates.
- **Domain:** An optional, cohesive business capability with meaning of its own,
  such as Inventory, Manufacturing, Payroll, Maintenance, or CRM.
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

    Extension
      ▼
    Domain
      ▼
    Core
      ▼
    Base

Dependencies may point to the same or a lower layer (toward Base). Every dependency is
declared and the graph is acyclic. Base and Core never depend on optional
capabilities, and a Domain never depends on an Extension.

### The company owns its build

The company selects trusted source and compiles it into its own binary. Bilimbi
supplies source and composition tooling but neither owns the binary nor
prescribes how the company operates it. Selected capabilities are trusted
application code, not sandboxed plugins.

Removing source removes its code from the next build; it does not delete
durable data.

## Tentative nested-Git realization

A company starts with the main Bilimbi checkout and mounts selected Domain and
Extension repositories below `apps/`:

```text
business-application/
├── apps/
│   ├── base/                    # Platform, main Bilimbi Git
│   ├── core/                    # Platform, main Bilimbi Git
│   ├── web/                     # Web host, main Bilimbi Git
│   ├── commerce/                # Domain, owns commerce/.git
│   ├── manufacturing/           # Domain, owns manufacturing/.git
│   ├── tax_adapter/             # Extension, owns tax_adapter/.git
│   └── acme_operations/         # Extension, owns its own .git
├── mix.exs
└── mix.lock
```

These are ordinary independent repositories, not Git submodules. Each owns its
Git history and access. The enclosing Bilimbi repository ignores and does not
record them. The company decides how to record, reproduce, mirror, or back up
its selected sources. Ignore rules prevent accidental tracking; they are not a
security boundary.

### Composition flow

1. A mounted repository presents one Domain or Extension container through
   `bilimbi.container.exs`.
2. Its immediate child modules declare identities, dependencies, migrations,
   and contributions through `bilimbi.module.exs`.
3. Bilimbi discovers every mounted container and rejects malformed descriptors,
   missing or forbidden dependencies, cycles, and duplicate identities.
4. The company compiles the validated graph and its contributions into one
   binary release.
5. The binary runs without source, Mix, a compiler, or runtime installation of
   unmounted code.

Repository presence is the tentative selection boundary: every valid module in
a mounted repository participates. Finer module-level selection is deferred
until a real capability requires it.

Git obtains source; discovery does not search GitHub or download dependencies.
A dependency from another repository must already be mounted.

### Contributions

Selected modules may contribute routes, migrations, schema contracts, settings,
authorization definitions, menus, and other supported metadata. Generic
Platform tooling consumes them without naming or depending on optional
capabilities.

Web hosts selected presentation contributions without knowing Domain or
Extension names. Contributors retain ownership of their business rules and
presentation adapters. Invalid or conflicting contributions fail the build.

The proof must determine the smallest compile-time and runtime mechanisms that
meet these requirements.

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
3. support the necessary same-layer dependencies without hidden layers;
4. compile and serve their Web contributions;
5. consume their migrations and metadata without upward Platform dependencies;
6. remove their code and contributions without deleting durable data; and
7. produce a binary that boots without source, Mix, or a compiler.

Only then should an implementation plan choose router integration, migration
coordination, generated metadata, or other concrete mechanisms and amend the
normative architecture rules.
