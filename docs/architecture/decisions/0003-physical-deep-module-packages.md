# ADR 0003: Physical deep-module packages

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** codex/sol-high
**Scope:** Deep-module filesystem boundaries, descriptor-driven Mix
composition, nested Git distribution, tests, documentation, assets, and
migration ownership
**Last Updated:** 2026-08-13

## Context

ADR 0001 established a repository-root Mix umbrella with Base, Core, and Web
as direct applications below `apps/`. Its first implementation placed all Base
code below `apps/base/lib/bilimbi/base` and all Core code below
`apps/core/lib/bilimbi/core`.

That layout preserved conventional namespace-derived source paths but made a
deep module a logical convention spread across a larger application. Removing,
installing, testing, or independently sourcing one module required selecting
files from several parent directories. This conflicts with Bilimbi's intended
distribution model: one module is one installable directory and potential Git
repository mount point.

## Decision

Base and Core are mandatory composition containers. Domains and Extensions are
optional composition containers. Every declared child module is a
self-contained Mix path package whose physical directory is its complete
ownership boundary.

```text
project_root/
├── mix.exs
├── apps/
│   ├── base/                         # Required composition application
│   │   ├── mix.exs
│   │   ├── bilimbi.container.exs
│   │   ├── database/                 # base/database module
│   │   ├── module_registry/          # base/module_registry module
│   │   └── tenancy/                  # base/tenancy module
│   │       ├── mix.exs
│   │       ├── bilimbi.module.exs
│   │       ├── lib/
│   │       │   ├── tenancy.ex
│   │       │   └── tenancy/
│   │       ├── priv/repo/migrations/
│   │       ├── test/
│   │       ├── docs/
│   │       └── assets/               # Optional
│   ├── core/                         # Required composition application
│   │   ├── mix.exs
│   │   ├── bilimbi.container.exs
│   │   ├── company/                  # core/company module
│   │   ├── geonames/                 # core/geonames module
│   │   ├── address/                  # core/address module
│   │   ├── employee/                 # core/employee module
│   │   ├── user/                     # core/user module
│   │   └── compatibility/            # core/compatibility module
│   ├── web/                          # Phoenix host and shared shell
│   ├── sales/                        # Optional Domain composition/bundle
│   │   ├── mix.exs
│   │   ├── bilimbi.container.exs
│   │   └── order/                    # sales/order module/Git mount
│   │       ├── mix.exs
│   │       ├── bilimbi.module.exs
│   │       ├── lib/
│   │       │   ├── order.ex
│   │       │   └── order/
│   │       ├── priv/repo/migrations/
│   │       ├── test/
│   │       ├── docs/
│   │       └── assets/               # Optional
│   └── sb_group/                     # Optional Extension composition/bundle
│       ├── mix.exs
│       ├── bilimbi.container.exs
│       └── qac/                      # sb_group/qac module/Git mount
│           ├── mix.exs
│           ├── bilimbi.module.exs
│           ├── lib/
│           ├── priv/repo/migrations/ # Optional
│           ├── test/
│           └── docs/
```

The module directory already supplies platform, layer, and module context.
Source paths therefore begin at the module boundary instead of repeating that
context below `lib/`:

| Physical boundary | Public facade | Elixir namespace |
|---|---|---|
| `apps/base/tenancy/` | `lib/tenancy.ex` | `Bilimbi.Base.Tenancy` |
| `apps/core/company/` | `lib/company.ex` | `Bilimbi.Core.Company` |
| `apps/sales/order/` | `lib/order.ex` | `Bilimbi.Sales.Order` |

Elixir namespaces remain globally qualified. Mix compiles source recursively
from `lib/`; it does not derive a module name from the filesystem path.

Each path package has a technical OTP application ID such as
`:bilimbi_base_tenancy` or `:bilimbi_core_company`. That identity lets Mix
compile, package, and include its `priv` directory. It does not make the module
a separate business application or require a supervisor when the module owns
no processes.

Each module root contains:

- `mix.exs`, giving the module an independently compilable package identity;
- `bilimbi.module.exs`, declaring stable ID, layer, dependencies, namespace,
  required/optional state, and migration contribution;
- `lib/`, beginning with the module facade and its hidden implementation;
- `priv/repo/migrations/` when the module owns database structure;
- `test/`, including module-owned fixtures and support;
- `docs/`, describing its public and compatibility contracts;
- optional `assets/` and presentation contributions owned by the module.

Each composition root contains `bilimbi.container.exs`, which declares its
stable container ID and layer. Its `mix.exs` calls the shared discovery helper
and never enumerates Database, Tenancy, Company, Address, Compatibility, or any
other child. Discovery treats each immediate non-hidden child directory as an
installed module and requires `bilimbi.module.exs` at that child's root. Thus
mounting `apps/base/mailer/` or `apps/sales/order/` is sufficient to change
source composition; Mix dependency resolution and compilation incorporate it.

Base ModuleRegistry physically owns the source-loadable helper at
`apps/base/module_registry/mix/module_discovery.exs`. Containers locate that
mandatory Base capability by generic contribution path rather than naming its
directory as an installed child. Its own formatter and tests cover the helper;
no load-bearing composition code lives outside a module boundary.

A module descriptor is executable Elixir data with one exact contract:

```elixir
[
  id: "base/tenancy",
  kind: :module,
  layer: :base,
  required: true,
  otp_app: :bilimbi_base_tenancy,
  namespace: Bilimbi.Base.Tenancy,
  dependencies: ["base/database"],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Base.Tenancy.SchemaContract
]
```

The descriptor is the source of truth for stable ID, kind/layer, OTP
application ID, namespace, declared module dependencies, required state, and
whether and where the module contributes migrations. `schema_contract` names a
compatibility verifier when one exists. A module's `mix.exs` may declare
external package dependencies it actually owns, but obtains Bilimbi module
path dependencies and runtime descriptor metadata generically. Composition
containers own no speculative library dependencies.

The umbrella remains conventional: Mix sees Base, Core, Web, and any installed
Domain or Extension composition applications as direct children below
`apps/`, while each container discovers its nested module packages.

Discovery validates the complete installed graph during Mix dependency
resolution. It rejects malformed and missing descriptors, duplicate stable
module IDs, duplicate OTP application IDs, missing declared dependencies,
dependency cycles, child/container layer mismatches, stable IDs outside their
container, nonexistent migration paths, and forbidden dependency directions.
Ordering is a deterministic topological sort: dependencies come first; among
simultaneously eligible modules, layer and then stable module ID are the
tie-breakers.

Mix stores each validated descriptor together with its zero-based resolved
position and workspace-graph fingerprint in OTP application metadata. Each
module package runs the shared `:bilimbi_graph` compiler before Mix's standard
compilers. The compiler fingerprints every installed container and module
descriptor and refreshes a package's application resource when that graph
changes, including when an independently mounted sibling shifts existing
positions. Runtime ModuleRegistry requires one common fingerprint, verifies
that positions are contiguous, layer-monotonic, and dependency-safe, then
consumes them directly. It does not maintain a second topological-sort
implementation.

Source composition and runtime visibility are distinct. Discovery makes a
mounted module available as a path package, but ModuleRegistry can enumerate
only loaded OTP applications in a runtime consumer's dependency closure. A
runtime coordinator's descriptor must therefore declare stable dependencies
on every installed contributor it must enumerate. Compatibility depends on
each current migration or schema-contract contributor while its code continues
to discover descriptors, paths, and contracts generically; it contains no
module-specific path list. A workspace-boundary regression must fail if an
installed contributor is missing from that runtime closure.

The Base and Core containers are deliberately composition-only and have no
`lib/`, `priv/`, or `test/` directory and no application callback. Runtime
processes, resources, and tests are owned by child packages. Their Mix projects
delegate umbrella-level test execution to each child package, keeping test
helpers and support compiled within their owner. Cross-module schema
coordination belongs to `apps/core/compatibility/`, not the Core container. A
future Base capability such as Mailer must be introduced as `apps/base/mailer/`,
not added back to the container.

Composition, contribution, and migration order is:

```text
Base modules → Core modules → optional Domain modules → Extensions
```

Allowed code dependencies point in the opposite direction: Extensions may
depend on Domain/Core/Base contracts, Domains may depend on Core/Base and
declared sibling modules in the same Domain, Core may depend on Base or
declared Core siblings, and Base may depend only on declared Base siblings.
Extensions cannot depend on other Extensions. A module may collaborate with a
sibling only through an explicit public contract and declared dependency; it
must not query the sibling's private schema merely because both are installed.

Base Database owns the shared Ecto Repo. `Bilimbi.Base.Repo` is an intentional
platform-level public name and the documented exception to that package's
primary `Bilimbi.Base.Database` namespace; its physical ownership does not
leave `apps/base/database/`. Module packages ship their own
`priv/repo/migrations` and publish that relative path in their descriptors.
The runtime module registry reads descriptor metadata from installed OTP
applications, and the Compatibility coordinator executes every contributed
path through that one Repo and `bilimbi_schema_migrations` ledger. The
coordinator contains no module-specific path list. Required baseline order is
deterministic: Base before Core before Domain before Extension, with
dependencies further constraining module order. Migration versions are
globally unique across installed modules.

Migration modules are named below their owning descriptor namespace. A
descriptor's schema contract also owns its structural table specification and
optional live-data invariant callback. Compatibility discovers and invokes
those contracts generically and contains no module-specific SQL.

Shared test mechanics follow the same ownership rule. Base Database owns the
single SQL sandbox case. A module may expose test-only fixtures for declared
higher-layer dependants, but its table DDL is defined only in its own test
support. Web integration tests create business state through public module APIs.

Base and Core modules are required parts of the Platform Baseline. A Domain
such as Sales is optional and may be distributed as a bundle repository that
composes independently mounted child module repositories such as Order.
Source installation and runtime enablement remain separate concerns.

## Alternatives Considered

### Keep namespace-derived paths inside flat Base and Core applications

Rejected because module code, migrations, tests, and documentation remain
spread across a parent application and cannot form one drop-in source unit.

### Make the namespace mirror the shortened filesystem path

Rejected. Generic modules such as `Tenancy` or `Company` would collide in the
global BEAM namespace and obscure ownership. Only the internal file path is
shortened; public namespaces remain Bilimbi-qualified.

### Make every module a direct umbrella child

Rejected because it flattens composition and loses the visible Base/Core/
Domain hierarchy. Nested path packages provide independent package boundaries
without pretending every module is a peer of the Phoenix host.

### Keep migrations in the parent composition application

Rejected because uninstalling or distributing a module would omit part of its
persistence contract. Migration coordination is centralized, but migration
ownership remains local.

## Consequences

- A declared module can be mounted, inspected, tested, and distributed as one
  directory or nested Git repository.
- Physical paths communicate ownership without repeating `bilimbi/base` or
  `bilimbi/core` below every module's `lib/`.
- Parent composition applications stay small and express installed modules as
  descriptor-discovered path dependencies.
- Descriptor graph changes invalidate every module package's generated
  application metadata before runtime discovery consumes resolved positions.
- Adding an immediate child directory without a valid descriptor fails fast;
  containers cannot silently ignore a partly installed module.
- The same composition mechanism applies to mandatory Base/Core and optional
  Domain/Extension containers; only their layer and installation policy differ.
- Base and Core have no container-level implementation, runtime resources,
  tests, or empty supervisors; their child modules own all code, processes,
  migrations, seeds, fixtures, tests, and other contributions.
- Generators that assume namespace-derived directories require Bilimbi-aware
  destination paths or a deliberate file move.
- Root formatting, testing, release, and migration commands must include
  nested module packages and their `priv` directories.
- Independently authored modules must coordinate globally unique migration
  versions and declare dependencies accurately.
- ADR 0001 remains the history of the repository-root umbrella decision, but
  this ADR supersedes its flat internal topology and its rejection of module-
  level Mix packages.
