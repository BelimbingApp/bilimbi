# ADR 0006: Module-owned web adapters and route discovery

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** faith-toh
**Scope:** Web adapter placement, route discovery, module dependency on
`phoenix_live_view`, host responsibilities, and AGENTS.md §4/§6 amendment
plan
**Last Updated:** 2026-08-13

## Context

ADR 0003 established physical deep-module packages: each module directory is
the ownership, packaging, and future nested-Git boundary containing its own
`mix.exs`, `lib/`, tests, documentation, descriptor, migrations, and optional
assets. ADR 0004 added the contribution provider for settings, authz, and
menu — three surfaces a module contributes without editing a central list.

Web adapters — LiveViews, controllers, route contributions, and colocated
templates — are a fourth contribution surface that ADRs 0003 and 0004 do not
address. AGENTS.md §4 currently recommends placing them in
`apps/web/lib/bilimbi_web/core/<module>_live/`, which centralises every
module's screens in `apps/web` and creates a growing, contended directory that
is outside the module graph entirely.

### The gap, verified on `main`

| | Discovered from descriptor | Centralised in `apps/web` |
|---|---|---|
| Migrations | ✅ `migrations:` key | |
| Schema contract | ✅ `schema_contract:` key | |
| Production seeds | ✅ OTP app env | |
| Capabilities / menu | ✅ contribution provider | |
| **Routes** | ❌ | `router.ex`, 198 lines, 10 routes |
| **LiveViews** | ❌ | `apps/web/lib/bilimbi_web/live/` |
| **Templates, assets** | ❌ | `apps/web/` |

`apps/web/` has no `bilimbi.module.exs` and no `bilimbi.container.exs` — it is
outside the module graph while `apps/base/` and `apps/core/` are containers
using generic discovery that names no child.

### Why the current placement cannot stay

AGENTS.md §6 says Domains and Extensions use the same discovery contract as
Base and Core. That contract has no UI provision, so every Domain and Extension
inherits the gap. Removing `apps/domains/commerce/catalog/` while its
LiveViews, templates, and routes remain in `apps/web` breaks compilation and
violates:

- §6 — "mounting or removing that one directory changes the container's source
  composition";
- §6 — the module directory is "the ownership, packaging, and future
  nested-Git boundary" containing "its own `mix.exs`, `lib/`, tests,
  documentation, descriptor, and any owned migrations or assets";
- `PORTING_STAGES.md` S5 — "install/remove source composition is
  deterministic";
- S6 — "distribution bundles can mount modules without central child lists".
  `router.ex` **is** a central child list.

Belimbing draws the same line this ADR adopts: Livewire classes and
`Routes/web.php` in the module; blade templates and `components/ui/` global.
`RouteDiscoveryService` globs `ApplicationTopology::contributionPatterns('Routes')`
across Base, Core, Domains, and Extensions — 25 route files, no central list.

### Steward directive

@kiatng has decided: **dir = module**. Controllers and module business view
logic go to the owning module. Assets, CSS, and UI components that have no
single owner belong globally in `apps/web`. Relaxable for Core and Base since
they are always the foundation, but adhere as closely as possible. This is
Belimbing's current pattern.

This ADR records and plans that decision; it does not reopen it.

## Decision

### 1. Module-owned web adapters

A module's LiveViews, controllers, colocated templates, and route
contributions live inside the owning module's `lib/` directory, under a
`web/` sub-namespace:

```text
apps/core/employee/
├── mix.exs
├── bilimbi.module.exs
├── lib/
│   ├── employee.ex              # public facade (Bilimbi.Core.Employee)
│   ├── employee/
│   │   ├── schema.ex
│   │   ├── queries.ex
│   │   └── ...
│   └── employee/web/            # web adapters (Bilimbi.Core.Employee.Web)
│       ├── router.ex            # route contribution
│       ├── live/
│       │   ├── index_live.ex    # Bilimbi.Core.Employee.Web.IndexLive
│       │   ├── show_live.ex
│       │   └── form_live.ex
│       └── controllers/         # when plain controllers are needed
├── test/
├── docs/
└── priv/repo/migrations/
```

The `web/` directory is below the module's `lib/` root. It does not repeat the
platform and layer path. The Elixir namespace is
`Bilimbi.Core.Employee.Web` — the module's globally qualified namespace plus
`Web`, not `BilimbiWeb.Core.EmployeeLive`.

This is more consistent with §6 than `BilimbiWeb.Core.CompanyLive`: the
LiveView is owned by the module that owns the business rules, lives in the
directory that can be mounted/unmounted independently, and compiles inside the
module's OTP application.

### 2. Route discovery via descriptor key

The module descriptor gains a `web:` key naming a route-contribution module:

```elixir
[
  id: "core/employee",
  kind: :module,
  layer: :core,
  required: true,
  otp_app: :bilimbi_core_employee,
  namespace: Bilimbi.Core.Employee,
  dependencies: ["core/company"],
  migrations: "priv/repo/migrations",
  schema_contract: Bilimbi.Core.Employee.SchemaContract,
  contribution_provider: Bilimbi.Core.Employee.Contributions,
  web: Bilimbi.Core.Employee.Web.Router   # <-- new
]
```

The value is `nil` or one module atom that implements a `Router` behavior
owned by Base ModuleRegistry:

```elixir
@callback routes() :: [Bilimbi.Base.ModuleRegistry.Route.t()]
```

Each `Route.t()` carries the path, the LiveView or controller module, the
capability required for authorization, the live session name, and any
pipeline configuration. The host router iterates
`ModuleRegistry.installed_modules!()` in resolved module order and injects
each contribution as a Phoenix Router scope via macros at compile time.

The host `apps/web/lib/bilimbi_web/router.ex` becomes a shell:

- the browser and API pipelines;
- the `fetch_current_scope` / `require_authenticated` plugs;
- the login screen and session controller routes;
- a macro call that expands discovered module routes into scoped
  `live_session` blocks with `on_mount` capability hooks.

No module name is hard-coded in the host router. Removing a module directory
removes its routes from the compiled application without editing `router.ex`.

### 3. Module dependency on `phoenix_live_view`

Module-owned LiveViews mean Base and Core modules depend on the
`phoenix_live_view` **library**. This is not a dependency on the `BilimbiWeb`
**application**, which is what AGENTS.md §4 actually forbids:

> A web module may call a Base or Core API. Base and Core modules must not
> depend on `BilimbiWeb`.

Depending on `phoenix_live_view` and `phoenix` as Hex packages is the same
class of dependency as depending on `ecto` or `phoenix_ecto` — a library
contract, not a reverse application dependency. The module's `mix.exs` adds
`phoenix_live_view` to its `deps/` just as it adds `ecto_sql`.

This is an explicit, recorded choice, not an assumption. The alternative —
keeping LiveViews centralised to avoid the library dependency — was rejected
by the steward directive.

### 4. What stays in the host

`apps/web` remains a plain umbrella child (not a composition container) and
owns only the **host shell**:

- `BilimbiWeb.Endpoint` — Phoenix endpoint, socket, LiveSocket configuration
- `BilimbiWeb.Router` — router shell with pipelines, login routes, and the
  discovered-route expansion macro
- `BilimbiWeb.Layouts` — application layout, flash group, auth layout
- `BilimbiWeb.CoreComponents` — semantic design system components (`<.input>`,
  `<.button>`, `<.badge>`, `<.list>`, `<.header>`, etc.)
- `BilimbiWeb.UserAuth` — session handling, scope propagation, Authz plugs
  and LiveView `on_mount` hooks (used by module routes via the discovery
  mechanism)
- `assets/` — Tailwind CSS, JS hooks, esbuild pipeline, vendor code
- `config/` entries for the endpoint, pubsub, and asset pipeline

`apps/web` does **not** own any module's LiveView, controller, template, or
route. It is the host, not a dumping ground.

### 5. Base and Core relaxation

The steward's directive allows relaxation for Base and Core "since they are
always the foundation." This ADR narrows that latitude:

- **Modules with no UI** (`base/database`, `base/module_registry`,
  `core/compatibility`) use `web: nil` and contribute nothing. No relaxation
  is needed — they simply have no web adapters.
- **Modules with UI** (`core/company`, `core/user`, `core/employee`,
  `core/address`, `core/geonames`, and any future Base module with screens)
  follow the dir=module pattern without exception.

Rationale: Base and Core are where Domains learn the pattern. If Base and Core
exempt themselves, Domains inherit ambiguity. The relaxation is for modules
that genuinely have no UI, not for modules that have UI but prefer the old
centralised placement.

### 6. `apps/web` identity

`apps/web` stays a plain umbrella child with OTP application `:web` and
namespace `BilimbiWeb`. It does **not** become a composition container with a
`bilimbi.container.exs`. It has no children to discover. Its `mix.exs` depends
on each installed module that contributes routes, declared through the same
descriptor graph — but it does not name them manually. The dependency edges
are derived from the `web:` descriptor keys at Mix resolution time, the same
way migration paths are derived from `migrations:` keys.

## Alternatives considered

### Keep centralised LiveViews in `apps/web`

Rejected by the steward directive. It violates the mount/unmount guarantee
(§6), creates a central child list (`router.ex`), and makes `apps/web` the
largest and most contended directory in the repository (Belimbing has 152
Livewire components in Base and Core alone).

### Make `apps/web` a composition container

Rejected. `apps/web` is a single host application, not a container that
discovers children. Giving it a `bilimbi.container.exs` adds ceremony without
benefit — there are no nested module packages to discover.

### Filesystem glob route discovery (as in Belimbing)

Rejected. Bilimbi already has an installed-module descriptor graph (ADR 0003).
Reintroducing topology-specific globs would bypass that graph, risk
discovering fixtures or uninstalled source, and recreate the six-pattern cost
visible in Belimbing's `RouteDiscoveryService`. The `web:` descriptor key is
the same shape as `migrations:` and `contribution_provider:`.

### Central route registry at runtime

Rejected. Routes must be compiled into the Phoenix router at build time for
verified routes (`~p`) to work. A runtime registry would either duplicate the
route table or break compile-time verification. The `web:` key feeds a
compile-time macro expansion, not a runtime lookup.

## Consequences

- A module's LiveViews, controllers, templates, and route contributions live
  in its own directory and can be mounted, unmounted, tested, and distributed
  as one unit.
- The host `router.ex` contains no module-specific route. Adding or removing a
  module directory changes the compiled routes without editing the host.
- Base and Core modules with UI depend on `phoenix_live_view` as a Hex
  package. This is a library dependency, not a reverse application dependency.
- `apps/web` becomes smaller and less contended. It owns the shell, the
  design system, and the endpoint — not every module's screens.
- AGENTS.md §4's recommended placement (`apps/web/lib/bilimbi_web/core/...`)
  is superseded. The new recommended placement is
  `apps/<layer>/<module>/lib/<module>/web/`.
- AGENTS.md §6's module directory contents list gains an optional `web/`
  sub-directory under `lib/` for modules that contribute web adapters.
- The `bilimbi.module.exs` descriptor schema gains the `web:` key. All
  installed descriptors must be updated in the same change that adds discovery
  validation and the host router macro.
- Existing LiveViews in `apps/web/lib/bilimbi_web/live/` must be migrated to
  their owning modules. This is separate migration work, not part of this ADR.
- The `mix bilimbi.contributions.verify` command should be extended to
  validate `web:` providers and route contributions, keeping one verification
  path.

## Migration plan

This ADR records the decision. The migration is separate work, sequenced as:

1. **Descriptor schema** — add `web:` key to `bilimbi.module.exs` validation
   in Base ModuleRegistry. All existing descriptors gain `web: nil`.
2. **Route behavior** — define `Bilimbi.Base.ModuleRegistry.Route` and the
   `Router` callback in Base ModuleRegistry.
3. **Host router macro** — implement the discovered-route expansion macro in
   `apps/web/lib/bilimbi_web/router.ex`.
4. **Move existing LiveViews** — relocate each LiveView from
   `apps/web/lib/bilimbi_web/live/` to its owning module's
   `lib/<module>/web/live/`. Add `phoenix_live_view` to each owning module's
   `deps/`. Implement each module's `Web.Router` with its route contributions.
5. **Update AGENTS.md** — amend §4 and §6 to reflect the new placement and
   descriptor key.
6. **Update tests** — Web integration tests continue to use public module
   APIs for setup; LiveView tests move with their owning module.

Steps 1–3 are infrastructure that can land before any LiveView moves. Step 4
can proceed module-by-module. Steps 5 and 6 follow.
