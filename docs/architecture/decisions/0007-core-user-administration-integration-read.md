# ADR 0007: Contained Core User Administration integration read

**Document Type:** Architecture Decision Record
**Status:** Proposed
**Agents:** codex/terra-user-admin-adr-1
**Scope:** Ownership, dependency direction, persistence access, bounded query,
route transfer, and enforcement for the Users administration index
**Last Updated:** 2026-08-24

> This ADR records one proposed exceptional private-relation read. The current
> general dependency and database-access rules are centralized in
> [Bilimbi Database Architecture](../database.md).

## Context

The Users administration index is one required S2 workflow whose durable read
contract crosses three existing persistence owners:

- Core User owns `users` and account commands;
- Core Company owns tenant affiliation, Company names, and Company archival;
- Base Authz owns Roles and principal-role assignments.

At the pinned Belimbing commit
`e70b4d33c0b10790e681f4c2b5095d85a53bc918`,
`app/Core/User/Livewire/Users/Index.php` builds one relational result before
pagination. It joins Users to Companies, filters by the current tenant,
optionally searches User name or email, optionally applies an OR Role filter,
sorts by Name, Email, Company, or Created, adds `users.id DESC` as the stable
tie-breaker, and only then paginates. The Blade consumes Company names, Role
summaries, and page metadata. This ordering is observable: paginating before
the Role filter changes totals and can omit matches.

The existing public facades cannot compose that result with bounded,
database-equivalent semantics. Core User can obtain archived-inclusive tenant
Company IDs but not archived Company names or a Company-name ordering
relation. Core Company's name-bearing list excludes archived rows. Base Authz
pages assignments for one principal; it does not expose a bounded reverse
User index. Calling these APIs per User creates N+1 work, while walking their
complete result sets creates unbounded BEAM materialization. A count query and
a later page query would also observe different Read Committed snapshots.

ADR 0003 and root guidance deliberately prohibit one Core module from querying
a sibling's private schema or table merely because a descriptor dependency
exists. That remains the default. `SchemaContract.tables/0` describes and
version-checks owned structure for compatibility; it is not authority for a
runtime read. The Users index therefore needs both a coherent workflow owner
and one explicit, narrow, machine-enforced exception before product code may
exist.

ADR 0006 separately requires the module that owns a screen to own its Phoenix
adapter and route contribution. The ownership decision must therefore account
for both the integration read and the `/users` index route without creating a
dependency cycle.

## Decision

While this ADR is Proposed, it grants no exception. Independent acceptance
and merge make the ownership and containment decision effective, but do not by
themselves authorize a product read. The read authorization remains dormant
until the package, manifest, and all guards in this ADR land atomically and
pass independent architecture/security review. Until then, the general
sibling-private-table prohibition applies without exception.

### 1. Establish one required, single-purpose Core module

The final stable identity is:

| Identity | Value |
| --- | --- |
| Stable module ID | `core/user_administration` |
| Directory | `apps/core/user_administration/` |
| OTP application | `:bilimbi_core_user_administration` |
| Public namespace | `Bilimbi.Core.UserAdministration` |

This is durable product vocabulary, not a provisional integration bucket. The
module owns only the bounded Users administration index read model and, after
the atomic route transfer described below, that index's Phoenix adapter. It
does not own User credentials, User mutations, Company lifecycle, Authz
commands, or unrelated administration screens.

The future descriptor is `required: true`, `layer: :core`,
`contribution_provider: nil`, `migrations: nil`, and `schema_contract: nil`.
Core User retains the existing Users menu and capability contribution.

The complete read-plus-adapter module uses these direct dependencies:

```text
core/user_administration
  -> core/user
  -> core/company
  -> base/authz
  -> base/database
  -> base/module_registry
  -> base/tenancy
  -> base/ui
```

The read-model package initially lands with `web: nil` and the first six
truthful edges: `core/user`, `core/company`, `base/authz`, `base/database`,
`base/module_registry`, and `base/tenancy`. Its integration contract validates
the three owner structures, its private query uses the shared Repo and Tenancy
scope, and the package participates in descriptor discovery. The later atomic
adapter phase adds `base/ui` when its LiveView consumes that public contract
and changes `web` to its route-data path. The adapter calls Core User's public
commands and navigation contracts; it never reads User persistence for a
command. Dependencies of the six initial modules, including User's Session,
Settings, Employee, and UI dependencies, remain transitive and must not be
repeated unless this package directly consumes their public contracts.
Nothing depends back on `core/user_administration`.

### 2. Authorize one conditional, read-only persistence exception

The general prohibition on sibling-private-table access remains in force.
Once all enforcement in this ADR lands atomically, only the private module
`Bilimbi.Core.UserAdministration.Query` may read the following schema-less
relations and columns:

- `core/user` — `users`: `id`, `company_id`, `name`, `email`, `created_at`;
- `core/company` — `companies`: `id`, `tenant_id`, `name`, `deleted_at`;
- `base/authz` — `base_authz_principal_roles`: `company_id`,
  `principal_type`, `principal_id`, `role_id`; and
- `base/authz` — `base_authz_roles`: `id`, `company_id`, `name`, `code`,
  `is_system`.

The authorization is source-site and purpose specific. It permits a read for
the bounded Users index only. It does not permit:

- writes, locks, commands, or data repair;
- importing or aliasing owner Ecto schemas;
- accepting or returning an Ecto schema or queryable;
- public query builders, fragments, relation names, column names, or table
  helpers;
- `Bilimbi.Base.Repo.query/2`, `query!/2`, or another raw-SQL escape;
- dynamic relation, column, ordering, or fragment identifiers;
- selecting any column outside the exact allowlist; or
- copying the read into another module, package, test helper, or Web adapter.

Fixed, parameterized, independently reviewed Ecto `fragment` expressions are
allowed only inside the private Query module when Ecto's ordinary constructs
cannot express the one-statement CTE, empty-page envelope, or bounded Role
aggregation. A fragment's SQL shape and identifiers are compile-time fixed;
all values remain bound parameters. No fragment or queryable becomes public.

This exception is unique and is not a generic descriptor feature. It does not
create an `integration_reads` descriptor key and is not precedent for ordinary
Core collaboration. Another cross-owner query requires its own ownership
decision and ADR; it cannot cite this decision as standing permission.

### 3. Version and enforce consumed structure

The future package owns a `ConsumedRelations` manifest. Version 1 records, for
each entry above, the owner stable ID, owner `SchemaContract`, owner baseline
migration version, relation, and exact column type/nullability contract.

Package tests compare the manifest with each owner's public
`SchemaContract.tables/0`. The comparison proves that every required relation
and column still has the reviewed structure. It does not grant access. Any
owner change to a consumed relation, name, type, or nullability requires an
explicit manifest version change and review by both the owning module and
User Administration owners.

The package implementation and its enforcement land in one PR. Product query
code is blocked unless architecture-boundary tests:

1. inspect Elixir/Ecto AST and source positions rather than matching workspace
   strings;
2. allow schema-less source sites only in the private Query module;
3. prove the selected column set equals, rather than merely includes, the ADR
   allowlist;
4. reject owner schemas, raw Repo queries, dynamic identifiers, public
   queryables/fragments/helpers, and writes;
5. reject copies of the four relation reads outside the allowed source sites;
6. validate the manifest against owner structural contracts; and
7. verify the exact descriptor graph without reverse or unnecessary
   transitive edges.

No useful source boundary exists before the package exists. This ADR therefore
adds no tautological architecture test. The guards above are a prerequisite of
the package PR and must fail that PR if the query exists without them.

### 4. Preserve one-statement, bounded snapshot semantics

One public page call executes exactly one parameterized PostgreSQL statement.
That statement produces, from one query snapshot:

- the complete filtered count;
- the requested ordered page;
- archived-inclusive Company facts for page entries; and
- Role summaries aggregated only for the bounded page entries.

The statement must retain a count/envelope row when the result or requested
page is empty, so totals remain truthful without a second query. A suitable
implementation may use fixed Ecto CTEs for the filtered User/Company
relation, count, ordered `LIMIT`/`OFFSET` page, and page-only Role aggregation.
Its public result is a bounded, schema-free page/read model.

The implementation must not:

- paginate before search or Role filtering;
- load a tenant-wide owner API result into BEAM;
- issue a Role or Company query per User;
- split count and page into separate statements or snapshots;
- aggregate every matching User merely to return one page; or
- expose persistence terms, hashes, tokens, or private metadata.

The database may scan matching rows to calculate the exact count. The
application receives only page metadata and a bounded page whose size is one
of the approved values below.

The public facade is
`Bilimbi.Core.UserAdministration.list_users(%Scope{}, options)` and returns a
stable `%Page{}` rather than `{:ok, queryable}` or persistence terms. Its
normalized internal options are:

```elixir
%Options{
  search: nil | binary(),
  role_ids: [pos_integer()],
  sort_by: :name | :email | :company_name | :created_at,
  sort_dir: :asc | :desc,
  page: pos_integer(),
  page_size: 10 | 25 | 50 | 100
}
```

Search is at most 255 bytes. Role IDs are unique positive integers with a
maximum of 100 selections and OR semantics. Defaults are `nil`, `[]`,
`:name`, `:asc`, `1`, and `25`. The API accepts only a keyword list with the
documented keys and normalized values; malformed or unknown options raise
`ArgumentError`, a raw tenant ID fails the `%Scope{}` function head, and an
unknown but well-formed Role ID simply matches no entries.

The returned contracts contain only:

```elixir
%Page{
  entries: [Entry.t()],
  page: pos_integer(),
  page_size: 10 | 25 | 50 | 100,
  total_entries: non_neg_integer(),
  total_pages: non_neg_integer()
}

%Entry{
  id: pos_integer(),
  company_id: pos_integer(),
  name: binary(),
  email: binary(),
  created_at: NaiveDateTime.t() | nil,
  company_name: binary(),
  company_archived: boolean(),
  roles: [Role.t()]
}

%Role{
  id: pos_integer(),
  name: binary(),
  code: binary(),
  is_system: boolean()
}
```

Empty and out-of-range pages have `entries: []` and truthful totals; an empty
result has `total_pages: 0`. Roles are unique by durable Role ID and ordered by
`{name, code, id}` so duplicate assignments do not destabilize rendering.

### 5. Preserve the pinned interaction contract

The Phoenix adapter owns URL/form normalization; the internal page API accepts
only normalized values.

Page size has the source's four choices: `[10, 25, 50, 100]`, defaulting to
`25`. A crafted parsed integer is clamped upward to the smallest supported
choice at least as large as the value and capped at `100`. Tests must prove at
least `1 -> 10`, `30 -> 50`, and `9999 -> 100`; absent or unparseable input
uses `25`. Changing page size resets to page 1.

Search applies parameterized PostgreSQL `LIKE` to User name or email. Empty
search and the exact string `"0"` disable the filter, preserving the pinned
PHP-falsey edge. `%` and `_` retain PostgreSQL wildcard meaning, and matching
keeps PostgreSQL `LIKE` case behavior; the adapter must not silently switch to
`ILIKE` or escape wildcard characters as literals.

The initial sort is Name ascending. Each sortable column has a reviewed first
toggle; in particular, switching to Created for the first time selects
descending. For every sort, the requested direction applies to the primary
expression and `users.id DESC` remains the deterministic secondary ordering,
regardless of the primary direction. Role selections have OR semantics and
are applied before count and pagination.

Only fixed allowlists map adapter strings to internal sort/page options. No
request value is converted to an atom or interpolated as an identifier.

### 6. Define tenancy, Authz, and exposure rules

User visibility starts from the Company-owned tenant relation, using
`%Bilimbi.Base.Tenancy.Scope{}` and the public tenancy scoping contract. It
joins `users.company_id` to `companies.id` and deliberately does not exclude a
Company solely because `deleted_at` is set. Therefore:

- a User affiliated with an archived Company remains visible with that
  Company's name and archived state;
- a User with `company_id: nil` is absent; and
- a User affiliated to another tenant is absent.

Data visibility is not actor authorization. The `/users` route remains gated
by `admin.user.list`; buttons/events separately enforce their command
capabilities. The integration facade enforces scope visibility, while the
adapter authorizes the actor before calling it. The adapter uses public Core
User APIs for commands and navigation and must not extend this read exception
to mutation. Archived-affiliation actions remain truthful about any public
Core User command that rejects archived Company ownership.

Role summaries and filters apply an integration-only corrupt-data/non-leak
policy. This is deliberately narrower than, and does not change, #140's
`list_principal_role_assignments/4` behavior:

- the assignment itself must be visible under the accepted Authz assignment
  Company scope;
- a custom Role must be non-system and owned by a live, in-scope Company;
- a system Role must have both `is_system = true` and global
  `company_id IS NULL` identity;
- a visible assignment joined to a foreign or archived custom Role is hidden;
- an assignment whose Role is missing is ignored; and
- duplicate visible assignments yield one Role summary per durable Role ID.

An archived Company may still establish User affiliation and provide the
displayed Company name, but Authz rows owned only by an archived Company remain
hidden. System and custom Role choices offered by the adapter continue to use
bounded public Authz APIs; the integration exception is not a Role-directory
API.

Public page, entry, and Role-summary values are stable plain structs or terms.
They contain only UI-safe User identity fields, Company summary fields, Role
summary fields, sort/page metadata, and counts. They never contain credential
hashes, remember/reset/verification tokens, raw Authz metadata, private
schemas, Ecto metadata, or queryables.

### 7. Transfer only the index route, atomically and later

The package may first land its tested read model with `web: nil`. Route
ownership changes only in a later atomic, steward-ACKed adapter change:

- `core/user_administration` gains one contribution for exactly `/users`,
  targeting its module-owned IndexLive with `admin.user.list`;
- Core User simultaneously removes only its `/users` contribution and old
  IndexLive;
- Core User retains `/users/new`, `/users/:id`, and `/users/:id/edit` with
  their existing adapters and capability gates;
- Core User retains the Users menu/capability contribution, whose `/users`
  target must resolve to the new owner; and
- the host router gains no module-specific entry or shim.

Moving only the IndexLive is necessary. User Administration depends on Core
User for public commands. If Core User's IndexLive instead called the new
facade, a reverse `core/user -> core/user_administration` edge would create a
cycle. Web cannot own the query or adapter because ADR 0006 assigns business
adapters to their deep module.

The route change must prove on a clean first build that `/users` is discovered,
verified, and reachable exactly once and that the three retained User routes
remain reachable exactly once. Route-manifest and endpoint tests cover the
same facts. Any change to the hot ModuleRegistry workspace fixture requires a
separate, explicit Integration Steward ACK and must preserve every existing
fixture entry.

### 8. Require proportional performance evidence; add no initial migration

The first implementation owns no migration, database view, function, or index.
A view or function would not be ownerless: it would carry the same coupling,
need an owning migration/compatibility contract, and add rollback cost without
first proving the one-statement Ecto design insufficient.

Before adapter integration, the implementation owner and database reviewer
agree a representative data shape and proportional latency, buffer, and query
count budget. `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` evidence must cover
unfiltered and selective/nonselective search, every sort, Role filtering,
combined filters, first/deep/out-of-range pages, and archived Company data.
Telemetry or sandbox evidence proves one statement per page call. This gate is
evidence-driven; it does not impose an arbitrary fixed production cardinality
as a merge blocker.

If evidence requires an index, the module that owns the indexed table receives
a separate migration issue and compatibility review. User Administration must
not add indexes to sibling-owned tables or hide an index inside an integration
migration.

### 9. Stage implementation and independent review

Implementation proceeds in separately reviewable gates:

1. accept this ADR and its narrow root rule;
2. add the required package, exact descriptor graph, schema-free contracts,
   `ConsumedRelations` version 1, private one-statement Query, boundary guards,
   and focused contract/security tests, with `web: nil`;
3. obtain independent architecture/security review of exception containment,
   tenant/Authz visibility, selected-column equality, and secret/schema
   non-exposure;
4. obtain independent database review of query count, snapshot semantics, and
   the agreed EXPLAIN budget;
5. transfer the adapter and `/users` route atomically under separate hot-path
   ACK, with endpoint, accessibility, route-manifest, first-build, and
   workspace-boundary evidence; and
6. add only evidence-driven, owner-specific performance migrations in later
   issues.

No product query may land before steps 1 and 2 are complete. No route may move
before the read contract and both architecture/security and database reviews
are accepted.

## Alternatives considered

### Put the query in Core User

Rejected as the default even though the dependency direction is mechanically
legal. Hiding the exceptional sibling reads inside an ordinary identity owner
weakens the general boundary and makes it easier to expand. A single-purpose
package makes the coupling visible and enforceable.

### Put the query in Base Authz

Rejected because Base cannot depend upward on Core User or Core Company, and
Authz must not own User/Company presentation semantics.

### Put the query in Core Company

Rejected because Company would need to depend on User while User already
depends on Company, creating a cycle and assigning a User workflow to the
wrong owner.

### Put the query or business rules in Web

Rejected because Web is an adapter host, not a business-query owner. This
would also conflict with ADR 0006's module-owned adapter rule.

### Put the query in Core Compatibility

Rejected because Compatibility is a generic migration/schema-contract
coordinator. A User screen would make it a business integration dumping ground
and compromise generic discovery.

### Introduce a Domain or Extension

Rejected because User Administration is required S2/Core product behavior.
Domain and Extension implementation remains stage-gated and optional; it
cannot own a required baseline workflow.

### Compose public queryables, fragments, behaviors, or list APIs

Rejected. A public Ecto relation or SQL fragment is a persistence escape, not
a deep API. Separate callbacks or bounded lists cannot compose one exact
count/order/page snapshot; walking all pages is unbounded. Protocol dispatch
does not solve relational composition.

### Create a database view or function first

Rejected for the initial implementation. It still needs an explicit owner,
migration, structural compatibility, and rollback policy while duplicating a
query that can be expressed as one reviewed statement. It may be reconsidered
only with measured evidence and a new decision.

## Consequences

- The required Users index has one coherent owner and one bounded public read
  contract without making Base depend on Core or Web own business rules.
- One narrowly exceptional persistence read becomes visible in the package,
  dependency graph, ADR, manifest, source-position guards, and independent
  reviews.
- Owner structural changes to the four consumed relations become coordinated,
  versioned changes instead of silent integration breakage.
- Exact filtered totals, ordering, archived Company names, and Role summaries
  share one PostgreSQL statement and snapshot.
- Core User continues to own credentials, commands, menu/capabilities, and the
  create/show/edit routes; the new module adds no mutation seam.
- The package and later route transfer add coordination cost and seven direct
  dependency edges. That cost is accepted because the workflow genuinely
  spans those contracts and the graph remains acyclic.
- The exception cannot be reused by ordinary modules and does not relax ADR
  0003's default collaboration rule.
- No initial migration means there is no data rollback. Before route transfer,
  rollback removes or reverts the package as one unit. After route transfer,
  rollback must atomically restore `/users` and IndexLive to Core User while
  removing the new contribution, preserving exactly-one route reachability.
  The required package must not be disabled at runtime while its route or
  descriptor remains installed.
- If the exceptional read is later removed, the package, route contribution,
  consumed-relation manifest, descriptor edges, workspace expectation, and
  root exception rule are removed together, and this ADR is superseded. Owner
  tables and data are unaffected.

## References

- [ADR 0003: Physical deep-module packages](./0003-physical-deep-module-packages.md)
- [ADR 0006: Module-owned web adapters and route discovery](./0006-module-owned-web-adapters.md)
- [Issue #142 feasibility evidence](https://github.com/BelimbingApp/bilimbi/issues/142#issuecomment-5286583919)
- [Issue #168 architecture decision](https://github.com/BelimbingApp/bilimbi/issues/168#issuecomment-5286916058)
- [Issue #168 independent corrections](https://github.com/BelimbingApp/bilimbi/issues/168#issuecomment-5286960077)
- [Issue #171 steward ACK](https://github.com/BelimbingApp/bilimbi/issues/171#issuecomment-5286971426)
- [Pinned Users index](https://github.com/BelimbingApp/belimbing/blob/e70b4d33c0b10790e681f4c2b5095d85a53bc918/app/Core/User/Livewire/Users/Index.php)
- [Pinned per-page behavior](https://github.com/BelimbingApp/belimbing/blob/e70b4d33c0b10790e681f4c2b5095d85a53bc918/app/Base/Foundation/Livewire/Concerns/SelectsPerPage.php)
- [Pinned sort-toggle behavior](https://github.com/BelimbingApp/belimbing/blob/e70b4d33c0b10790e681f4c2b5095d85a53bc918/app/Base/Foundation/Livewire/Concerns/TogglesSort.php)
