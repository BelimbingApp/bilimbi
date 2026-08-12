# ADR 0001: Mix umbrella application topology

**Document Type:** Architecture Decision Record
**Status:** Superseded by ADR 0003
**Agents:** codex/sol-high
**Scope:** Repository topology, Mix umbrella composition, application identity,
and independently sourced Domains and Extensions
**Last Updated:** 2026-08-12

ADR 0003 retains the repository-root umbrella and the direct Base/Core/Web
applications, but supersedes this record's flat internal source topology, its
namespace-derived Base/Core paths, and its rejection of module-level Mix
packages. The Decision, Alternatives, and Consequences below are retained only
as historical rationale; do not use them as current module-placement or
composition guidance.

## Context

Bilimbi is a platform composed from a required Platform Baseline and, later,
independently developed optional sources. Base provides framework
infrastructure, Core is the required platform-owned enterprise Domain, and Web
hosts the Phoenix endpoint and shared presentation shell. Optional Domains and
deployment-owned Extensions must be installable as independent source
repositories without losing their internal full-stack Module boundaries.

The initial Phoenix scaffold was a single Mix application. That shape could not
express independent source ownership and lifecycle cleanly. A preliminary flat
umbrella placed `base/`, `core/`, and `web/` directly below a custom `bilimbi/`
root, but it added a working-directory layer and required custom paths where
Phoenix, Mix, assets, generators, and editor tooling conventionally expect an
`apps/` umbrella.

The custom root did not improve Domain or Extension independence: a nested Git
source can mount below `apps/` just as it can below any other directory.

## Decision

Bilimbi uses a conventional Mix umbrella rooted at the Git repository:

```text
project_root/
├── mix.exs                         # Mix umbrella project
├── mix.lock
├── config/
├── apps/
│   ├── base/                       # Platform infrastructure
│   ├── core/                       # Required enterprise Domain
│   ├── web/                        # Phoenix endpoint and shared UI shell
│   ├── people/                     # Example optional Domain source
│   └── sb_group/                   # Example Extension source
├── AGENTS.md
├── DESIGN.md
├── LICENSE
├── README.md
└── docs/
```

The umbrella project uses `apps_path: "apps"`. Every direct child Mix project
below `apps/` is an umbrella child. Configuration, dependencies, build output,
and the lock file remain at the repository root according to standard Mix
umbrella conventions.

Each compiled umbrella child is technically an OTP application. In Bilimbi,
that term describes an Elixir runtime and supervision boundary; it is not the
product noun for software built on the platform.

Bilimbi does not prescribe one fixed business suite. A business application is
a deployment composed from the Platform Baseline, selected Domains, and any
deployment-owned Extensions. An ERP is one intended class of business
application that can be built on Bilimbi.

Mix requires an umbrella child directory to match its OTP application ID. The
baseline uses short source names and Bilimbi-qualified Elixir namespaces:

| Directory | OTP application ID | Primary namespace | Ownership |
|---|---|---|---|
| `apps/base` | `:base` | `Bilimbi.Base` | Platform infrastructure and shared contracts |
| `apps/core` | `:core` | `Bilimbi.Core` | Required platform-owned enterprise Domain |
| `apps/web` | `:web` | `BilimbiWeb` | Phoenix host, endpoint, router composition, and shared UI shell |

The repeated segment in a path such as
`apps/base/lib/bilimbi/base/company.ex` is intentional. `apps/base` identifies
the OTP and source boundary, `lib/` is the Elixir source root, and
`bilimbi/base` mirrors the globally qualified `Bilimbi.Base` namespace. These
layers must not be collapsed by introducing generic top-level modules or by
combining Base and Core into one OTP application.

Optional sources use the same short-directory rule while declaring their kind,
stable identity, dependencies, and contributions in a Bilimbi source manifest.
For example, `apps/people` uses `:people` with namespace
`Bilimbi.Domains.People`, while `apps/sb_group` uses `:sb_group` with namespace
`Bilimbi.Extensions.SbGroup`.

Directory names are source mount points, not durable business identities.
Logical Module IDs remain path-independent values such as `core/company`,
`people/payroll`, and `sb-group/qac`.

Each optional Domain or Extension source may be an independent nested Git
repository mounted directly below `apps/`. The parent repository tracks Base,
Core, Web, and umbrella configuration. Optional source paths are managed
through the Bilimbi source lifecycle and are not absorbed into the parent
repository's history.

An optional Domain is one installation and lifecycle unit that may contain
multiple deep Modules. For example, the People Domain can contain Attendance,
Claim, Leave, and Payroll Modules. Those Modules do not become separate OTP
applications merely because they are full-stack ownership boundaries.

Installed sources are compiled as part of the umbrella. Domain enablement
remains a separate runtime concern: every contribution surface must respect
centralized Domain state. Extensions are installed according to source presence
unless a later ADR defines a distinct Extension state model.

Discovery and contribution order remains:

```text
Base → Core → enabled Domains → installed Extensions
```

This order does not permit lower layers to depend on higher ones. Base cannot
depend on Core, Domains, or Extensions; Core cannot require an optional Domain;
and a Domain cannot require a deployment-owned Extension.

## Alternatives Considered

### Keep the generated single Phoenix application

Rejected because it cannot represent independently installed, compiled,
tested, and versioned Domain and Extension sources without building a parallel
source-lifecycle system inside one runtime project.

### Use a custom `bilimbi/` umbrella root

Rejected after an implementation trial. It introduced a second working root,
custom child paths, explicit application discovery, and asset path adjustments
without strengthening source ownership. It also made the repository less
familiar to Phoenix tools and contributors.

### Use `apps/bilimbi/{application}`

Rejected because the extra named container provides no Mix or Bilimbi
lifecycle benefit. The `apps/` directory already names the application
composition boundary conventionally.

### Eliminate namespace repetition with generic modules

Rejected because modules such as `Base` and `Core.Company` are generic in the
global BEAM namespace. `Bilimbi.Base` and `Bilimbi.Core.Company` preserve clear
ownership and avoid collisions. Filesystem repetition is preferable to
ambiguous runtime identity.

### Make every Module an OTP application

Rejected because Module ownership and source lifecycle are different
boundaries. Excess runtime projects would expose internal structure, multiply
dependency and supervision edges, and prevent a Domain from being managed as
one coherent installation unit.

## Consequences

- Mix, Phoenix, Ecto, asset, test, and release commands run from the Git
  repository root.
- Phoenix generators, editor integrations, and common umbrella tooling can use
  their conventional paths.
- Installing a Domain or Extension mounts its nested Git repository directly at
  `apps/{source}` and requires dependency resolution, compilation, and normally
  a release rebuild or restart.
- An installed but disabled Domain may remain compiled, but its routes,
  supervision children, menus, settings, jobs, migrations, and other
  contributions must all be filtered consistently by Domain state.
- Full-stack presentation remains with its owning Module. Web owns only the
  host endpoint, router composition, shared shell, and genuinely platform-wide
  web components.
- The source boundary and the Elixir namespace both remain visible in paths
  such as `apps/base/lib/bilimbi/base`; this is accepted structural clarity,
  not accidental duplication.
