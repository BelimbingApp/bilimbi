# ADR 0002: Compatible schema baselines and adoption

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** codex/sol-high
**Scope:** Bilimbi migration ownership, Belimbing schema compatibility,
installation, adoption, and explicit tenant/company identity
**Last Updated:** 2026-08-12

## Context

Bilimbi must do more than map Ecto schemas onto tables created by Laravel. It
must create a fresh PostgreSQL schema compatible with Belimbing and must adopt
an existing Belimbing database without replaying creation DDL or treating
Laravel migration history as Bilimbi migration history.

The compatibility reference is Belimbing merge commit
`e70b4d33c0b10790e681f4c2b5095d85a53bc918` from PR #245. That change replaced
runtime ID-1 meaning with explicit tenancy. Its upgrade files run in this global
order:

1. `0100_01_13_000005_rename_platform_operator_locale_source`;
2. `0100_01_25_000001_mark_platform_operator_tenant`;
3. `0200_01_05_000002_add_tenant_to_addresses`;
4. `0200_01_07_001004_enforce_company_tenant_integrity`;
5. `0200_01_07_001005_create_tenant_primary_companies_table`;
6. `0200_01_07_001006_backfill_tenant_primary_companies`;
7. `0200_01_07_001007_scope_custom_authz_roles`.

Those files are historical upgrade steps for Laravel installations. Bilimbi's
first Ecto migrations are unreleased current-state baselines, so they create
the resulting schema directly rather than reproducing transitional defaults,
ID-based backfills, or Laravel's migration ledger.

The resulting cross-module contract is:

- `tenants.is_platform_operator` is a non-null PostgreSQL boolean defaulting to
  false. The partial unique index `tenants_one_platform_operator` permits at
  most one marked operator.
- `companies.tenant_id` is non-null, has no default, is indexed, and references
  `tenants.id` through `companies_tenant_foreign` with restricted deletion.
- `companies_id_tenant_unique` covers `(id, tenant_id)`, and
  `companies_parent_tenant_foreign` constrains `(parent_id, tenant_id)` to a
  parent in the same tenant.
- `tenant_primary_companies` has no timestamps. Its tenant is both the primary
  key and a restricted foreign key. Its company is unique, and its composite
  foreign key requires company and tenant ownership to match.
- Address tenancy and Authz role ownership have their own exact constraints,
  described below, but remain owned by their modules when those modules are
  ported.

## Decision

### Bilimbi migration history

Bilimbi owns Ecto migrations and records them in
`bilimbi_schema_migrations`. It never reads from, writes to, renames, or
repurposes Laravel's `migrations` table.

Migration files remain with their owning deep module:

```text
apps/base/tenancy/priv/repo/migrations/
apps/core/company/priv/repo/migrations/
apps/core/address/priv/repo/migrations/
```

These are the current contributing paths, not a hard-coded coordinator list.
The Compatibility coordinator discovers every installed module descriptor
whose `migrations` field is non-null and composes those paths through the shared
Repo and ledger. It uses globally unique Ecto versions with strict deterministic
ordering: declared dependencies first, then Base → Core → Domain → Extension
and stable module ID as tie-breakers. The current declarations make Base
Tenancy run before Core Company, which runs before Core Address. Ownership is
expressed by the module descriptor and path; version numbers provide global
execution order rather than permanent numeric ranges for layers.

### Current-state compatibility baselines

The first Bilimbi migrations create the canonical end state:

1. Base creates `tenants`, including the explicit operator marker and partial
   unique index. It inserts no tenant.
2. Core creates the complete current Company schema, including explicit tenant
   ownership, tenant-safe parentage, and `tenant_primary_companies`.
3. Core creates the current Address schema, including explicit tenant
   ownership and compatible polymorphic attachments.

The Core Company baseline owns:

- `companies`;
- `tenant_primary_companies`;
- `company_relationship_types`;
- `company_relationships`;
- `company_external_accesses`;
- `company_legal_entity_types`;
- `company_department_types`;
- `company_departments`.

The Core Address baseline owns `addresses` and `addressables`. It preserves
Belimbing's existing camel-cased PostgreSQL columns through explicit Ecto
`source:` mappings. The Geonames normalization foreign keys are an optional
all-or-nothing contribution until the Geonames tables are ported; adoption
requires both exact keys when either is present.

The historical locale-source rename and data backfills are not replayed on an
empty schema. They remain provenance for adopting upgraded Belimbing data.

User may later add the external-access `user_id` contribution and Employee may
later add the department-head foreign key. The Company verifier treats each as
an optional all-or-nothing contribution until its owning Bilimbi module exists.
It does not fabricate a dependency on absent `users` or `employees` tables.

Authz remains deferred to its owner without weakening its canonical contract:

- `base_authz_roles.company_id` is null only for system roles. The restricted
  `base_authz_roles_company_foreign` and exact check
  `base_authz_roles_custom_company_check` enforce
  `is_system = (company_id IS NULL)`.
- Role APIs must exclude custom roles whose owning company is soft-deleted.
- A future AI `ConfigResolver.resolve_for_provider` equivalent must require the
  owning company ID; tenant identity alone cannot select company credentials.

Reference-data seeders are separate ownership work. Creating compatible tables
does not claim every Belimbing seeder has been ported.

### Fresh installation

`mix bilimbi.migrate` runs all installed descriptor-contributed paths together.
`mix setup` includes this command. A fresh migration:

- creates `bilimbi_schema_migrations` and never creates Laravel's ledger;
- creates the complete in-scope schema at the pinned current state;
- creates no identity-bearing tenant or company row;
- requires explicit platform-operator and primary-company provisioning.

Ordinary `create` operations deliberately fail if target tables already exist.
Broad `create_if_not_exists` behavior would conceal whether a database is
fresh, already adopted, or drifting.

### Existing Belimbing database adoption

An existing database uses an explicit two-step contract:

1. `mix bilimbi.schema.verify` compares its current PostgreSQL structure and
   identity invariants with the pinned contract.
2. `mix bilimbi.schema.adopt` repeats verification and, only after success,
   records the Bilimbi baseline versions without executing their DDL.

Verification checks owned columns, types, nullability, defaults, named indexes
including the partial predicate, single and composite foreign keys, and
important live-data invariants. Unexpected owned structure is drift. A partial
or foreign Bilimbi ledger is an error.

Each installed module's descriptor identifies its schema contract. That
contract owns both its structural table specifications and its live-data
invariant callback: Tenancy verifies platform-operator identity, and Company
verifies primary-company assignments. Core Compatibility only discovers,
orders, and aggregates those contracts; it contains no Tenancy-, Company-, or
Address-specific SQL.

An empty explicit identity is valid before provisioning. A marked but
soft-deleted operator, multiple marked operators, or a missing, cross-tenant,
or soft-deleted assigned primary company is an invariant failure. Adoption
never modifies Laravel's ledger or business data.

### Platform operator and primary company

The platform operator is distinct from every customer tenant and its primary
company:

- Base resolves the platform operator from `tenants.is_platform_operator`.
- Every provisioned tenant has its own explicit primary company through
  `tenant_primary_companies`.
- Core owns primary-company resolution, assignment, transfer, and tenant-plus-
  company provisioning because Base must not depend on a Core table.
- Missing assignment means not yet provisioned. Invalid or soft-deleted
  assigned records are invariant failures, not permission to guess.
- The oldest company is never an identity fallback.

Elixir APIs use the same concepts with Elixir naming conventions:

- `Bilimbi.Base.Tenancy.platform_operator/0`;
- `Bilimbi.Base.Tenancy.require_platform_operator!/0`;
- `Bilimbi.Base.Tenancy.platform_operator?/1`;
- `Bilimbi.Core.Company.PrimaryCompanyManager` for primary-company behavior.

`companies.tenant_id` has no default. Every creation path must supply or derive
the tenant from an explicit, validated context. This is safe for SaaS and
prevents accidental writes into the operator tenant.

Numeric ID 1 has no durable runtime meaning. It appears only as bounded input
inside Belimbing's historical upgrade migrations. Preserving retained numeric
IDs during adoption is a data-compatibility requirement; interpreting those
numbers as roles is not.

## Consequences

- Bilimbi can create a fresh, explicit-tenancy Company foundation without
  Laravel.
- Existing Belimbing databases require deliberate, drift-sensitive adoption.
- Base Database owns the shared Repo, each module owns its compatibility
  contract and migrations, and Core Compatibility discovers and coordinates
  all installed contributions into the current Platform Baseline.
- Authz, User, Employee, Geonames, and AI compatibility obligations remain
  explicit and will be activated with their owning slices.
- The pinned source commit must change deliberately whenever the compatible
  Belimbing schema changes.
- Business code accepts explicit tenant or company identity and never infers a
  role from row age or a numeric primary key.
