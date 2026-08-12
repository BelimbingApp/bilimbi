# Platform Baseline Source Inventory

**Task:** [BLB-S1-002](../tasks/BLB-S1-002.md)
**Document Type:** Source analysis (read-only)
**Analyst:** claude/opus-5 — source analyst
**Bilimbi Base Commit:** `54b50b0`
**Belimbing Source:** `/home/kiat/repo/laravel/blb` at merge commit
`e70b4d33c0b10790e681f4c2b5095d85a53bc918`
**Last Updated:** 2026-08-12

This maps what Belimbing owns, what Bilimbi already has, and what the Platform
Baseline still needs. It designs nothing. Every claim cites a path.

## 1. Method and source verification

`AGENTS.md` §5 names `e70b4d33c0b10790e681f4c2b5095d85a53bc918` as the
explicit-tenancy compatibility source. `git cat-file -t` resolves it in
`/home/kiat/repo/laravel/blb`, where `git log --oneline -1` reads
`e70b4d33 Merge pull request #245 from BelimbingApp/feat/explicit-tenancy-model`.
That tree is the code source of truth.

`/home/kiat/repo/Belimbing` is **not** the code source. It holds `bmad/`,
`docs/`, and `notes/` with no `app/` tree. Agents citing "Belimbing" must cite
`laravel/blb` paths or they are citing planning material.

Analysis was restricted to reading. No product file, root doc, ADR, descriptor,
migration, or lockfile was changed. Board and task-card edits are recorded in
[`claude-opus-5.md`](../mailboxes/claude-opus-5.md).

## 2. The migration prefix ledger is the ownership map

Belimbing keeps three framework tables in `database/migrations`
(`cache`, `jobs`, `sessions`) and puts **everything else** in
`app/<Layer>/<Module>/Database/Migrations`, ordered by a hand-assigned global
numeric prefix. That prefix is the most reliable ownership and ordering
evidence in the repository.

| Prefix | Owner | Tables |
|---|---|---|
| `0001_01_01_*` | Base/Database | 12 |
| `0100_01_01_*` | Base/Foundation | 1 |
| `0100_01_11_*` | Base/Authz | 5 |
| `0100_01_13_*` | Base/Settings | 1 |
| `0100_01_15_*` | Base/Workflow | 11 |
| `0100_01_17_*` | Base/Audit | 2 |
| `0100_01_19_*` | Base/Integration | 2 |
| `0100_01_21_*` | Base/Media | 1 |
| `0100_01_23_*` | Base/Schedule | 2 |
| `0100_01_25_*` | Base/Tenancy | 1 |
| `0200_01_03_*` | Core/Geonames | 4 |
| `0200_01_05_*` | Core/Address | 2 |
| `0200_01_07_*` | Core/Company | 8 |
| `0200_01_09_*` | Core/Employee | 2 |
| `0200_01_20_*` | Core/User | 5 |
| `0200_02_01_*` | Core/AI | 18 |

**Read the prefix order for foreign-key sequencing, not for port order.** Two
places where it misleads:

- Base/Tenancy is numerically *last* in Base (`0100_01_25`), after Authz,
  Settings, Workflow, and Audit — because tenancy was retrofitted. Its real
  dependency position is first: `companies.tenant_id` and `addresses.tenant_id`
  are non-null FKs to `tenants`.
- `app/Base/Audit/.../0100_01_17_000002_add_tenant_id_to_base_audit_tables.php`
  adds `tenant_id` *before* `tenants` exists. This is legal only because the
  column has **no foreign key** — audit rows deliberately outlive their
  referents. Do not "fix" this by adding an FK in Bilimbi.

Bilimbi already resolves this correctly by ordering on the descriptor graph
rather than on filenames, and by collapsing each module's history into one
compatibility baseline migration. **Port each table's end state, not
Belimbing's migration steps.** The steps matter only for deriving FK order and
for understanding the backfill semantics that `mix bilimbi.schema.adopt` must
tolerate on a live database.

## 3. Capability inventory

`State` is against Bilimbi at `54b50b0` plus the uncommitted worktree.

### 3.1 Required Platform Baseline — Core identity

| Capability | Stable ID candidate | Tables | Schema deps | State |
|---|---|---|---|---|
| Tenancy | `base/tenancy` | `tenants` | none | **Complete** |
| Geonames | `core/geonames` | `geonames_countries`, `geonames_admin1`, `geonames_postcodes`, `geonames_cities` | none | Schema complete; import in flight (BLB-S1-001) |
| Address | `core/address` | `addresses`, `addressables` | `tenants`, `geonames_countries`, `geonames_admin1` | **Complete** |
| Company | `core/company` | `companies`, `company_relationship_types`, `company_relationships`, `company_external_accesses`, `company_legal_entity_types`, `company_department_types`, `company_departments`, `tenant_primary_companies` | `tenants` | **Complete**; department seams in flight (BLB-S1-004) |
| Employee | `core/employee` | `employees`, `employee_types` | `companies`, `company_departments` | In flight (BLB-S1-003); layer confirmed Core — [BLB-S1-005](../tasks/BLB-S1-005.md) |
| User | `core/user` | `users`, `password_reset_tokens`, `user_pins`, `user_database_queries`, `notifications` | `companies`, `employees` | **Absent — the one real S1 gap** |

All 8 Company tables, all 4 Geonames tables, both Address tables, and `tenants`
are created by Bilimbi migrations today. Core User has no counterpart at all:
there is no `apps/core/user/`.

### 3.2 Required Platform Baseline — Base mechanisms

| Capability | Stable ID candidate | Tables | Purpose | State |
|---|---|---|---|---|
| Database/Repo | `base/database` | — | One shared Repo, sandbox case | **Complete** |
| Module discovery | `base/module_registry` | — | Descriptor graph; replaces Belimbing's `base_database_migration_sources` + `app/Base/Foundation/ModuleManifest` | **Complete** |
| Compatibility | `core/compatibility` | — | Verify/adopt, migration ledger | **Complete** |
| Migration + seeder ledger | `base/database` | `base_database_tables`, `base_database_seeders`, `base_database_migration_sources` | Registry + observable seeder status | Partial — migration ledger exists as `bilimbi_schema_migrations`; **no seeder ledger** |
| Settings | `base/settings` | `base_settings` | Scoped runtime parameters | Absent |
| Authz | `base/authz` | `base_authz_roles`, `base_authz_role_capabilities`, `base_authz_principal_roles`, `base_authz_principal_capabilities`, `base_authz_decision_logs` | Capability decisions | Absent |
| Audit | `base/audit` | `base_audit_mutations`, `base_audit_actions` | Mutation/action trail | Absent |

### 3.3 Operational services — admit only on proof of need (S3)

Belimbing has 16 Base modules with **no durable tables**: AI, Cache, Dashboard,
DateTime, Livewire, Locale, Log, Menu, Pdf, Perf, Queue, Routing, Session,
Software, Support, System. Four carry tables but are not identity:
Media (`base_media_assets`), Integration (2), Schedule (2), Workflow (11).

Three are already obsolete in Bilimbi and should be ported as **nothing**:

- `app/Base/Livewire/ComponentDiscoveryService.php` and
  `app/Base/Routing/RouteDiscoveryService.php` solve Laravel autoloading
  problems Phoenix does not have.
- `app/Base/Foundation/ApplicationTopology.php`,
  `ModuleManifest/`, and `base_foundation_bundle_catalog_cache` are Belimbing's
  module-discovery machinery, already superseded by `base/module_registry`.
  Note `app/Base/Foundation/Compatibility/LegacyApplicationClassMap.php` — the
  four-root topology is itself a recent Belimbing migration
  (`2026_08_05_000000_normalize_four_root_application_topology.php`).

Base/Database is the trap in this group: 255 PHP files, of which
`Services/` alone is 106. Only the ledger tables belong to the baseline. The
`base_database_data_share_*` (5 tables) and `base_database_data_operation_*` /
`data_freshness` (4 tables) subsystems are a substantial separate capability
that no baseline table references. **Do not port `Base/Database` as one unit.**

### 3.4 Explicitly out of Platform Baseline

- **Core/AI** — 18 tables, 397 PHP files, prefix `0200_02_01_*`. Every table
  keys off `employees`, `users`, or `companies`. This is S4 and must not start
  before identity is trustworthy.
- **Domains** — `app/Domains/{Commerce,Operation,People}/*` (Catalog, Inventory,
  Marketplace, Sales, IT, Quality, Attendance, Claim, Leave, Payroll,
  Settings). S5.
- **Extensions** — `app/Extensions/{Ham,Kiat,SbGroup}/*`. S6.
- **Laravel framework tables** — `cache`, `jobs`, `sessions` in
  `database/migrations`. `config/session.php:19` and `config/queue.php:16` both
  default to the `database` driver. These are Laravel runtime mechanics with no
  Phoenix equivalent; see §7.4.

## 4. Foreign keys: the real dependency graph

Extracted from every `constrained()`, `->foreign()`, and `->references()` call
in Base and Core migrations.

```text
tenants ──< companies.tenant_id            (non-null, RESTRICT)
        ──< addresses.tenant_id            (non-null, named addresses_tenant_foreign)
        ──< tenant_primary_companies.tenant_id   (PK + FK)

geonames_countries ──< geonames_postcodes.country_iso
                   ──< geonames_cities.country_iso
                   ──< addresses.country_iso
geonames_admin1    ──< addresses.admin1Code

companies ──< company_relationships.{company_id, related_company_id}
          ──< company_external_accesses.company_id
          ──< company_departments.company_id
          ──< tenant_primary_companies.company_id  (composite → companies(id, tenant_id))
          ──< employees.company_id
          ──< users.company_id                     (nullable)
          ──< base_authz_roles.company_id          ← added by a CORE migration
          ──< ai_*.company_id

employees ──< employees.supervisor_id              (self, nullOnDelete)
          ──< company_departments.head_id          ← added by an EMPLOYEE migration
          ──< users.employee_id                    (nullable)
          ──< ai_*.employee_id

users     ──< company_external_accesses.user_id    ← added by a USER migration
          ──< user_pins.user_id
          ──< user_database_queries.user_id
          ──< ai_*.{acting_for_user_id, created_by, requested_by}
```

### 4.1 Cross-module FKs are added by the *depending* module

Three FKs cross a module boundary, and in every case Belimbing puts the
`ALTER TABLE` in the migration of the module that *needs* the reference, not
the module that owns the table:

| FK | Table owner | Migration owner |
|---|---|---|
| `company_departments.head_id → employees` | Core/Company | Core/Employee (`0200_01_09_000001`) |
| `company_external_accesses.user_id → users` | Core/Company | Core/User (`0200_01_20_000002`) |
| `base_authz_roles.company_id → companies` | Base/Authz | Core/Company (`0200_01_07_001007`) |

This convention is load-bearing, and Bilimbi already has a mechanism for it
that a porting agent must use rather than reinvent.

**The optional-group contract.** A table's owner declares the incoming
contribution as optional, and the contributing module supplies it. The Company
contract does this twice:

- `company_departments` declares `optional_foreign_keys`
  `company_departments_head_id_foreign` (`head_id → employees`,
  `:nilify_all`), which the in-flight Employee baseline creates
  (`apps/core/employee/priv/repo/migrations/20260812112641_create_core_employee_compatibility_baseline.exs:57`);
- `company_external_accesses` declares `optional_columns` `user_id`,
  `optional_indexes` `company_external_accesses_user_id_is_active_index`,
  `optional_foreign_keys` `company_external_accesses_user_id_foreign`
  (`user_id → users`, `:nilify_all`), and binds all three into one
  `optional_groups` entry named `core/user external-access owner`. That is an
  exact match for Belimbing `0200_01_20_000002` — nullable `user_id`,
  `constrained('users')`, `nullOnDelete()`, `index(['user_id', 'is_active'])`.

`SchemaVerifier.compare_optional_groups/4` reports
`incomplete optional contribution` only when a group is *partly* present, so a
contributing module must add every member of its group in one migration, and a
contract stays green whether or not the contributor is installed.

The consequence for planning is concrete: **Core User needs no Company-side
edit and no follow-on task.** Its own migration adds the column, index, and FK
together. Base/Authz gets the same treatment — Base creates `base_authz_roles`
with a bare `company_id` and declares the FK plus the
`base_authz_roles_custom_company_check` constraint as an optional group, and
Core/Company contributes it. That is what lets Base/Authz be ported without
Base depending on Core.

### 4.2 Deliberately absent foreign keys

`base_audit_mutations` / `base_audit_actions` carry `company_id`, `tenant_id`,
and a polymorphic `actor_type`/`actor_id` pair with **no FKs at all**
(`app/Base/Audit/Database/Migrations/Concerns/DefinesAuditActorColumns.php`).
`base_settings.scope_type`/`scope_id` is likewise unconstrained. Preserve this.

### 4.3 Soft deletes are the exception, not the rule

Only five baseline tables have `deleted_at`: `tenants`, `companies`,
`company_relationships`, `company_external_accesses`, `addresses`.
`employees`, `users`, `employee_types`, and every Geonames table are **hard
delete**. `AGENTS.md` §5 already requires soft delete to be an explicit query
policy; the inventory point is that the policy applies to five tables, and
assuming otherwise would invent behavior.

## 5. Runtime dependencies ≠ schema dependencies

This is the most important finding for task splitting, and it is invisible in
the migrations.

`app/Core/User/Models/User.php` imports, at runtime:

```php
App\Base\Authz\Enums\PrincipalType;      App\Base\Authz\Models\PrincipalRole;
App\Base\Settings\Contracts\SettingsService;  App\Base\Settings\DTO\Scope;
App\Base\Foundation\Contracts\CompanyScoped;
App\Core\AI\Models\AiProviderModel;
App\Core\Company\Models\Company;   App\Core\Company\Models\ExternalAccess;
App\Core\Employee\Models\Employee;
```

So `users` needs only `companies` and `employees` **as schema**, but the
Belimbing User *behavior* needs Authz, Settings, and even Core/AI. Splitting on
that seam is what makes a Core User task possible inside S1 — see §7.1.

### 5.1 Eloquent's bidirectional references cannot be copied

Belimbing models reference each other freely in both directions:
Company ↔ User, Employee ↔ User, Address → Company/Employee, Department →
Employee. Bilimbi's descriptor graph rejects dependency cycles
(`AGENTS.md` §6). Every one of these pairs needs a declared seam.

Bilimbi has already solved this once and the solution should be treated as the
house pattern: `apps/core/company/lib/company.ex:71` exposes

```elixir
def addressable_identity, do: "App\\Core\\Company\\Models\\Company"
```

The **owned** module publishes its durable polymorphic identity string as
public API, and the *referencing* module stores it. Address never depends on
Company. Note the persisted value is a literal PHP class name — a durable
compatibility payload, exactly as `AGENTS.md` §5 warns. It is data, not an
Elixir module reference, and renaming the Elixir module must not change it.

The same treatment is needed for:

- `addressables.addressable_type` for Employee;
- `base_authz_principal_roles.principal_type` — `'user'` | `'agent'`
  (`docs/architecture/authorization.md:25-26`), where `'agent'` is an
  **Employee**, not a User;
- `notifications.notifiable_type`;
- `base_audit_*.actor_type`.

### 5.2 Configuration discovery is a real Belimbing mechanism

Modules contribute behavior by dropping config files that are auto-discovered:
22 × `Config/menu.php`, 22 × `Config/authz.php`, 12 × `Config/settings.php`,
plus `dashboard.php`, `audit.php`, and others. `authorization.md:293` states
capabilities are registered purely by creating `Config/authz.php` — "No service
provider changes needed."

Bilimbi's descriptor (`bilimbi.module.exs`) currently declares only id, layer,
otp_app, namespace, dependencies, migrations, and schema_contract. Whether
menu/capability/settings contribution becomes descriptor keys, behaviours, or
something else is an architecture decision that Authz, Settings, and Menu all
depend on. It should be decided **once**, before the first of them is built —
see §8.3.

## 6. Bootstrap and reference data

Belimbing separates structural migration from data, exactly as the S1 exit gate
requires. `base_database_seeders`
(`app/Base/Database/Database/Migrations/0001_01_01_000001_*`) is an observable
ledger: `seeder_class` unique, `module_name`, `migration_file`, `status`
(pending/running/completed/failed/skipped), `ran_at`, `error_message`.
Migrations self-register via the `RegistersSeeders` trait — see
`0200_01_09_000002_create_employee_types_table.php:38`.

Required (non-dev) reference data in the baseline:

| Seeder | Table | Notes |
|---|---|---|
| `CountrySeeder`, `Admin1Seeder`, `CitySeeder`, `PostcodeSeeder` | `geonames_*` | Downloads from geonames.org — `Seeders/Concerns/DownloadsGeonamesFile.php` |
| `LegalEntityTypeSeeder`, `RelationshipTypeSeeder`, `DepartmentTypeSeeder` | Company reference tables | Static |
| `EmployeeTypeSeeder` | `employee_types` | `is_system` rows are protected; licensees add custom |
| `AuthzRoleSeeder`, `AuthzRoleCapabilitySeeder` | `base_authz_roles`, `base_authz_role_capabilities` | System roles are company-less |

`Dev/`-prefixed seeders are demo data guarded by
`DevSeederProductionEnvironmentException`. They are **not** baseline.

**Gap:** Bilimbi has the Geonames import in flight (`mix bilimbi.geonames.*`)
and a `bilimbi.employee.types.bootstrap` task in the relocated Employee module,
but **no shared seeder ledger**. Belimbing's observable status/error/ran_at
contract has no Bilimbi counterpart. Three modules now need idempotent
reference data; a per-module Mix task each, with no shared record of what ran
or what failed, will not satisfy "idempotent, observable operational path."
This is a Base Database capability worth one small task before a third module
invents a fourth pattern.

## 7. Recommended port order

### 7.1 Finish S1 — Core User is the only real gap

1. **Geonames import** (BLB-S1-001, in flight).
2. **Employee** (BLB-S1-003, in flight) — Core, required, per §8.1.
3. **Seeder ledger** (§6) — small, unblocks the reference-data gate.
4. **Core User, identity only.** Port `users`, `password_reset_tokens`,
   `user_pins`, `user_database_queries`, `notifications`, plus the
   `company_external_accesses.user_id` FK per §4.1. Public API covers
   creation, company/employee affiliation, and lookup.
   **Explicitly defer** authentication, sessions, password reset flow,
   authorization, preferences, and the `Core/AI` model-hint code in
   `User::getLastUsedModel()` to S2/S4. This split is what §5 makes possible
   and it is the only way User fits inside S1 without dragging Authz and
   Settings in with it.

`notifications` deserves its own note: UUID primary key, not bigint
(`0200_01_20_000005:23`), because Laravel's `NotificationSender` assigns
`Str::orderedUuid()` client-side. Mapping it as `:id` breaks every insert.

### 7.2 S2 — access and governance, in this order

1. **Base Settings** first. `base_settings` has **zero foreign keys**, so it is
   portable in isolation, and both Authz and User preferences read it
   (`0200_01_20_000007_migrate_user_preferences_to_settings.php`). Scope
   cascade is user → company → tenant → global
   (`docs/architecture/tenancy.md`, Settings section).
2. **Base Authz.** Tables carry a bare `company_id`; Core/Company adds the FK
   and the `base_authz_roles_custom_company_check` constraint (§4.1).
   Principals are polymorphic over `'user'` and `'agent'`, where `'agent'` is an
   Employee — so Authz cannot be completed before Employee's layer is decided.
3. **Base Audit.** No FKs, polymorphic actor; portable once actors exist.
4. **Session / authentication**, then the deferred half of Core User.

### 7.3 S3 and later

Admit operational services only on proof of need, per the stage gate. Port
nothing from Livewire, Routing, or Foundation's module machinery (§3.3). Split
`Base/Database`'s data-share and data-operation subsystems out as their own
capability; they are not baseline. Base/Workflow (11 tables) has no baseline
consumer — its consumers are S5 Domains (Quality NCR/SCAR, IT tickets), so it
should travel with the first Domain rather than being pulled forward.

### 7.4 Decide, do not port

`cache`, `jobs`, and `sessions` are Laravel driver tables. Phoenix has no
equivalent need. They matter only for adoption: an existing Belimbing database
*contains* them, so `mix bilimbi.schema.verify` must decide whether unknown
Laravel-owned tables are drift or expected residue. That is a compatibility
contract question, not a port.

## 8. Uncertainties requiring a user or architecture decision

**8.1 Employee's layer — resolved during this analysis, recorded for reuse.**
Between 19:34 and 19:39+08 the worktree briefly contained a `people` Domain
container with Employee relocated as `layer: :domain, required: false`. Raised
as [BLB-S1-005](../tasks/BLB-S1-005.md) and closed by the steward as
resolved-by-reversion: `apps/people/` is gone and
`apps/core/employee/bilimbi.module.exs` again declares
`id: "core/employee", layer: :core, required: true`.

The argument is kept because it constrains any future attempt. `users.employee_id`
is a real FK to `employees`
(`app/Core/User/Database/Migrations/0200_01_20_000000_create_users_table.php:23-25`).
Employee at `:domain` would make Core/User depend on a Domain, which
`AGENTS.md` §4 forbids; `required: false` would additionally let a required
Core table carry an FK into an absent module's table. Employee is Core because
the canonical schema makes it Core, not by convention.

**8.2 How much of Core User belongs to S1.** §7.1 recommends the identity/schema
half. If the team wants a login-capable application at the S1 gate instead, S1
absorbs Base Settings, Base Authz, and Session, and the gate moves. This is a
scope decision, not a technical one.

**8.3 The module contribution contract.** Menu, capability, and settings
declaration (§5.2) is one mechanism serving at least three future modules. It
needs one ADR before Authz or Settings starts, or each will invent its own.

**8.4 Where tests live.** Belimbing centralizes all 362 test files in `tests/`
(`tests/Feature/`, `tests/Unit/`), organized by capability. Bilimbi requires
tests inside the owning module directory (`AGENTS.md` §6). Ported tests must be
redistributed, and `tests/Support/` + `TestingBaselineSeeder.php` have no
obvious single owner. Candidate: Base Database, which already owns the shared
sandbox case.

**8.5 A documentation discrepancy worth not trusting.**
`docs/architecture/user-employee-company.md:70` states Employee has a
`user_id` column. It does not — the FK runs the other way, as
`users.employee_id`
(`0200_01_20_000000_create_users_table.php:23-25`), and the same doc later
calls it a "Future Enhancement" (line 329). Where Belimbing's docs and
migrations disagree, the migrations are canonical. Any Employee↔User contract
built from that doc paragraph would be built on a column that does not exist.

**8.6 Seeder identity across the port.** `base_database_seeders.seeder_class`
stores PHP FQCNs, and rows in an adopted database will name classes like
`App\Core\Employee\Database\Seeders\EmployeeTypeSeeder`. Some already-stored
values are stale — `0200_01_09_000002_create_employee_types_table.php:2`
imports the pre-topology `App\Modules\Core\Employee\...` namespace. If Bilimbi
adopts this ledger, it inherits strings that name classes that no longer exist
under any topology. Whether Bilimbi reuses the table or starts a parallel one
is a compatibility decision.

## 9. Suggested non-overlapping task split

Each claims one module directory. None overlaps another's write paths.

| Task | Role | Claim | Depends on |
|---|---|---|---|
| Seeder ledger contract | Module implementer | `apps/base/database/**` | — |
| Module contribution contract | Compatibility architect | ADR (integration-owned) | — |
| Core User contract | Compatibility architect | research/ADR | BLB-S1-003 handoff |
| Core User implementation | Module implementer | `apps/core/user/**` | Core User contract |
| `company_external_accesses.user_id` FK | Module implementer | `apps/core/company/**` | Core User; conflicts with BLB-S1-004 — serialize |
| Base Settings | Module implementer | `apps/base/settings/**` | Contribution contract |
| Base Authz | Module implementer | `apps/base/authz/**` | Settings, BLB-S1-003 handoff |

The Core User implementation and the Company FK task touch different modules
but land in one schema change; the integration steward should sequence them, or
merge them into one task that claims both.
