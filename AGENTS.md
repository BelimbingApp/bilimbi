# Bilimbi Agent and Architect Guidelines

Bilimbi is the Phoenix and Elixir implementation of the Belimbing application
platform. These rules are part of the product's engineering system. Follow
them when adding or changing code, tests, migrations, documentation, assets, or
configuration.

Read this file and `DESIGN.md` before making changes. The source Belimbing
project is the reference for business meaning and schema compatibility, not a
template for copying Laravel implementation details.

Frequent mistakes are written in the folder the next edit touches. Open that
guide yourself before changing the code it names; do not rely on a harness to
append it. Each guide points at the component comment that enforces the rule.

- `apps/AGENTS.md` — LiveView bindings, messages, withheld controls, clocks,
  read-first pages, list filters and pagination, who performed an operation,
  tests, routes, composition lock
- `apps/base/ui/AGENTS.md` — shared components, the Design Library, assets,
  hook tests, tiled workspace
- `apps/base/audit/AGENTS.md` — what an audit row records
- `apps/base/database/AGENTS.md` — silencing capture, and a boundary the
  database enforces
- `apps/core/AGENTS.md` — an archived company freezes its accounts for good
- `apps/domains/AGENTS.md` — mounting an optional repository; meta-terms only
  in Domain code
- `apps/extensions/AGENTS.md` — what an Extension may adapt
- `docs/plans/AGENTS.md` — how to write a plan

Normative sources this file points at rather than restates:

- `docs/architecture/database.md` — database ownership, dependency
  categories, migrations, schema contracts, verification, adoption, and
  seeding. Do not create a second hand-maintained database dependency
  registry.
- `docs/architecture/0010_composition-model.md` — Platform, Domain,
  Extension, dependency, and nested-repository rules.
- `apps/base/module_registry/docs/README.md` — descriptor discovery and
  validation.

Compatibility is a one-direction replacement contract. Bilimbi must be able
to adopt an existing Belimbing database and replace the Belimbing application;
Belimbing is not required to consume Bilimbi source, UI, routes, migrations,
or a database after Bilimbi-only evolution. Preserve durable business and data
contracts deliberately; do not keep Laravel framework details, legacy UI, or
internal route names merely to make Bilimbi reversible to Belimbing. ADR 0002
records the baseline and adoption decision.

## 1. Project context

Bilimbi is built with:

- Elixir 1.20.3 on Erlang/OTP 28.5, pinned in `.mise.toml`;
- Phoenix 1.8.10 and Phoenix LiveView 1.2.9;
- Ecto 3.14.1, Ecto SQL 3.14.0, Postgrex 0.22.4, and PostgreSQL 18;
- HEEx, Phoenix components, Tailwind CSS 4.3.0, and esbuild 0.25.4;
- ExUnit and `Phoenix.LiveViewTest`;
- Req 0.7.2 for declared outbound HTTP;
- Bandit 1.12.5 as the HTTP server;
- Swoosh 1.27.0 for email where email is required.

These versions record the current engineering baseline; `.mise.toml`,
`mix.lock`, and the binary versions in `config/config.exs` remain
authoritative. Use the conventions of these versions rather than habits from
older releases. Check for the latest stable compatible releases at milestone
boundaries and update this list with the pins. Keep `mix.lock` committed. Do
not use prerelease dependencies unless the task explicitly requires one and
the decision is documented.

The repository uses the composed Mix topology of ADR 0003
(`docs/architecture/decisions/0003-physical-deep-module-packages.md`). Base,
Core, and Web are direct umbrella children below `apps/`. Base and Core are
composition applications whose deep modules are nested local Mix path
packages discovered from `bilimbi.module.exs`. Domain and Extension
composition applications use the same discovery contract.

`Base` and `Core` are ownership boundaries, not superclass hierarchies. OTP
application boundaries carry dependency, supervision, and lifecycle
contracts; they do not replace deep module APIs.

## 2. Current scope

The Platform contains Base, Core, and the Web host. The installed modules are
the immediate children of `apps/base/` and `apps/core/` that carry a
`bilimbi.module.exs`; the descriptor, not this file, says what each owns.
`apps/core/compatibility/` owns schema verification, adoption, and migration
execution; `apps/web/` is the host.

The Platform repository contains no optional Domain or Extension. Those live
in their own repositories mounted under `apps/domains/` and `apps/extensions/`
(see `apps/domains/AGENTS.md`). Add production capabilities only through that
composition model and a real business requirement.

Bilimbi maps Belimbing's existing PostgreSQL schema accurately and owns Ecto
migrations that can create a fresh compatible schema. An existing Belimbing
database is verified and adopted under ADR 0002
(`docs/architecture/decisions/0002-compatible-schema-baselines.md`).

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
- **Configurable:** Never hard-code what should be configurable. Values an
  operator could reasonably set (servers and credentials, schedules, limits,
  scopes, mappings, codes, visibility, and approvers) are settings with an
  operator UI, not code constants, config files, or environment-only values.
  Secrets are stored encrypted and never displayed back or logged. Only
  bootstrap values needed before the settings store is reachable stay in the
  runtime environment; see the environment-file guidance in
  `docs/deploy/ubuntu-26.04.md` for the deployment contract and current exceptions.

## 4. Application ownership and dependency direction

### Base

`Bilimbi.Base` owns framework infrastructure and cross-cutting platform
mechanisms: database access conventions, authentication primitives,
authorization, tenancy context, settings, audit infrastructure, telemetry, and
shared contracts. Base must not depend on Core business implementations.

### Core

`Bilimbi.Core` is the required enterprise domain. It owns foundational business
modules such as User, Company, Employee, Address, and Geonames. Core may depend
on Base. Core modules collaborate through public APIs, behaviours, or explicit
events, not another module's private queries or tables.

ADR 0007
(`docs/architecture/decisions/0007-core-user-administration-integration-read.md`)
records the one exception. `Bilimbi.Core.UserAdministration.Query`, private to
`core/user_administration`, performs the bounded Users administration read
across `users`, `companies`, and `base_authz_principal_roles` as one
parameterized statement. Its allowlist is that package's `ConsumedRelations`,
checked against the owners' schema contracts, and
`architecture_boundary_test.exs` and `performance_test.exs` there hold the
guards. This is not precedent for any other sibling-private-table access;
`docs/architecture/database.md` "Exceptional private-relation read" lists what
a new exception would need.

### Future Domains and Extensions

Follow the roles, dependency rules, and placement tests in
`docs/architecture/0010_composition-model.md`.

### Web

`BilimbiWeb` is the Phoenix host: endpoint, router shell, authentication
hooks, host-only routes, assets, and host integration support. Module
LiveViews, controllers, colocated templates, and route contributions belong to
the module whose workflow they adapt (ADR 0006). Shared presentation
primitives belong to Base UI.

Placement, using Core Company:

```text
apps/core/company/lib/company.ex                  # public API, the deep module
apps/core/company/lib/company/schema.ex
apps/core/company/lib/company/web/index_live.ex   # its UI adapter
apps/core/company/priv/repo/migrations/
apps/core/company/test/
apps/core/company/web_test/company_index_live_test.exs
```

Module-owned endpoint and router integration tests live in `web_test/`; the
Web Mix project discovers and runs them against the real host, so the module
never depends on Web. Each `web_test/` carries a `test_helper.exs` that
requires the Web host's test helper; discovery fails closed when that bridge
or the owner's non-null `web:` descriptor is missing (`web_test_paths/1` in
`apps/base/module_registry/mix/module_discovery.exs`).

## 5. Stable identities and schema compatibility

Belimbing is the reference for durable business meaning and the PostgreSQL
schema Bilimbi adopts. It is not permanent authority over Bilimbi-only
evolution after that boundary. Compatibility covers more than table names:

- column names and nullability;
- primary and foreign keys;
- PostgreSQL types and sequences;
- indexes, unique constraints, partial indexes, and triggers;
- JSON shapes and status values;
- timestamp precision and timezone semantics;
- soft-delete behaviour;
- tenant, company, user, and employee relationships;
- polymorphic records and durable identifiers.

Use stable logical IDs such as `core/company` in documentation and
registries. Never derive persisted identity from a filesystem path or Elixir
module name.

### Existing database rules

- Treat Belimbing's schema as canonical while defining and adopting the
  compatible baseline. Evolve beyond it through explicit Bilimbi-only
  migrations; Belimbing never has to run them.
- Do not invent a replacement table because its Ecto schema would be cleaner.
- Do not rename an existing table or column without an explicit compatibility
  migration decision.
- Map existing sources explicitly with `schema/2`, `@primary_key`,
  `@foreign_key_type`, or field `source:` options.
- Model Laravel polymorphic columns explicitly; Ecto associations do not
  reproduce Laravel morph relationships.
- Soft deletes are an explicit query and context policy; Ecto has no global
  soft-delete scope.
- Map `json`/`jsonb`, UUIDs, bigint IDs, decimals, and timestamps to the
  actual PostgreSQL column, not a guessed Elixir type.
- Preserve PostgreSQL sequence correctness when inserting into existing tables.
- PHP serialized values and PHP class names in durable payloads are a
  compatibility concern. Do not deserialize them as ordinary Elixir terms.

### Migrations

Bilimbi records applied versions only in `bilimbi_schema_migrations`; never
read, write, rename, or repurpose Laravel's `migrations` table. A migration
stays in its owning module's `priv/repo/migrations/`; every descriptor with a
non-nil `migrations` path owns one such directory, and this file keeps no list
of them. Run the baseline from the umbrella root with `mix bilimbi.migrate`,
which discovers every contributing descriptor and merges the paths in strict
Base → Core → Domain → Extension order. Do not use broad
`create_if_not_exists` to make a migration look safe on an existing database.
Verify an existing Belimbing database with `mix bilimbi.schema.verify`, then
baseline it with `mix bilimbi.schema.adopt`; adoption refuses structural
drift. The command table, dispositions, and provenance rules are
`docs/architecture/database.md` "Migration contract" and "Ledger and
execution". A compatible baseline is proved against the Laravel-generated
schema fixture in `apps/core/compatibility/test/fixtures/belimbing/`, never
only against Bilimbi's own baselines: Laravel's `unique()` is a table
constraint, and a shipped migration that creates an index Belimbing
already has creates it only if absent.

### Module boundaries fixed by compatibility

Base Session owns the compatible durable `sessions` table without depending on
Core User or Web. `payload` is opaque: Base stores, fetches, lists metadata,
terminates, and prunes sessions, and never interprets Laravel payloads or
attaches authentication semantics. Listings never expose payloads, and
terminating another session protects the caller's current session ID.

Core User owns account credentials and lifecycle. New hashes are Argon2id;
existing Laravel Argon2 hashes stay valid, and a successful legacy `$2y$`
bcrypt login is upgraded. Never accept a caller-supplied password hash or
expose credential or reset-token schemas. Core provides neutral reset and
signed verification primitives; Web owns routes, IP and login throttling,
delivery, cookies, and the authenticated Session adapter. Public
self-registration stays disabled unless an architecture decision changes that
policy.

The explicit-tenancy compatibility source is Belimbing merge commit
`e70b4d33c0b10790e681f4c2b5095d85a53bc918`. Resolve the platform operator only
through `tenants.is_platform_operator` and a tenant's primary company only
through `tenant_primary_companies`. Numeric ID 1 has no runtime meaning; it is
bounded historical migration input.

`companies.tenant_id` is non-null with no default. Every Company write
receives or derives an explicit, validated tenant. Do not infer a primary
company from row age. Base Tenancy owns operator resolution and never queries
Core Company tables; Core Company owns primary-company resolution, assignment,
transfer, and provisioning.

Core Geonames owns the canonical country, first-level administrative division,
postcode, and city lookup tables; fresh installation creates them empty, and
reference-data import is separately owned seeding. Core Address preserves the
canonical non-null `addresses.tenant_id`, its named index, restricted tenant
foreign key, and its two Geonames normalization foreign keys.

Base Authz owns capability vocabulary, roles, direct grants, evaluation, and
decision logs. Capability definitions come from installed module
contributions; there is no capabilities table, and an unknown key fails
closed. Custom roles require a live owning company; system roles are
company-less. Core Company owns the restricted `base_authz_roles.company_id`
foreign key and the exact `is_system = (company_id IS NULL)` check. Reconcile
configured system roles only through the explicit production-seed path, never
at boot, and never delete principal grants during reconciliation. When AI
provider configuration is ported, its lookup requires an owning company ID;
tenant identity alone must not resolve credentials.

## 6. Deep-module design

The physical module directory is the ownership, packaging, and future
nested-Git boundary. `apps/base/tenancy/` is the complete Base Tenancy
boundary: its own `mix.exs`, `bilimbi.module.exs`, `lib/`, tests, docs, and
any owned migrations or assets.

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

`lib/` starts at the module; do not repeat the platform and layer path below
it. `lib/tenancy.ex` still declares `Bilimbi.Base.Tenancy`; flattening the
filesystem does not shorten the Elixir namespace. Facade, implementation,
migrations, tests, docs, descriptor, and assets never split across the parent
composition application.

Each container `mix.exs` calls generic discovery and names no child; each
immediate child has a valid `bilimbi.module.exs` and a `mix.exs` derived from
it. The descriptor is the sole declaration of the module's stable ID, layer,
OTP application, namespace, dependencies, required state, migration path and
dispositions, schema contract, route-data path, contribution provider, and dev
seed. `web` and `contribution_provider` are always present and `nil` when the
module contributes nothing. A provider implements the ModuleRegistry behaviour
and returns immutable plain terms under only the consumer keys
`ContributionRegistry` validates: `:settings`, `:authz`, `:menu`,
`:dashboard`, `:principal_directory`, `:schedule`, `:actor_verifier`,
`:system_principals`, `:workflow`, and `:grid` (ADRs 0004, 0009, 0011, 0012,
0016, 0017, 0018, 0019). `mix.exs` derives its local path dependencies from
the descriptor; never list them by hand.

A non-nil `migrations` path requires `migration_dispositions` mapping every
owned migration version exactly once to `:compatible_baseline` or
`:bilimbi_only`. There is no default; adding, removing, or reclassifying a
migration fails discovery until the descriptor is exact
(`docs/architecture/database.md` "Migration contract").

Discovery fails during dependency resolution on a malformed or missing
descriptor, duplicate stable ID or OTP application, missing dependency,
cycle, layer/container mismatch, or upward dependency; valid modules are
ordered dependency-first, then by stable ID, with layers Base → Core →
Domain → Extension. Base ModuleRegistry owns those source-loadable Mix
helpers in its `mix/` directory (kept in that package's formatter) and the
shared `:bilimbi_graph` compiler every module project lists before Mix's
standard compilers; it records each package's validated position and the
workspace-graph fingerprint in application metadata. Runtime consumers verify
that one fingerprint and use the approved positions; never implement a second
graph algorithm. `apps/base/module_registry/docs/README.md` has the rest.

Base Database owns the one Repo, deliberately named `Bilimbi.Base.Repo`
across the platform. That documented exception does not let any other module
escape its declared namespace. Core Compatibility discovers migration paths
from the approved composition metadata and runs them through the single
ledger; it must not hard-code any contributor, and its coordinator never
carries module-specific SQL. A descriptor's schema contract owns that
module's structural table specifications and live-data invariants;
Compatibility iterates installed contracts generically. Migration modules use
the owning descriptor namespace.

The Base and Core composition applications contain no `lib/`, `priv/`, or
`test/`. Schemas, services, application callbacks, mailers, marker modules,
migrations, seeds, fixtures, and tests live in the owning child module; the
containers delegate `mix test` to each child. External library dependencies
belong to the module that uses them, never to a container for possible future
use. A module declares in its own `mix.exs` every library its `lib/` or
`test/` calls (`phoenix_live_view`, `ecto`, `jason`, `postgrex`, and so on),
never relying on `base/ui` or `base/database` to bring it in; Mix rejects an
`only:` restriction on a library another dependency requires. `mandates.sh`
checks the common ones for `lib/`.

Cross-module tests may load lower-layer test support from declared
dependencies, but table DDL and fixtures are defined once by their owner. Base
Database owns the shared SQL sandbox case. Web tests set up business identity
through public module APIs, never by writing domain tables.

Generate a migration with `mix ecto.gen.migration` from the owning module
root, or pass its `--migrations-path`, after confirming it belongs to the
compatibility plan and does not alter an existing Belimbing table
unexpectedly. The file stays below that module's `priv/repo/migrations`;
never generate into a composition application and move it later.

Each module exposes a small public API around its business capability:

```elixir
Bilimbi.Core.Company.list_companies(scope)
Bilimbi.Core.Company.get_company(scope, id)
Bilimbi.Core.Company.create_company(scope, attrs)
```

Schemas, queries, changesets, locking, and internal workflows stay behind it;
a caller never needs to know which table or query implements an operation.

Use a behaviour for a real stable seam or more than one meaningful
implementation, a protocol when dispatch depends on the data type, and a
macro only when it removes a proven, repeated source of complexity. Do not
add any of them to imitate PHP interfaces or inheritance.

Events publish facts without consumer-specific implementation codes.
Synchronous collaboration uses a documented API or behaviour. An optional
integration must never make a Core module fail to boot.

## 7. Elixir conventions

- One primary module per file. Keep nested modules in their own files unless
  the code is a deliberately tiny private helper.
- Prefer pattern matching, guards, `case`, `cond`, and `with` over nested
  conditionals.
- Data is immutable. Rebind the result of `if`, `case`, `cond`, and `with`
  when it is needed afterward.
- Lists do not support index access. Use pattern matching, `Enum.at/2`, or
  the appropriate `List` function.
- Do not use map access syntax on structs. Access fields directly or use the
  struct's API; for changesets, `Ecto.Changeset.get_field/2`.
- Predicate functions end in `?`; reserve `is_` names for guards.
- Never call `String.to_atom/1` on user input.
- Prefer standard library date/time types and functions over a package for a
  problem the standard library already solves.
- Use `Task.async_stream/3` for concurrent collection work with
  back-pressure; use `timeout: :infinity` when the operation is intentionally
  unbounded.
- Name OTP processes in child specifications, for example
  `{DynamicSupervisor, name: Bilimbi.SomeSupervisor}`.

## 8. Dependencies and HTTP

A module that needs outbound HTTP adds `Req` to its own `mix.exs`; Web (its
Swoosh API client) and Core Geonames (reference-data import) own it today. Do
not place Req in a container for a future child, and do not add or use
`HTTPoison`, `Tesla`, or `:httpc`.

Before adding any dependency, check whether the standard library, Phoenix,
Ecto, or an existing dependency already provides the capability, and record
the reason in the change when one is necessary. Keep versions current and
compatible; update `mix.lock`, compile, format, and test after an update.

Phoenix 1.8, LiveView 1.2, and Ecto 3.14 are newer than much of what a model
learned. Check the installed version before calling a library function or
copying a pattern:

```bash
mix usage_rules.docs Module.function/arity
mix usage_rules.search_docs "phrase" -p package
```

`usage_rules.docs` reads the locked version. `search_docs` searches the
latest Hex release, so use it only to find a page, then confirm with
`usage_rules.docs`. `h Module.function` in `iex -S mix` shows the same docs;
the source is `deps/<package>`. When a dependency is upgraded, record the new
pattern and the retired one in the component comment and the folder guide in
the same change.

Files a library ships, such as `deps/phoenix/usage-rules/*.md` and
`deps/sobelow/usage-rules.md`, are that library's notes. This guide and the
folder guides win where they disagree; do not copy those files into a guide.
Known disagreements:

- `liveview.md` says a stream prepend uses `at: -1`. LiveView 1.2.9 appends
  at `-1` and prepends at `0` (the `:at` option of `stream/4`). Re-check on
  upgrade; delete this line once Phoenix corrects the file.
- `ecto.md` generates a migration wherever `mix ecto.gen.migration` runs. A
  Bilimbi migration belongs to the owning module and runs through
  `mix bilimbi.migrate` (§6).
- `html.md` puts app-wide imports in `my_app_web.ex`. A module LiveView uses
  `Bilimbi.Base.UI, :live_view`.
- `liveview.md` names a view `AppWeb.WeatherLive` under the router's alias. A
  Bilimbi LiveView lives on the owning module, such as
  `Bilimbi.Core.Company.Web.IndexLive`.
- The same file shows an empty stream with a Tailwind `only:` class. An empty
  region uses `<.empty_state>`.

## 9. Phoenix application conventions

- Use verified routes and the `~p` sigil for internal paths.
- Router scopes already provide their configured module alias; do not add
  duplicate route aliases.
- Do not use deprecated `live_redirect` or `live_patch`. Use
  `<.link navigate={...}>`, `<.link patch={...}>`, `push_navigate/2`, and
  `push_patch/2`.
- Module-owned LiveViews use a `Live` suffix, such as
  `Bilimbi.Core.Company.Web.IndexLive`.
- Keep business rules out of controllers and LiveViews. They coordinate
  request state and call domain APIs.
- Use the existing `Bilimbi.Base.UI.Layouts` and `Bilimbi.Base.UI.Components`
  instead of creating parallel shared foundations.

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
- Use `~H` or `.html.heex`; never old `~E` templates.
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
- A Design Library specimen calls the real component. Anchor, state, and
  catalog-id rules live with `Bilimbi.Base.UI.DesignLibrarySource` and
  `apps/base/ui/AGENTS.md`.

Templates may be colocated with their owning LiveView through
`embed_templates` or a nearby `.html.heex` file. Colocation does not move the
view into the domain namespace or let it bypass the domain API.

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

Streams are not enumerable and do not provide counts. Track counts
separately, and refetch plus `reset: true` when filtering or refreshing a
collection. Re-stream items when an assign changes the content of a streamed
item. Do not use deprecated `phx-update="append"` or `phx-update="prepend"`.

## 12. JavaScript and CSS

Interface rules live in `DESIGN.md`. The mistakes that keep recurring, and
the asset and generator rules, live in `apps/base/ui/AGENTS.md`. Read both
before editing HEEx, a shared component, or `apps/web/assets`. Where a
component comment states the rule, follow that comment instead of restating
it at the call site.

## 13. Ecto conventions

- Use `Ecto.Schema` for persistence mapping and context modules for public
  operations; `Ecto.Changeset` for casts and validation.
- Never cast programmatically assigned fields such as `user_id`, `tenant_id`,
  or actor IDs from untrusted form parameters.
- Use `Ecto.Changeset.get_field/2` for changeset values.
- Preload associations before accessing them in templates.
- Import `Ecto.Query` explicitly where query macros are used.
- Use explicit query scopes for tenant and soft-delete filtering.
- **A module API that reads or writes tenant-owned data takes a
  `Bilimbi.Base.Tenancy.Scope`, never a raw tenant ID.** The scope is built
  once at the edge with `Tenancy.scope/1`; downstream modules do not
  re-resolve or re-validate the tenant, and no operation below that point
  carries a `:tenant_not_found` failure. Match `%Scope{}` in the function head
  so a raw ID raises at runtime and is rejected statically by the type
  checker. Base Tenancy's own resolvers take an ID because resolving one is
  their job, and so does provisioning that creates the tenant it will scope.
- **Begin such a read with `Tenancy.scope_query/2`.** It has one clause, so a
  missing or `nil` tenant raises instead of returning an unfiltered query. A
  hand-written `tenant_id` comparison in a caller-facing read is a defect. It
  is greppable, so treat it as one:

  ```bash
  grep -rnE 'tenant_id\s*==\s*\^' apps/*/*/lib
  ```

  The surviving matches must be invariant checks inside the module that owns
  the table (row locking, or a deliberate cross-tenant uniqueness proof), each
  saying so in a comment or function name. `.github/scripts/mandates.sh`
  allowlists exactly those sites; extending it is a review decision made in
  the same change.
- Name constraints and indexes deliberately, especially on PostgreSQL.
- **Every write through `Bilimbi.Base.Repo` is audited**, struct writes and
  `insert_all`/`update_all`/`delete_all` alike (ADR 0013). What a row
  records, and how silence is allowed, lives in `apps/base/audit/AGENTS.md`
  and `apps/base/database/AGENTS.md`. Raw SQL bypasses the repo, so raw-SQL
  DML outside the lifecycle modules that need it (production-seed ledger,
  compatibility cutover) is a review defect.
- The database console is a developer tool on the application's own
  connection with no login of its own. PostgreSQL itself refuses a console
  write, and every console command, refused and failed ones included, is one
  row in the audit actions log (`Bilimbi.Base.Database.ConsoleCapture` is the
  seam, `Bilimbi.Base.Audit.ConsoleCapture` the record). Do not add a
  recorder to a console screen: the executor records every command it is
  handed.

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
- Prove behaviour, never source: `apps/AGENTS.md` "Tests" owns that rule and
  the fixtures and discovery helpers a test should use.

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

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in
this project. Do not repeat what the codebase already shows; point to the
authoritative file or command instead. Prefer rewriting or pruning existing
entries over appending new ones. When updating this file, preserve this bar
for all agents and keep entries concise.
