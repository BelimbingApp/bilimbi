# ADR 0001: Flat Bilimbi umbrella topology

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** codex/sol-high
**Scope:** Repository topology, Mix umbrella composition, application identity,
and independently sourced Domains and Extensions
**Last Updated:** 2026-08-11

## Context

Bilimbi is a platform composed from a required Platform Baseline and, later,
independently developed optional sources. Base provides framework
infrastructure, Core is the required platform-owned enterprise Domain, and Web
hosts the Phoenix endpoint and shared presentation shell. Optional Domains and
deployment-owned Extensions must be installable as independent source
repositories without losing their internal full-stack Module boundaries.

The initial Phoenix scaffold is a single Mix project at the repository root.
That shape is useful for generation but cannot express the intended
source ownership and lifecycle cleanly. Keeping all future code below one
`lib/` tree would reduce independently developed Domains to implementation
subdirectories rather than first-class build and source boundaries.

A conventional Mix umbrella puts child projects below a generic `apps/`
directory. Bilimbi instead needs a named composition root where the baseline
components and installed source repositories are direct peers. Mix supports
this through its configurable `apps_path`.

This ADR describes the accepted target topology. The repository has not yet
been converted to it.

## Decision

The Git repository root contains project-wide documentation, governance, and
licensing. Runtime code is composed by a Mix umbrella rooted at `bilimbi/`:

```text
project_root/
├── AGENTS.md
├── DESIGN.md
├── LICENSE
├── README.md
├── docs/
└── bilimbi/                         # Mix umbrella composition root
    ├── mix.exs
    ├── mix.lock
    ├── config/
    ├── base/                        # Platform infrastructure
    ├── core/                        # Required enterprise Domain
    ├── web/                         # Phoenix endpoint and shared UI shell
    ├── people/                      # Example optional Domain source
    └── sb_group/                    # Example Extension source
```

The umbrella project sets `apps_path: "."`. Mix therefore treats direct child
Mix projects below `bilimbi/` as umbrella children. There is no intermediate
`apps/` directory. The `bilimbi/` directory is the composition root, not a
business Module or independently installable source.

Each compiled umbrella child is technically an OTP application. In Bilimbi,
that term describes an Elixir runtime and supervision boundary; it is not the
product noun for software built on the platform.

Bilimbi does not prescribe one fixed business suite. A business application is
a deployment composed from the Platform Baseline, selected Domains, and any
deployment-owned Extensions. An ERP is one intended class of business
application that can be built on Bilimbi.

Baseline component directories use short local names while retaining
globally explicit OTP application identifiers and Elixir namespaces:

| Directory | OTP application ID | Primary namespace | Ownership |
|---|---|---|---|
| `bilimbi/base` | `:bilimbi_base` | `Bilimbi.Base` | Platform infrastructure and shared contracts |
| `bilimbi/core` | `:bilimbi_core` | `Bilimbi.Core` | Required platform-owned enterprise Domain |
| `bilimbi/web` | `:bilimbi_web` | `BilimbiWeb` | Phoenix host, endpoint, router composition, and shared UI shell |

Optional sources use the same short-directory rule while declaring their kind,
stable identity, dependencies, and contributions in a Bilimbi source
manifest. For example, `bilimbi/people` may use the OTP application identifier
`:bilimbi_people` and namespace `Bilimbi.Domains.People`, while
`bilimbi/sb_group` may use `:bilimbi_sb_group` and namespace
`Bilimbi.Extensions.SbGroup`.

Directory names are source mount points, not durable business identities.
Logical Module IDs remain path-independent values such as `core/company`,
`people/payroll`, and `sb-group/qac`.

Each optional Domain or Extension source may be an independent nested Git
repository mounted directly below `bilimbi/`. The parent repository tracks
Base, Core, Web, and umbrella configuration. Optional source paths are managed
through the Bilimbi source lifecycle and are not absorbed into the parent
repository's history.

An optional Domain is one installation and lifecycle unit that may contain
multiple deep Modules. For example, the `people` Domain can contain
Attendance, Claim, Leave, and Payroll Modules. Those Modules do not become
separate umbrella children merely because they are full-stack ownership
boundaries.

Umbrella children share the build, configuration, dependencies, and lock file.
Because they are one directory below the umbrella root, their Mix projects use
paths relative to that depth:

```elixir
[
  build_path: "../_build",
  config_path: "../config/config.exs",
  deps_path: "../deps",
  lockfile: "../mix.lock"
]
```

Installed sources are compiled as part of the umbrella. Domain
enablement remains a separate runtime concern: every contribution surface must
respect centralized Domain state. Extensions are installed according to source
presence unless a later ADR defines a distinct Extension state model.

Dependency direction remains:

```text
Base → Core → enabled Domains → installed Extensions
```

This is discovery and contribution order, not permission for lower layers to
depend on higher ones. Base cannot depend on Core, Domains, or Extensions; Core
cannot require an optional Domain; and a Domain cannot require a
deployment-owned Extension.

## Alternatives Considered

### Keep the generated single Phoenix application

Rejected as the target because it cannot represent independently installed,
compiled, tested, and versioned Domain and Extension sources without building a
parallel source-lifecycle system inside one runtime project.

### Use the conventional `apps/` umbrella directory

Valid Mix practice, but rejected for Bilimbi's canonical topology. A generic
container adds no ownership information, while the named `bilimbi/` umbrella
clearly identifies the runtime composition root and lets independently sourced
applications mount as its direct children.

### Use `apps/bilimbi/{application}`

Rejected because it keeps both generic and named container layers. The extra
depth provides no Mix or Bilimbi lifecycle benefit.

### Group sources below `bilimbi/domains/` and `bilimbi/extensions/`

Rejected because ordinary umbrella discovery operates on direct children of
`apps_path`. Extra physical grouping would require custom recursive application
discovery or generated dependency configuration. Source manifests, namespaces,
and stable IDs already express whether a source is a Domain or Extension.

### Make every Module an umbrella child

Rejected because Module ownership and source lifecycle are different
boundaries. Excess runtime projects would expose internal structure, multiply
dependency and supervision edges, and prevent a Domain from being managed as
one coherent installation unit.

## Consequences

- Mix, Phoenix, Ecto, and asset commands run from `project_root/bilimbi`.
- CI, release, container, and editor configuration must use `bilimbi/` as the
  Elixir working directory.
- Some generators and third-party tools assume the conventional `apps/`
  directory and may require explicit paths or small Bilimbi wrappers.
- Direct children of `bilimbi/` that contain a Mix project are potential
  umbrella children; unrelated Mix projects must live elsewhere.
- Installing, updating, or removing Elixir source requires dependency
  resolution, compilation, and normally a release rebuild or restart.
- An installed but disabled Domain may remain compiled, but its routes,
  supervision children, menus, settings, jobs, migrations, and other
  contributions must all be filtered consistently by Domain state.
- Full-stack presentation remains with its owning Module. The Web application
  owns only the host endpoint, router composition, shared shell, and genuinely
  platform-wide web components.
- The current root Phoenix scaffold requires a coordinated umbrella conversion
  before Base and Core implementation proceeds. Partial coexistence of the old
  root application and the target umbrella is not a supported steady state.
