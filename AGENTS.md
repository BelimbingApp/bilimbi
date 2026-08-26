# Bilimbi Agent and Architect Guidelines

Bilimbi is the Phoenix and Elixir implementation of the Belimbing application
platform. These rules are part of the product's engineering system. Follow
them when adding or changing code, tests, migrations, documentation, assets, or
configuration.

Read this file and `DESIGN.md` before making changes. The source Belimbing
project is the reference for business meaning and schema compatibility, not a
template for copying Laravel implementation details.

Compatibility is a one-direction replacement contract. Bilimbi must be able
to adopt an existing Belimbing database and replace the Belimbing application;
Belimbing is not required to consume Bilimbi source, UI, routes, migrations,
or a database after Bilimbi-only evolution. Preserve durable business and data
contracts deliberately. Do not retain Laravel framework details, legacy UI,
internal route names, or other implementation artifacts merely to make a
Bilimbi application reversible to Belimbing. ADR 0002 is authoritative for
schema baseline and adoption mechanics.

## 1. Project context

Bilimbi is built with:

- Elixir 1.20.3 on Erlang/OTP 28.5, pinned in `.mise.toml`;
- Phoenix 1.8.10 and Phoenix LiveView 1.2.9;
- Ecto 3.14.1, Ecto SQL 3.14.0, Postgrex 0.22.4, and PostgreSQL 18;
- HEEx, Phoenix components, Tailwind CSS 4.3.0, and esbuild 0.25.4;
- ExUnit and `Phoenix.LiveViewTest`;
- Req 0.7.2 for Web's Swoosh API client and declared outbound HTTP;
- Bandit 1.12.5 as the HTTP server;
- Swoosh 1.27.0 for email where email is required.

These versions record the current engineering baseline; `.mise.toml`,
`mix.lock`, and binary versions in `config/config.exs` remain authoritative.
Use the conventions and features of these versions rather than habits from
older Elixir or Phoenix releases. Check for the latest stable compatible
releases at milestone boundaries and update this list with the pins. Keep
`mix.lock` committed. Do not use prerelease dependencies unless the task
explicitly requires one and the decision is documented.

The repository uses the composed Mix topology defined by
`docs/architecture/decisions/0003-physical-deep-module-packages.md`. Base,
Core, and Web are direct umbrella children below `apps/`. Base and Core are
composition applications; their declared deep modules are nested local Mix
path packages discovered from `bilimbi.module.exs`. Future Domain and Extension
composition applications use the same discovery contract.

`docs/architecture/0010_composition-model.md` is the normative source of truth
for composition. Read it before changing Platform, Domain, Extension,
dependency, or nested-repository rules; do not restate those rules here.

`Base` and `Core` remain ownership boundaries rather than superclass
hierarchies. OTP application boundaries support their dependency, supervision,
and lifecycle contracts; they do not replace deep Module APIs.

## 2. Current scope

The initial Bilimbi implementation contains the Platform Baseline and its web
host. Base Session, Base Settings, Base Tenancy, Base Authz, Base Audit, Base
Queue, Base Locale, Base Principal Directory, Core Company, Core Geonames, Core
Address, Core Employee, and Core User are active foundation slices:

```text
apps/base/database/
apps/base/session/
apps/base/settings/
apps/base/tenancy/
apps/base/authz/
apps/base/audit/
apps/base/queue/
apps/base/locale/
apps/base/principal_directory/
apps/core/company/
apps/core/geonames/
apps/core/address/
apps/core/employee/
apps/core/user/
apps/core/compatibility/
apps/web/
```

The current production scope contains no optional Domain or Extension. Add
production capabilities only through the composition rollout and a real
business requirement. Disposable repositories used by the approved composition
proof are allowed, must remain outside the Platform Git history, and must be
removed when the proof ends.

The initial goal is compatibility with Belimbing's existing PostgreSQL schema.
Bilimbi maps that schema accurately and owns Ecto migrations that can create a
fresh compatible schema. Existing Belimbing databases use the explicit
verify-and-adopt contract in
`docs/architecture/decisions/0002-compatible-schema-baselines.md`.

## 3. Development philosophy

Build production-grade foundations from the beginning. An initialization phase
allows design freedom, not shortcuts.

### Core principles

- **Low entropy:** Fix small inconsistencies when encountered. For larger
  corrections, document the plan rather than silently carrying drift.
- **Strategic programming:** Spend deliberate design effort on boundaries and
  contracts when a real future variation justifies it. Do not build speculative
  frameworks.
- **Progressive evolution:** Build the best design current knowledge supports.
  Refactor, simplify, delete, relocate, rename, or improve abstractions as
  understanding improves.
- **Deep modules:** Hide difficult implementation behind a small, stable API.
  Do not leak schemas, queries, table names, or workflow internals across
  module boundaries.
- **Exceptional experience:** UI quality is architecture. Every interface must
  follow `DESIGN.md`.
- **Information architecture:** Organize UI by user workflow and code by
  ownership/change boundary. Bridge differences explicitly.
- **Honesty:** Names, persisted values, APIs, documentation, and UI copy must
  be truthful and grounded in code and data.
- **Opinionated defaults:** Prefer one good blessed path over option sprawl.
  Business modules remain adaptable; the shared shell and platform conventions
  should be clear.

## 4. Application ownership and dependency direction

### Base

`Bilimbi.Base` owns framework infrastructure and cross-cutting platform
mechanisms: database access conventions, authentication primitives,
authorization, tenancy context, settings, audit infrastructure, telemetry, and
shared contracts.

Base must not depend on Core business implementations.

### Core

`Bilimbi.Core` is the required enterprise domain. It owns foundational business
modules such as User, Company, Employee, Address, and Geonames.

Core may depend on Base. Core modules should collaborate through public APIs,
behaviours, or explicit events—not another module's private queries or tables.

[ADR 0007](docs/architecture/decisions/0007-core-user-administration-integration-read.md)
records one conditional exception for the future required
`core/user_administration` integration read. The exception does not apply
until that package lands with ADR 0007's exact allowlist; consumed-relation
version, type, and nullability assertions; AST/source-position boundary
guards; independently reviewed architecture/security containment; and a
focused query-count proof that filtered count, ordered page, archived Company
facts, and bounded page-Role aggregation execute as one parameterized
PostgreSQL statement under one snapshot. Only its private
`Bilimbi.Core.UserAdministration.Query` may then perform that read. This is not
precedent for any other sibling-private-table access.

### Future Domains and Extensions

Follow the normative roles, dependency rules, and placement tests in
`docs/architecture/0010_composition-model.md`.

### Web

`BilimbiWeb` is the Phoenix host. It owns the endpoint, router shell,
authentication hooks, host-only routes, assets, and host integration support.
Module LiveViews, controllers, colocated templates, and route contributions
belong to the Base/Core/Domain/Extension module whose workflow they adapt, as
decided by ADR 0006. Shared presentation primitives belong to Base UI.

Recommended placement:

```text
apps/core/company/lib/company.ex
apps/core/company/lib/company/schema.ex
apps/core/company/lib/company/queries.ex
apps/core/company/lib/company/web/index_live.ex
apps/core/company/lib/company/web/index_live.html.heex
apps/core/company/priv/repo/migrations/
apps/core/company/test/
apps/core/company/web_test/company_live_test.exs
```

The domain API is the deep module. `Bilimbi.Core.Company.Web.IndexLive` is its
UI adapter. Module-owned endpoint/router integration tests live in
`web_test/`; the Web Mix project discovers and runs them so they can use the
real host without creating a forbidden module-to-Web dependency. Each such
directory carries a `test_helper.exs` that requires the Web host's shared test
helper; discovery fails closed when that bridge or the owner's non-null `web:`
descriptor is missing.

## 5. Stable identities and schema compatibility

Belimbing is the reference for durable business meaning and the PostgreSQL
schema that Bilimbi must initially adopt. It is not permanent authority over
Bilimbi-only evolution after that boundary. Compatibility includes more than
table names:

- column names and nullability;
- primary and foreign keys;
- PostgreSQL types and sequences;
- indexes, unique constraints, partial indexes, and triggers;
- JSON shapes and status values;
- timestamp precision and timezone semantics;
- soft-delete behaviour;
- tenant, company, user, and employee relationships;
- polymorphic records and durable identifiers.

Use stable logical IDs such as `core/company` in documentation and future
registries. Do not derive persisted identity from a current filesystem path or
Elixir module name.

### Existing database rules

- Treat Belimbing's schema as canonical while defining and adopting the
  compatible baseline. Evolve beyond it through explicit Bilimbi-only
  migrations; reverse execution by Belimbing is not a requirement.
- Do not invent a replacement table merely because its Ecto schema would be
  cleaner.
- Do not rename existing tables or columns without an explicit compatibility
  migration decision.
- Map existing sources explicitly in Ecto when needed with `schema/2`,
  `@primary_key`, `@foreign_key_type`, or field `source:` options.
- Model Laravel polymorphic columns explicitly; Ecto associations do not
  automatically reproduce Laravel morph relationships.
- Treat soft deletes as an explicit query and context policy. Ecto does not
  provide an automatic global soft-delete scope.
- Map `json`/`jsonb`, UUIDs, bigint IDs, decimals, and timestamps according to
  the actual PostgreSQL column, not a guessed Elixir type.
- Preserve PostgreSQL sequence correctness when inserting into existing tables.
- Treat PHP serialized values and PHP class names in durable payloads as a
  compatibility concern. Do not deserialize them as ordinary Elixir terms.

Bilimbi records migration versions in `bilimbi_schema_migrations`; never read
from, write to, rename, or repurpose Laravel's `migrations` table. Migration
files stay with their owner:

```text
apps/base/session/priv/repo/migrations/
apps/base/settings/priv/repo/migrations/
apps/base/tenancy/priv/repo/migrations/
apps/base/authz/priv/repo/migrations/
apps/base/audit/priv/repo/migrations/
apps/base/queue/priv/repo/migrations/
apps/core/company/priv/repo/migrations/
apps/core/geonames/priv/repo/migrations/
apps/core/address/priv/repo/migrations/
apps/core/employee/priv/repo/migrations/
apps/core/user/priv/repo/migrations/
```

Run the required baseline through `mix bilimbi.migrate`, which discovers every
installed descriptor that contributes migrations and merges those paths with
strict Base → Core → Domain → Extension ordering. Do not use broad `create_if_not_exists`
operations to make a migration appear safe on an existing database. Verify an
existing Belimbing database with `mix bilimbi.schema.verify`, then baseline it
with `mix bilimbi.schema.adopt`; adoption must refuse structural drift.

Base Session owns the compatible durable `sessions` table without depending on
Core User or Web. Treat `payload` as opaque compatibility data: Base may store,
fetch, list metadata, terminate, and prune sessions, but it must not interpret
Laravel payloads or attach authentication semantics. Operational listings must
not expose payloads, and terminating another session must protect the caller's
current session ID.

Core User owns account credentials and lifecycle. New hashes are Argon2id;
existing Laravel Argon2 hashes remain valid and successful legacy `$2y$`
bcrypt logins are upgraded. Never accept a caller-supplied password hash or
expose credential/reset-token schemas. Core provides neutral reset and signed
verification primitives; Web owns routes, IP/login throttling, delivery,
cookies, and the authenticated Session adapter. Public self-registration stays
disabled unless a future architecture decision explicitly changes that policy.

The explicit-tenancy compatibility source is Belimbing merge commit
`e70b4d33c0b10790e681f4c2b5095d85a53bc918`. Resolve the platform operator only
through `tenants.is_platform_operator`, and resolve a tenant's primary company
only through `tenant_primary_companies`. Numeric ID 1 has no runtime meaning;
it is bounded historical migration input only.

`companies.tenant_id` is non-null and has no default. Every Company write must
receive or derive an explicit, validated tenant. Do not infer a primary company
from row age. Base Tenancy owns operator resolution and must not query Core
Company tables; Core Company owns primary-company resolution, assignment,
transfer, and provisioning.

Core Geonames owns the canonical country, first-level administrative division,
postcode, and city lookup tables. Core Address preserves the canonical
non-null `addresses.tenant_id`, named index, restricted tenant foreign key, and
its two Geonames normalization foreign keys. Fresh installation creates empty
Geonames tables; reference-data import remains separately owned seeding work.
Base Authz owns capability vocabulary, roles, direct grants, evaluation, and
decision logs. Capability definitions come from installed module
contributions; there is no capabilities table, and unknown keys fail closed.
Custom roles require a live owning company; system roles are company-less.
Core Company owns the restricted `base_authz_roles.company_id` foreign key and
the exact `is_system = (company_id IS NULL)` check. Reconcile configured system
roles only through the explicit production-seed path, never at application
boot, and never delete principal grants as part of reconciliation. AI provider
configuration lookup requires an owning company ID and must not resolve
credentials from tenant identity alone.

## 6. Deep-module design

The physical module directory is the ownership, packaging, and future nested-
Git boundary. For example, the complete Base Tenancy module boundary is
`apps/base/tenancy/`. It must contain its own `mix.exs`, `lib/`, tests,
documentation, `bilimbi.module.exs` descriptor, and any owned migrations or
assets.

Inside that boundary, `lib/` starts at the module. Do not repeat the platform
and layer path below `lib/`:

```text
apps/base/tenancy/
├── mix.exs
├── bilimbi.module.exs
├── lib/
│   ├── tenancy.ex
│   └── tenancy/
│       └── web/          # optional module-owned Phoenix adapters
├── priv/repo/migrations/
├── test/
├── web_test/             # optional real-host integration tests
└── docs/
```

`lib/tenancy.ex` still declares `Bilimbi.Base.Tenancy`; filesystem flattening
does not shorten or weaken the globally qualified Elixir namespace. The public
facade, private implementation, migrations, tests, docs, descriptor, and
optional assets must not be split across the parent composition application.

Composition layout and selection follow 0010. Each container `mix.exs` calls
generic discovery and names no child module; each immediate child has a valid
`bilimbi.module.exs` and descriptor-derived `mix.exs`.

The module descriptor is the sole declaration of its stable module ID, layer,
OTP application ID, namespace, module dependencies, required/optional state,
migration path, optional compatibility contract, route-data path, and optional
contribution provider. Every descriptor carries `web`; use `nil` when the
module contributes no routes, otherwise point it at the module-owned plain-data
route file. Every descriptor also carries `contribution_provider`; use `nil`
when the module contributes nothing. A non-nil provider implements the
ModuleRegistry behavior and returns immutable plain terms below only
`:settings`, `:authz`, `:menu`, `:dashboard`, `:principal_directory`, and
`:schedule`, as decided by ADR 0004, ADR 0009, ADR 0011, and ADR 0012. Its
`mix.exs` derives local module path dependencies and application metadata from
that descriptor; do not repeat module dependency names manually.

A descriptor with a non-null `migrations` path must also declare
`migration_dispositions`, mapping every owned migration filename version
exactly once to `:compatible_baseline` or `:bilimbi_only`. A descriptor with
`migrations: nil` omits that field. Compatible baselines may be ledger-adopted
only after verification; Bilimbi-only migrations always execute. There is no
default disposition. Adding, removing, or reclassifying a migration changes
the workspace graph and must fail discovery until the descriptor is exact.

Discovery must fail during dependency resolution for a malformed or missing
descriptor, duplicate stable ID, duplicate OTP application ID, missing
dependency, dependency cycle, layer/container mismatch, or forbidden upward
dependency. Valid modules are ordered dependency-first and then by stable
module ID; layer order is Base → Core → Domain → Extension.

Base ModuleRegistry owns the source-loadable Mix helpers under its own `mix/`
directory. That directory must remain in the package formatter. Mix records the
validated resolved position and workspace-graph fingerprint in each OTP
application's descriptor metadata. Every module project includes the shared
`:bilimbi_graph` compiler before Mix's standard compilers; when composition
or an owned migration file changes, it refreshes each package's application metadata. Runtime consumers
verify one graph fingerprint, use the approved positions, and must not
implement a second dependency graph algorithm.

The shared database module owns one Repo. Compatibility discovers migration
paths from the approved composition metadata and executes them through the
single `bilimbi_schema_migrations` ledger; it must not hard-code Tenancy,
Company, Address, or any future contributor.

A descriptor's schema contract owns both structural table specifications and
any live-data invariants understood by that module. Compatibility iterates
installed contracts generically; never place tenant-, company-, address-, or
future module-specific SQL in the coordinator. Migration modules must use the
owning descriptor namespace.

`Bilimbi.Base.Repo` is the deliberate platform-wide public name for the one
shared Repo even though its physical owner and primary package namespace are
Base Database. Do not generalize this documented Ecto convention into
permission for other modules to escape their declared namespaces.

The Base and Core composition applications contain no `lib/`, `priv/`, or
`test/` directory. Do not place schemas, services, application callbacks,
mailers, namespace marker modules, migrations, seeds, runtime resources,
fixtures, or tests directly under `apps/base` or `apps/core`; create or use the
owning child module instead. The container Mix projects delegate `mix test` to
each child package so test helpers and support compile inside their owner.
External library dependencies belong to the module that uses them, never to a
composition-only container for possible future use.

Cross-module tests may load lower-layer test support from declared module
dependencies, but table DDL and fixtures remain defined once by their owning
module. Base Database owns the shared SQL sandbox case. Web tests set up
business identity through public module APIs rather than writing domain tables.

Generate a migration from the owning module root or pass its explicit
`--migrations-path`. Confirm the generated file remains below that module's
`priv/repo/migrations`; never generate it into the Base or Core composition
application and move ownership later by convention.

Each module should provide a small public API around its business capability.
Prefer functions such as:

```elixir
Bilimbi.Core.Company.list_companies(scope)
Bilimbi.Core.Company.get_company(scope, id)
Bilimbi.Core.Company.create_company(scope, attrs)
```

Keep schemas, queries, changesets, database locking, and internal workflows
behind the module API. A caller should not need to know which table or query
implements the operation.

Use a behaviour when there is a real stable seam or more than one meaningful
implementation. Use a protocol when dispatch genuinely depends on the data
type. Do not introduce behaviours, protocols, or macros merely to imitate PHP
interfaces or inheritance.

Events publish facts. They should not embed consumer-specific implementation
codes. Synchronous collaboration should use a documented API or behaviour.
Optional future integrations must not make a Core module fail to boot.

## 7. Elixir conventions

- Use one primary module per file. Keep related nested modules in separate
  files unless the code is a deliberately tiny private helper.
- Prefer pattern matching, guards, `case`, `cond`, and `with` over deeply
  nested conditionals.
- Remember that data is immutable. Rebind the result of `if`, `case`, `cond`,
  and `with` when the result is needed afterward.
- Elixir lists do not support index access. Use pattern matching, `Enum.at/2`,
  or the appropriate `List` function.
- Do not use map access syntax on ordinary structs. Access fields directly or
  use the struct's documented API. For changesets, use
  `Ecto.Changeset.get_field/2`.
- Predicate functions end in `?`; reserve `is_` names for guards.
- Never call `String.to_atom/1` on user input.
- Prefer standard library date/time types and functions. Do not add a package
  for a problem the standard library already solves.
- Use `Task.async_stream/3` for concurrent collection work with back-pressure;
  use `timeout: :infinity` when the operation is intentionally unbounded.
- Name OTP processes in child specifications, for example
  `{DynamicSupervisor, name: Bilimbi.SomeSupervisor}`.
- Prefer plain modules and data over macros. Add macros only when they remove a
  proven, repeated source of complexity.

## 8. Dependencies and HTTP

When a module needs outbound HTTP, add `Req` to that owning module and use it
for HTTP requests. Web currently owns Req for its configured Swoosh API client.
Do not place Req in a composition container merely because a future child may
need it, and do not add or use `HTTPoison`, `Tesla`, or `:httpc`.

Do not add dependencies casually. Before adding one, check whether the
standard library, Phoenix, Ecto, or an existing dependency already provides
the capability. Record a meaningful reason in the change when a new dependency
is necessary.

Keep dependency versions current and compatible, update `mix.lock`, compile,
format, and test after updates.

## 9. Phoenix application conventions

- Use verified routes and the `~p` sigil for internal paths.
- Router scopes already provide their configured module alias. Do not add
  duplicate route aliases.
- Do not use deprecated `live_redirect` or `live_patch`. Use `<.link
  navigate={...}>`, `<.link patch={...}>`, `push_navigate/2`, and
  `push_patch/2`.
- Module-owned LiveViews use a `Live` suffix, such as
  `Bilimbi.Core.Company.Web.IndexLive`.
- Keep business rules out of controllers and LiveViews. They coordinate
  request state and call domain APIs.
- Use the existing `Bilimbi.Base.UI.Layouts` and
  `Bilimbi.Base.UI.Components` instead of creating parallel shared
  foundations.

### Layouts and authenticated routes

Every LiveView template begins with the application layout:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  ...
</Layouts.app>
```

Pass `current_scope` whenever the route is authenticated. If an assign is
missing, fix the route's `live_session` and scope propagation rather than
adding a fallback value in the template.

The `<.flash_group>` component belongs only in `Bilimbi.Base.UI.Layouts`. Do
not call or recreate it elsewhere.

## 10. HEEx, forms, and components

- Module-owned LiveViews use `Bilimbi.Base.UI, :live_view`; they never use or
  depend on `BilimbiWeb, :live_view`.
- Use `~H` or `.html.heex`; never use old `~E` templates.
- Use the imported `<.form>` and `<.input>` components.
- Assign forms with `to_form/1` or `to_form/2`; templates consume
  `@form[:field]`, never a raw changeset.
- Give every important form, button, table, and interaction a unique DOM ID.
- Use HEEx `[...]` class lists for multiple or conditional classes.
- Use `{...}` interpolation in attributes and tag bodies; use `<%= ... %>` for
  block constructs such as `if`, `case`, `cond`, and `for`.
- Use `<%!-- ... --%>` for HEEx comments.
- Use `<.icon>` for icons.
- Do not use `Enum.each/2` to generate template content; use a HEEx `for`.
- Prefer function components for reusable markup. Avoid LiveComponents unless
  they need their own state and event lifecycle.

Templates may be colocated with their owning LiveView through `embed_templates`
or a nearby `.html.heex` file. Colocation does not move the view into the
domain namespace or allow the view to bypass the domain API.

## 11. LiveView state and collections

LiveViews are processes with server-side state. Keep state minimal, explicit,
and recoverable. The browser is not the source of truth for authorization or
business invariants.

Use streams for collections that can grow or change over time:

```elixir
stream(socket, :companies, companies)
```

The template must provide a DOM ID and consume the stream:

```heex
<div id="companies" phx-update="stream">
  <div :for={{id, company} <- @streams.companies} id={id}>
    {company.name}
  </div>
</div>
```

Streams are not enumerable and do not provide counts. Track counts separately,
and refetch plus `reset: true` when filtering or refreshing a collection.
Re-stream items when an assign changes the content of a streamed item.

Do not use deprecated `phx-update="append"` or `phx-update="prepend"`.

## 12. JavaScript and CSS

- Use Tailwind CSS and focused custom CSS for the design in `DESIGN.md`.
- **UI consistency:** Reuse Base UI before local markup. Field, search, and
  filter controls are compact (`rounded-md`, `py-1.5`) and use `brand-strong`
  focus borders and rings; compact pagination and icon controls are
  `rounded-md`; surfaces are `rounded-xl`. Operational lists default to 25
  rows and only offer 25, 50, 100, or 300; their sortable headers expose
  `aria-sort`, and page, search, filters, sort, and page size stay in URL
  state. Use `<.datetime>` for timestamps and `<.icon>` for all icons (put
  product-only SVGs in `Bilimbi.Base.UI.IconRegistry`). Primary actions use
  `<.button variant="primary">` with deep olive base (`bg-action`, `lime-950`
  light / `lime-600` dark), high-contrast text (`text-action-ink`, `lime-50`
  light / `lime-950` dark), and a brighter lime hover
  (`hover:bg-action-hover`, `lime-600` light / `lime-500` dark). Lime `brand`
  is reserved for orientation and selection, never an action or status. Async actions
  must show in-flight state, reject duplicate work, and truthfully report the data
  outcome and recovery.
- **Compact actions:** Use `<.icon_button>` for familiar repeated secondary
  actions in tables and toolbars. Inline icon controls are `size-5`; table and
  toolbar icon controls are `size-7`. Every icon-only action has a truthful
  accessible label and title. Keep primary and unfamiliar actions as text.
  Destructive actions use calm danger text with quiet hover feedback, not a
  solid danger fill.
- **Data tables & inline editing:** Tables use compact density (`py-0.5` row
  cells, `py-1.5` header cells, `px-2` cell horizontal padding,
  `bg-surface-sunken` header background, proper case
  `text-xs font-semibold text-muted` headers,
  tabular numbers for numeric/code/date columns). Search filters use an open
  toolbar with an `mb-2` gap above the table card; do not wrap the toolbar in
  another card. Inline editing uses `<.inline_edit>` with
  subtle hover pencil icon, click/focus activation, Enter/blur save, Escape cancel, and
  LiveView stream patching (`stream_insert/3`). Pagination uses compact rows-per-page select
  (`w-14`, `h-7`, `pl-2 pr-4`) and accent focus rings (`focus:border-brand-strong focus:ring-brand-strong/30`).
- Maintain the Tailwind v4 `source(none)` and `@source` imports in
  `assets/css/app.css`.
- The platform uses `Instrument Sans` globally via `--font-sans` in `@theme`.
- **Navigation & menu design:** Navigation items use `Instrument Sans` with compact
  styling (`font-weight: 350`, `0.8125rem`/13px, `line-height: 1.25rem`). Default
  link text is `text-link` (`stone-700` light / `stone-300` dark), hover is
  `text-ink`, and pinned headers and grips are `text-muted` (`stone-600` light /
  `stone-400` dark). Active navigation uses `bg-surface text-brand-strong`
  without bolding or spine borders. Parent branches of active items ascend with
  `text-brand-strong`. Chevrons use triangle characters `&#x2BC8;` (`⯈`) and `&#x2BC6;`
  (`⯆`) with figure space indentation for leaf items. Menu items and submenus are sorted
  alphabetically ascending (`ASC`). Pinned items sit in `bg-brand-surface`.
- Do not use `@apply` in raw CSS.
- Build the design system with hand-written Tailwind-based components. Do not
  make daisyUI or another component library the product design system.
- The `@theme` block in `apps/web/assets/css/app.css` is the only place a color
  is chosen. Components and templates use the semantic roles it declares —
  `canvas`, `surface`, `surface-sunken`, `surface-muted`, `surface-sidebar`,
  `brand-surface`, `line`, `ink`, `link`, `muted`, `action`, `brand`, `brand-strong`,
  `success`, `warning`, `danger` — as ordinary Tailwind utilities such as
  `bg-surface`, `text-ink-muted`, `text-link`, `border-line`, `text-danger`.
- A raw palette class such as `stone-200` or `emerald-600` outside that
  `@theme` block is a defect. It is greppable, so treat it as one:

  ```bash
  grep -rnE '\b(bg|text|border|ring|shadow|divide|accent)-(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-[0-9]+' apps/*/lib
  ```

- Add a semantic role when a workflow genuinely needs one, not when a single
  screen wants a shade. Roles carry meaning; `brand` is identity and never
  reports status.
- `phx.gen.live`, `phx.gen.html`, and `phx.gen.schema` output must use the
  shared `Bilimbi.Base.UI.Components`; do not introduce a parallel
  `BilimbiWeb.CoreComponents` layer.
  `phx.gen.auth` is the exception: its templates hardcode daisyUI classes
  (`btn btn-primary`, `btn-soft`, `alert alert-outline`, `alert alert-info`).
  Convert those to semantic roles in the same change that runs the generator.
- Do not add external script or stylesheet URLs to layouts. Import vendor code
  through the supported asset bundles.
- Do not write raw inline `<script>` tags in HEEx.
- Use colocated hooks with `:type={Phoenix.LiveView.ColocatedHook}` for small
  template-local behaviour; hook names start with `.`.
- External hooks live in `assets/js/`, are registered with `LiveSocket`, and
  have a unique DOM ID plus `phx-update="ignore"` when they manage their own
  DOM.
- Use `push_event/3` for server-to-hook events and rebind the returned socket.
- Keep client-side behaviour small. Business rules and authorization remain on
  the server.

## 13. Ecto conventions

- Use `Ecto.Schema` for persistence mapping and context modules for public
  operations.
- Use `Ecto.Changeset` for casts and validation.
- Never cast programmatically assigned fields such as `user_id`, `tenant_id`,
  or actor IDs from untrusted form parameters.
- Use `Ecto.Changeset.get_field/2` for changeset values.
- Preload associations before accessing them in templates.
- Import `Ecto.Query` explicitly where query macros are used.
- Use explicit query scopes for tenant and soft-delete filtering.
- **A module API that reads or writes tenant-owned data takes a
  `Bilimbi.Base.Tenancy.Scope`, never a raw tenant ID.** The scope is built
  once at the edge with `Tenancy.scope/1`; downstream modules do not re-resolve
  or re-validate the tenant, and no operation below that point carries a
  `:tenant_not_found` failure. Match `%Scope{}` in the function head so a raw
  ID raises at runtime and is rejected statically by the type checker. Base
  Tenancy's own resolvers take an ID because resolving one is their job, and so
  does provisioning that creates the tenant it will scope.
- **Begin such a read with `Tenancy.scope_query/2`.** It has one clause, so a
  missing or `nil` tenant raises instead of returning an unfiltered query. A
  hand-written `tenant_id` comparison in a caller-facing read is a defect. It
  is greppable, so treat it as one:

  ```bash
  grep -rnE 'tenant_id\s*==\s*\^' apps/*/*/lib
  ```

  The surviving matches must be invariant checks inside the module that owns
  the table — row locking, or a deliberate cross-tenant uniqueness proof — and
  each one should say so in a comment or function name.
- Name constraints and indexes deliberately, especially on PostgreSQL.
- Generate migrations with `mix ecto.gen.migration`, but first confirm that
  the migration belongs to Bilimbi's compatibility plan and will not alter an
  existing Belimbing table unexpectedly.

## 14. Tests

Test outcomes and public contracts rather than implementation details.

- Use ExUnit and `Phoenix.LiveViewTest`.
- Use `start_supervised!/1` for processes in tests.
- Do not use `Process.sleep/1` or `Process.alive?/1` to synchronize tests.
  Monitor processes and assert on `:DOWN`, or use `_ = :sys.get_state/1` when
  a process must first handle prior messages.
- Test LiveViews through `element/2`, `has_element?/2`, and stable DOM IDs,
  not raw HTML strings or fragile prose.
- Use `render_submit/2` and `render_change/2` for forms.
- Test authorization, tenant boundaries, soft deletes, and schema-compatible
  persistence as observable outcomes.
- Split large behaviours into focused test files and begin with simple
  presence/contract tests before interaction-heavy tests.

## 15. Documentation and AI workflow

For every change:

1. Read the relevant root and local guidance.
2. Identify the owning Base/Core module and its public API.
3. Check the Belimbing source when business meaning or schema compatibility is
   uncertain.
4. Make the smallest complete change, including tests and documentation that
   belong to it.
5. Run focused tests while iterating.
6. Run `mix precommit` before handing off.

When a convention is important enough for an AI agent to follow, express it as
one of:

- a compiler-enforced structure;
- a test;
- a clear local `AGENTS.md` rule;
- a documented public contract;
- a deterministic command.

Do not rely on an unwritten convention.

## 16. Version control

- Keep commits focused and descriptive.
- Never commit secrets, local credentials, generated build output, or local AI
  permission files.
- Preserve unrelated user changes.
- Do not use destructive commands such as `git reset --hard` or
  `git checkout --` without explicit authorization.
- Keep the working tree clean when handing off work.

## 17. GitHub credentials in Orbs

Orbs receive two GitHub credentials with different capabilities:

- `GH_TOKEN` (the default `gh` authentication): a GitHub App user token. It
  reads Discussions and writes issues, comments, and PRs, but **cannot write
  GitHub Discussions** — `createDiscussion` and `addDiscussionComment` fail
  with `FORBIDDEN: Resource not accessible by integration`.
- `GH_DISCUSSION_TOKEN` (workspace secret, authenticates as `faith-tohmm`):
  has Discussions write permission. Use it for any Discussion creation or
  comment by overriding `GH_TOKEN` for that call only:

  ```bash
  GH_TOKEN="$GH_DISCUSSION_TOKEN" gh api graphql \
    -f query='mutation($id: ID!, $body: String!) {
      addDiscussionComment(input: {discussionId: $id, body: $body}) {
        comment { id url }
      }
    }' -f id='D_...' -f body='...'
  ```

Never print, log, or commit either token value. Do not reconfigure `gh` auth
globally to the discussion token; keep the override scoped per command.
