# ADR 0006: Module-owned web adapters and route discovery

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** faith-toh
**Scope:** Web adapter placement, route discovery, module dependency on
`phoenix_live_view`, host responsibilities, and AGENTS.md §4/§6 amendment
plan
**Last Updated:** 2026-08-21

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

The module descriptor gains a `web:` key naming a route data file:

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
  web: "priv/web_routes.exs"   # <-- new: path to route data
]
```

The value is `nil` or a path to a plain-data route file (the same pattern as
`migrations:`). The data file contains route terms as maps: path string,
LiveView or controller module atom, capability string, live session name, and
pipeline data. The module atoms are data, not compiled modules — they resolve
at runtime when Phoenix dispatches the route.

A `Web.Router` module implementing a `Router` callback (`routes/0`) remains
for runtime introspection and tests, but the compile-time path reads the data
file, not the function. §8 records why this split is necessary and how the
compile DAG works.

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

### 4. Base UI package — the compile seam

Every shipped LiveView renders `<Layouts.app>`, `<.input>`, `<.button>`,
`<.header>`. Those are **compile-time** dependencies: a LiveView in
`bilimbi_core_employee` calling `Layouts.app/1` cannot compile unless it can
see that module's beam code.

A module cannot depend on the `:web` OTP application — that is the reverse
dependency §4 forbids. Placing `Layouts` and `CoreComponents` in the host
creates an impossible compile seam: the migration plan's step 6 (relocate
LiveViews) fails on the first file because `use BilimbiWeb, :live_view` and
`<Layouts.app>` do not resolve.

The solution is a **Base-layer UI package** (`base/ui`) that owns the shared
presentation contracts every UI-bearing module needs — **and only those
contracts**:

```text
apps/base/ui/
├── mix.exs
├── bilimbi.module.exs
├── lib/
│   ├── ui.ex                       # Bilimbi.Base.UI — public facade
│   └── ui/
│       ├── components.ex           # CoreComponents (<.input>, <.button>, etc.)
│       ├── layouts.ex              # Layouts (<Layouts.app>)
│       ├── live_view.ex            # __using__ macro replacing use BilimbiWeb, :live_view
│       └── route_contract.ex       # RouteContract (@behaviour Phoenix.VerifiedRoutes)
├── test/
└── docs/
```

`base/ui` is a Base-layer module. UI-bearing modules (Core, Domain,
Extension, and Base modules with UI) depend on it through the same descriptor
graph as any other Base dependency. The dependency direction stays legal:
Base → Core → Domain → Extension.

**`base/ui` is deliberately dependency-light.** It depends only on
`phoenix_live_view`, `phoenix`, and `phoenix_html` as Hex packages, and on
`base/module_registry` (for the route manifest path). It does **not** depend
on `base/tenancy`, `base/authz`, or any other Base business module. This is
essential: if `base/ui` depended on `base/authz`, then a future Authz
administration screen — which needs `base/ui` for components — would create
`base/authz → base/ui → base/authz`, a cycle the descriptor graph rejects.
The same applies to Settings and Tenancy screens. Keeping `base/ui`
dependency-light ensures any Base module can have a UI without a cycle.

`Bilimbi.Base.UI` is a deliberate cross-cutting public name, the same class
of documented exception as `Bilimbi.Base.Repo` (ADR 0003). Its physical
ownership stays in `apps/base/ui/`; its public name does not carry `Base.UI`
in template calls — `Layouts.app` and `<.input>` work because the module
exports them and consuming LiveViews `import` or `use` the facade.

Module LiveViews use `use Bilimbi.Base.UI, :live_view` instead of
`use BilimbiWeb, :live_view`. The `__using__` macro brings in the HTML
helpers, translation functions, and shared components. Verified routes (`~p`)
verify against `Bilimbi.Base.UI.RouteContract` (in `base/ui`, implements
`@behaviour Phoenix.VerifiedRoutes`), not `BilimbiWeb.Router` — §8 records
why this is necessary for the compile DAG. Module LiveViews that need the
endpoint (for socket configuration) get it through the standard Phoenix
compile-time mechanism — the endpoint module is injected at compile time and
does not require a runtime `:web` dependency.

#### Authentication and authorization hooks stay in the host

The `on_mount` hooks (`require_authenticated`, `require_capability`,
`redirect_if_authenticated`) and `fetch_current_scope` plug stay in
`apps/web` as `BilimbiWeb.UserAuth`. They are **not** moved to `base/ui`
because:

1. **Dependency cycle.** `UserAuth`'s live scope rehydration calls Base
   Session, Tenancy, Authz **and Core Company and User**
   (`user_auth.ex:350-404`). A Base package cannot own that without depending
   on Core, which is an upward dependency violation. And if `base/ui`
   depended on `base/authz` or `base/tenancy` for the hooks, any Base module
   with a UI (Authz settings, Tenancy admin) would cycle back through
   `base/ui`.

2. **No compile-time coupling.** Module LiveViews do not need to compile
   against the auth hooks. The host router attaches `on_mount` hooks from
   route data — each route's capability string and live session name are
   data the host macro interprets, selecting the appropriate hook from
   `BilimbiWeb.UserAuth`. The LiveView module itself only needs `base/ui`
   for components and `~p` verification; the hooks run in the LiveView
   process but are loaded by the host router's `live_session` declaration,
   not by the LiveView's `use` macro.

### 5. What stays in the host

`apps/web` remains a plain umbrella child (not a composition container) and
owns only the **host shell**:

- `BilimbiWeb.Endpoint` — Phoenix endpoint, socket, LiveSocket configuration
- `BilimbiWeb.Router` — router shell with pipelines, login routes, and the
  discovered-route expansion macro
- `BilimbiWeb.UserAuth` — request-level plugs (`fetch_current_scope`,
  `require_authenticated`, `redirect_if_authenticated`), login/logout
  lifecycle, **and LiveView `on_mount` hooks**. The hooks stay in the host
  because their live scope rehydration depends on Core Company and User
  (see §4). The host router attaches the hooks from route data; module
  LiveViews do not compile against `UserAuth`.
- `assets/` — Tailwind CSS, JS hooks, esbuild pipeline, vendor code
- `config/` entries for the endpoint, pubsub, and asset pipeline

`apps/web` does **not** own any module's LiveView, controller, template, or
route. It does **not** own `Layouts` or `CoreComponents` — those move to
`base/ui`. It is the host, not a dumping ground.

### 6. Base and Core relaxation

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

### 7. `apps/web` identity

`apps/web` stays a plain umbrella child with OTP application `:web` and
namespace `BilimbiWeb`. It does **not** become a composition container with a
`bilimbi.container.exs`. It has no children to discover. Its `mix.exs` depends
on each installed module that contributes routes, declared through the same
descriptor graph — but it does not name them manually. The dependency edges
are derived from the `web:` descriptor keys at Mix resolution time, the same
way migration paths are derived from `migrations:` keys.

### 8. Compile DAG — verified routes without a cycle

Module LiveViews use `~p`, which calls `router.verified_route?/2` at compile
time via `Phoenix.VerifiedRoutes`'s `@after_verify` callback. The host router
injects module routes at compile time. If module LiveViews verify `~p` against
`BilimbiWeb.Router`, they need the router compiled first — but `:web` is a
forbidden dependency for module OTP apps, and Elixir does not do cross-project
on-demand compilation. This section records the acyclic design.

#### What does not work

Three mechanisms the previous draft of this section relied on, all identified
by reviewers on PR #124:

1. **On-demand cross-project compilation.** `Phoenix.VerifiedRoutes.__verify__/1`
   calls `route.router.verified_route?/2` in an `@after_verify` callback.
   Elixir can load an already-compiled beam or wait for a module in the same
   parallel compilation set, but it does not discover and compile source
   outside the current project's `elixirc_paths`. A module app without `:web`
   in `deps/` cannot resolve `BilimbiWeb.Router` at all.

2. **Route terms in `.app` env.** The current `:bilimbi_graph` compiler writes
   only fingerprint markers — it does not write route data. The descriptor's
   `web:` value is a provider module atom; paths and LiveView targets live in
   `routes/0`, which is Elixir code that has not compiled yet. Reading `.app`
   env gives the host no route terms to expand.

3. **Workspace fingerprint file for `@external_resource`.** The graph compiler
   writes per-app marker files with changing names. `apps/web` does not run
   `:bilimbi_graph`, so there is no stable fingerprint file for the host
   router to declare as `@external_resource`.

#### The acyclic design: route manifest + RouteContract module

The design separates route **data** from route **code**, and route
**verification** from route **serving**:

```
                    bilimbi.module.exs files
                    (route data as plain terms)
                            │
                     :bilimbi_graph compiler
                     (runs before Elixir compilers)
                            │
                     ┌──────┴──────┐
                     ▼              ▼
              route manifest    route manifest
              (generated)       (generated)
                     │              │
         ┌───────────┘              └──────────┐
         ▼                                     ▼
  Bilimbi.Base.UI.RouteContract        BilimbiWeb.Router
  (implements verified_route?/2)       (splices routes via macros)
  compiles in base/ui                  compiles in :web
  (Base layer — first)                 (depends on module apps)
         │
         ▼
  module LiveViews
  (~p verifies against RouteContract)
  compile in module apps
  (depend on base/ui, never :web)
```

#### Route data: plain terms in descriptor, not function calls

The `web:` descriptor key changes from a module atom to a **path** to a route
data file (the same pattern as `migrations:`):

```elixir
[
  id: "core/user",
  ...
  web: "priv/web_routes.exs"   # path to plain route data
]
```

The data file contains route terms as plain Elixir data — paths as strings,
LiveView module names as atoms, capabilities as strings:

```elixir
# apps/core/user/priv/web_routes.exs
[
  %{path: "/users", live: Bilimbi.Core.User.Web.IndexLive,
    capability: "admin.user.list", session: :auth},
  %{path: "/users/new", live: Bilimbi.Core.User.Web.FormLive,
    capability: "admin.user.create", session: :auth}
]
```

The module atoms are data, not compiled modules. They resolve at runtime when
Phoenix dispatches the route. The `Web.Router` module and `routes/0` callback
remain for runtime introspection and tests, but the compile-time path reads
the data file, not the function.

#### Route manifest: one generated file

The `:bilimbi_graph` compiler already reads every `bilimbi.module.exs` from
disk and resolves the full workspace graph. It gains one responsibility: when
a descriptor has a `web:` path, read that data file and collect its route
terms. After resolving all modules, it writes a single **route manifest** to a
stable workspace-level path (e.g. `_build/<env>/bilimbi_routes.exs`).

The manifest is a plain Elixir term: a list of route maps in resolved module
order, plus host routes (login, session) contributed by `apps/web`'s own
declaration. It is written before any Elixir module compiles, because
`:bilimbi_graph` runs as the first compiler in every module's `mix.exs`.

#### RouteContract: `~p` verification in the Base layer

`Bilimbi.Base.UI.RouteContract` is a module in `base/ui` that:

1. Declares `@external_resource` on the route manifest file.
2. Reads the manifest at compile time into a module attribute.
3. Implements `@behaviour Phoenix.VerifiedRoutes` with `verified_route?/2`,
   returning `true` when the path matches a route in the manifest.

The `__using__` macro in `Bilimbi.Base.UI` configures
`use Phoenix.VerifiedRoutes, router: Bilimbi.Base.UI.RouteContract` — not
`BilimbiWeb.Router`. Module LiveViews verify `~p` against `RouteContract`,
which is in `base/ui` (Base layer, compiles before any Core/Domain module).
No module OTP app needs `:web` in `deps/`.

Since `base/ui` compiles before all UI-bearing module apps (they depend on
it), and the `:bilimbi_graph` compiler runs in `base/ui` before its Elixir
compilers, the manifest is already written when `RouteContract` compiles.

#### Host router: reads the same manifest

`BilimbiWeb.Router` reads the route manifest at compile time and splices
routes into Phoenix Router macros. It declares `@external_resource` on the
same manifest file. Since `:web` depends on module apps (Mix deps), they
compile first — the `:bilimbi_graph` compiler in those apps (and in `base/ui`)
has already written the manifest. The host router also contributes its own
routes (login, session) to the manifest through its own descriptor or a
host-side data file.

#### Invalidation contract

The route manifest is the **one stable generated invalidation artifact**. When
the workspace graph changes (a module is mounted, unmounted, or its `web:`
data file changes), the `:bilimbi_graph` compiler rewrites the manifest. Both
`RouteContract` and `BilimbiWeb.Router` declare `@external_resource` on it, so
Mix detects the stale file and recompiles both. The manifest path is stable
(not a changing filename), so `@external_resource` works.

For `apps/web` which does not run `:bilimbi_graph`: the manifest is written by
the graph compiler running in `base/ui` and in module apps, all of which
compile before `:web` (they are Mix dependencies). The `@external_resource`
declaration in `BilimbiWeb.Router` points at the manifest's stable path; Mix
checks it on every compile.

#### What this rules out

- **Calling `ModuleRegistry.installed_modules!()` at compile time** — it is a
  runtime API. The graph compiler reads descriptors from disk instead.
- **Calling `Web.Router.routes/0` at compile time** — would require the module
  to compile before the router or `RouteContract`, recreating the cycle. Route
  data is plain data in a file, not a function call.
- **Module LiveViews declaring `:web` in `deps/`** — that is the reverse
  dependency §4 forbids. `RouteContract` in `base/ui` handles `~p` without it.
- **On-demand cross-project compilation** — Elixir does not support it.
  `RouteContract` is a same-project dependency (`base/ui`), not a cross-project
  one.

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

## Amendment: test ownership and execution

Module-owned web integration tests live in `web_test/` inside the same module
directory as the adapter they exercise. They are not part of that module's
standalone `mix test`: the Web Mix project discovers `web_test/` directories
from installed descriptors with a non-null `web:` path and executes them with
the real endpoint, discovered router, authentication hooks, and `ConnCase`.

This distinction preserves both boundaries:

- source ownership and install/remove composition remain directory-local;
- a Base/Core/Domain/Extension module does not acquire a reverse dependency on
  the Web host merely to compile endpoint tests.

Tests for the endpoint, router shell, authentication lifecycle, host-only
routes, and cross-module shell behavior remain in `apps/web/test`. Public API
and adapter tests that do not need the host remain in the owning module's
ordinary `test/` directory. A test's physical owner follows the production
surface it primarily verifies; its execution project follows the runtime
dependencies it needs.

## Interim placement rule for in-flight UI

Before the `web:` descriptor key and host router macro land, UI-bearing
modules that are building screens now must:

1. **Put LiveViews in `lib/<module>/web/`** inside the owning module now.
2. **Do not register routes in the host `router.ex`** — that recreates the
   central child list the ADR removes.
3. **Do not invent a per-screen shim** or temporary route-registration hack.
   Coordinate route wiring through the `web:` descriptor key when it lands.

This rule applies to all in-flight UI issues (#97–#103, #119, #102, #97).
Screens can be built, tested, and reviewed in the owning module; route
wiring is the last step, gated on the descriptor infrastructure.

## AGENTS.md amendment

Before the 2026-08-21 amendment, AGENTS.md §4 recommended
`apps/web/lib/bilimbi_web/core/...` and `BilimbiWeb.Core.*Live`, while §9
recommended `BilimbiWeb.Core.CompanyLive.Index`. Those rules became stale when
this ADR was accepted. The completed amendment:

- §4: replace the recommended placement with
  `apps/<layer>/<module>/lib/<module>/web/` and namespace
  `Bilimbi.<Layer>.<Module>.Web`.
- §6: add the optional `web/` sub-directory and the `web:` descriptor key to
  the module directory contents list.
- §9: replace `BilimbiWeb.Core.CompanyLive.Index` with
  `Bilimbi.Core.Company.Web.IndexLive`.
- §10: note that `use Bilimbi.Base.UI, :live_view` replaces
  `use BilimbiWeb, :live_view` for module-owned LiveViews.

The amendment is migration step 5 and now reflects the implemented placement.

## Migration plan

This ADR records the decision. The migration is separate work, sequenced as:

1. **Descriptor schema** — add `web:` key to `bilimbi.module.exs` validation
   in Base ModuleRegistry. The value is `nil` or a path to a route data file.
   All existing descriptors gain `web: nil`.
2. **Base UI package** — create `apps/base/ui/` with `Layouts`,
   `CoreComponents`, the `__using__` macro, and `RouteContract` moved from
   `apps/web`. Auth hooks stay in `BilimbiWeb.UserAuth` (host). Add `base/ui`
   to the Base container and descriptor graph.
3. **Route manifest + RouteContract** — extend `:bilimbi_graph` to read route
   data files and write a consolidated route manifest. Implement
   `Bilimbi.Base.UI.RouteContract` (`@behaviour Phoenix.VerifiedRoutes`) in
   `base/ui` reading the manifest. Define the `Router` callback in Base
   ModuleRegistry for runtime introspection. See §8 for the full compile DAG.
4. **Host router macro** — implement the discovered-route expansion macro in
   `apps/web/lib/bilimbi_web/router.ex`. Reads the same route manifest and
   splices routes via macros. Declares `@external_resource` on the manifest
   for invalidation. See §8.
5. **Amend AGENTS.md** — update §4, §6, §9, and §10 to reflect the new
   placement, descriptor key, and `use Bilimbi.Base.UI, :live_view`. This
   must happen before step 6.
6. **Move existing LiveViews** — relocate each LiveView from
   `apps/web/lib/bilimbi_web/live/` to its owning module's
   `lib/<module>/web/live/`. Add `phoenix_live_view` and `base/ui` to each
   owning module's `deps/`. Implement each module's `Web.Router` with its
   route contributions.
7. **Update tests** — Web integration tests continue to use public module
   APIs for setup. Module-owned LiveView integration tests move to the owning
   module's `web_test/` directory and are discovered by the Web Mix project;
   host-owned integration tests remain in `apps/web/test`. This is the
   cross-module test-support rule: tests execute with the real host without a
   production or test dependency from the module back to Web.

Steps 1–4 are infrastructure that can land before any LiveView moves. Step 5
amends AGENTS.md. Step 6 can proceed module-by-module. Step 7 follows each
module move.
