# Migrating from Belimbing

Bilimbi began as the Phoenix and Elixir implementation of the Belimbing
application platform ([BelimbingApp/belimbing](https://github.com/BelimbingApp/belimbing)).
It preserves Belimbing's business model, product principles, and PostgreSQL
schema, so an existing Belimbing installation can move to Bilimbi on the same
database. This page records that compatibility contract and the cutover steps.
The normative rules live in
[Database Architecture](./architecture/database.md) and
[ADR 0002](./architecture/decisions/0002-compatible-schema-baselines.md).

## What compatibility means

Compatibility means that Bilimbi can use the same PostgreSQL database and
preserve the same logical records. It does not mean copying Laravel classes or
reproducing Laravel internals.

The intended operating model is one active application runtime at a time. The
compatibility goal is a seamless schema and data-model transition, not
concurrent Laravel/Phoenix access or dual writes.

Compatibility is a one-direction replacement contract. Bilimbi adopts an
existing Belimbing database and replaces the Belimbing application; Belimbing
is not required to consume a database after Bilimbi-only evolution.

The compatibility work includes:

- exact table and column names;
- primary keys, foreign keys, sequences, indexes, and constraints;
- JSON and timestamp representations;
- soft-delete behaviour and status values;
- tenant, company, user, and employee relationships;
- polymorphic records and stable persisted identities;
- migration and seed data safety.

Ecto schemas and queries are written against the compatibility contract. Do
not invent a cleaner parallel schema without an explicit migration decision.

Belimbing was the reference while the port was underway, but it is not
perfect. When inconsistencies, mistakes, or entropy were discovered during
development, they were not built into Bilimbi. The defect is corrected cleanly
in Bilimbi and an issue is raised in Belimbing so that both projects benefit.

## Adopting an existing database

Configure the connection to the Belimbing database (see
[the development guide](./development.md)), then adopt it instead of running
fresh creation migrations:

```bash
mix bilimbi.schema.verify
mix bilimbi.schema.adopt
mix bilimbi.cutover.remap --dry-run
mix bilimbi.cutover.remap
mix bilimbi.server
```

Adoption refuses schema drift and records the verified baselines in
`bilimbi_schema_migrations`. Laravel's `migrations` table is never changed.

The schemas already match, so the remaining cutover work is stored values
Bilimbi reads differently. `mix bilimbi.cutover.remap` remaps pin and
notification URLs (always recomputing the pin hash) and `heroicon-` names, and
reports what it must not fix by itself: grants naming capabilities Bilimbi does
not declare, and pins with no Bilimbi equivalent. It deletes nothing and is
idempotent, so `--dry-run` first and read its residue before opening traffic.
See [Database Architecture](./architecture/database.md) for the full
sequence and `mix help bilimbi.cutover.remap` for the options.

After an unprovisioned adoption, establish explicit operator identity with
`mix bilimbi.platform.provision` as described in
[the development guide](./development.md#provisioning-identity).

## The contract by module

The current contract uses `tenants.is_platform_operator` for the installation
operator and `tenant_primary_companies` for each tenant's designated company.
`companies.tenant_id` is always explicit and has no database default. ID 1 is
only historical migration input in Belimbing, never a Bilimbi runtime role.

Bilimbi-owned migrations live inside their owning module, in its
`priv/repo/migrations`; `mix bilimbi.migrations` lists them. The Compatibility coordinator obtains
these paths from installed module descriptors; it contains no per-module path
list. Each migration module uses its owning public namespace. Structural and
live-data invariants are likewise implemented by the contributing module's
schema contract and invoked generically by Compatibility. Fresh installations
use `mix bilimbi.migrate`; existing databases use the explicit verify-and-adopt
workflow described in
[ADR 0002](./architecture/decisions/0002-compatible-schema-baselines.md).

Core Geonames preserves Belimbing's country, administrative-division,
postcode, and city tables behind read models and lookup APIs. Fresh schemas
contain no reference rows until a separately owned import or seeding step runs.
Core Address preserves Belimbing's camel-cased legacy columns and polymorphic
Company identity behind a snake-cased Elixir API. Every Address operation takes
an explicit tenant scope, and its Geonames normalization foreign keys are part
of the required verified contract.

Core Employee preserves Belimbing's employee and employee-type tables and
completes the Company department-head foreign key. Core User preserves the
user, password-reset, pin, saved-query, and notification tables and completes
Company's external-access user contribution. Both modules own their baselines,
contracts, and tenant/company-scoped APIs while Compatibility only coordinates
their descriptor-declared contributions.

Core User also owns the credential lifecycle behind those compatible tables:
Argon2id account creation, Laravel Argon2 and legacy `$2y$` bcrypt login,
transparent bcrypt upgrade, neutral password-reset requests, signed email
verification, and the four canonical user-scoped settings. This is a Core API,
not a public signup surface; Phoenix Web still owns routes, rate limiting,
delivery, cookies, and the authenticated session adapter.

Base Session preserves Belimbing's root `sessions` table as an opaque durable
store with no dependency on Core User or Web. Its operational listing omits
payloads, termination protects the caller's current session, and unreadable
Laravel payloads remain a future authentication-adapter concern.

Base Authz keeps capability definitions in immutable module contributions and
assignments in the five compatible `base_authz_*` tables. Unknown capability
keys fail closed. System-role reconciliation is an explicit production-seed
operation and never deletes principal grants. Core Company owns the later
restricted company foreign key and exact system/custom-role ownership check,
so Base does not depend upward on Core.

Base Audit preserves Belimbing's `base_audit_mutations` and
`base_audit_actions` tables: jsonb payloads, `inet` `ip_address`, nullable
`tenant_id`, no foreign keys, and `occurred_at` as the only timestamp.

The stage-by-stage history of the port is in
[Porting stages](./PORTING_STAGES.md).
