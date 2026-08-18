# Bilimbi

Bilimbi is the Phoenix and Elixir implementation of the Belimbing application
platform. It is designed to preserve Belimbing's business model, product
principles, and PostgreSQL schema while using the BEAM runtime and Phoenix
conventions.

The project is MIT licensed. See [LICENSE](./LICENSE).

## What Bilimbi is

Bilimbi provides a durable foundation for building business applications:

- Base infrastructure for database access, authentication, authorization,
  tenancy, settings, auditability, and shared platform behaviour.
- Core business modules for users, companies, employees, addresses, and other
  required enterprise primitives.
- A Phoenix web interface using LiveView, HEEx, Tailwind CSS, and verified
  routes.
- Bilimbi-owned Ecto baselines compatible with Belimbing's existing PostgreSQL
  tables, constraints, and data conventions.

Bilimbi is a general business-application platform, not a fixed business
suite. An ERP is one intended kind of application that can be composed from its
Platform Baseline, business Domains, and deployment-owned Extensions.

Bilimbi is being built from the beginning by coding agents. The repository's
`AGENTS.md` and `DESIGN.md` are part of the engineering system: they describe
how the application should be extended and how it should feel to use.

## Current status

Bilimbi is in its foundation phase. The repository uses a Mix umbrella rooted
at the repository. Base, Core, and Web are its top-level composition
applications; each declared deep module below Base or Core is a self-contained
local Mix package discovered from its descriptor. The current foundation owns
Ecto migrations that can create the compatible Base Session, Settings,
Tenancy, Authz, and Audit plus Core Company, Geonames, Address, Employee, and
User schema, or
verify and adopt an existing Belimbing database. Optional Domains and
deployment-owned Extensions are intentionally not implemented yet.

The first major compatibility target is the existing Belimbing PostgreSQL
schema. Bilimbi should map that schema accurately instead of creating a second,
similar data model. Belimbing remains the reference for table names, durable
identities, existing data, and business meaning while the port is underway.

## Development setup

The repository pins the local Erlang and Elixir toolchain in `.mise.toml`.
Install those versions with mise, then run:

```bash
mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000).

`mix setup` creates the database, runs the Base and Core compatibility
migrations, and builds the web assets. The baseline creates no tenant or
company rows; platform-operator and primary-company provisioning are explicit
setup steps and numeric IDs carry no runtime meaning.

To use an existing Belimbing database, configure its connection and adopt it
instead of running fresh creation migrations:

```bash
mix bilimbi.schema.verify
mix bilimbi.schema.adopt
mix phx.server
```

Adoption refuses schema drift and records the verified baselines in
`bilimbi_schema_migrations`. Laravel's `migrations` table is never changed.

After a fresh migration or an unprovisioned adoption, establish explicit
operator identity with:

```bash
mix bilimbi.platform.provision \
  --tenant-name "Platform operator" \
  --company-name "Example Operations" \
  --company-code "example_operations"
```

The operation is idempotent: rerunning it resolves the existing marked tenant
and primary-company assignment rather than relying on a numeric ID.

Provision a customer tenant and its primary company atomically with:

```bash
mix bilimbi.tenant.provision \
  --tenant-name "Acme tenant" \
  --company-name "Acme Sdn. Bhd." \
  --company-code "acme"
```

Useful commands:

```bash
mix format
mix test
mix bilimbi.migrate
mix bilimbi.migrations
mix bilimbi.schema.verify
mix help bilimbi.platform.provision
mix help bilimbi.tenant.provision
mix precommit
```

`mix precommit` is the required final check for a change. It compiles with
warnings as errors, unlocks unused dependencies, formats the project, and runs
the test suite.

## Architecture at a glance

```text
apps/
├── base/                         # Mandatory composition application
│   ├── bilimbi.container.exs     # Declares the Base layer
│   ├── database/                 # base/database module package
│   ├── module_registry/          # Runtime installed-module registry
│   ├── session/                  # Opaque compatible session persistence
│   ├── settings/                 # Immutable definitions and scoped values
│   ├── tenancy/                  # base/tenancy module package
│   ├── authz/                    # Capability, role, grant, and decision engine
│   └── audit/                    # base/audit module package
├── core/                         # Mandatory composition application
│   ├── bilimbi.container.exs     # Declares the Core layer
│   ├── company/                  # core/company module package
│   ├── geonames/                 # Geographic reference-data package
│   ├── address/                  # core/address module package
│   ├── employee/                 # core/employee module package
│   ├── user/                     # core/user module package
│   └── compatibility/            # Shared migration/adoption coordinator
└── web/                          # Phoenix endpoint and shared UI shell
```

The complete physical boundary of Base Tenancy is `apps/base/tenancy/`, not a
directory below its `lib/`. Consequently its source begins at
`apps/base/tenancy/lib/tenancy.ex` while the Elixir namespace remains
`Bilimbi.Base.Tenancy`. The same rule applies to Session, Settings, Authz,
Audit, Company, Geonames, Address, Employee, User, and every future declared
module.

A composition container never lists child packages by name. Every immediate
child directory containing `bilimbi.module.exs` is an installed module; the
shared discovery code validates all installed descriptors and generates the
container's local Mix path dependencies. Mounting `apps/base/mailer/` or a
future `apps/sales/order/` is therefore the source-installation action.
Dependency resolution and compilation must still run afterward.

The discovery helper itself belongs to `apps/base/module_registry/mix/` and is
covered by that package's formatter and tests. Mix writes its validated,
resolved module position and graph fingerprint into OTP application metadata;
a shared compiler refreshes that metadata across all module packages whenever
the installed descriptor set changes. Runtime migration discovery consumes
that approved order instead of maintaining a second graph algorithm. Because
runtime discovery can see only loaded OTP applications, the Compatibility
descriptor declares stable dependencies on every current migration or schema
contract contributor even though its code contains no module-specific paths.

The descriptor is the source of truth for stable module ID, layer, OTP
application ID, namespace, declared module dependencies, and migration
contribution. Discovery rejects malformed or missing descriptors, duplicate
stable or OTP IDs, missing dependencies, cycles, container/layer mismatches,
and upward dependency edges. Modules are ordered dependency-first with stable
module ID as the deterministic tie-breaker.

Future optional Domains are composition applications below `apps/`. For
example, a Sales distribution can compose a self-contained Order module at
`apps/sales/order/`, with namespace `Bilimbi.Sales.Order`. A module
directory may be mounted as a nested Git repository and composed as a local Mix
path dependency without scattering its files through the platform tree. See
[ADR 0003](./docs/architecture/decisions/0003-physical-deep-module-packages.md).

Base and Core are ownership boundaries, not superclass hierarchies. A domain
module exposes a small public API and hides its schemas, queries, and internal
workflow. Web modules call those APIs; business modules do not depend on the
web layer.

Views may be colocated with their LiveView module through `embed_templates` or
HEEx files, while remaining under `BilimbiWeb`. This keeps presentation close
to the workflow without mixing Phoenix concerns into the domain API.

## Compatibility with Belimbing

Compatibility means that Bilimbi can use the same PostgreSQL database and
preserve the same logical records. It does not mean copying Laravel classes or
reproducing Laravel internals.

The intended operating model is one active application runtime at a time. The
compatibility goal is a seamless schema and data-model transition, not
concurrent Laravel/Phoenix access or dual writes.

The compatibility work includes:

- exact table and column names;
- primary keys, foreign keys, sequences, indexes, and constraints;
- JSON and timestamp representations;
- soft-delete behaviour and status values;
- tenant, company, user, and employee relationships;
- polymorphic records and stable persisted identities;
- migration and seed data safety.

Ecto schemas and queries should be written against the compatibility contract.
Do not invent a cleaner parallel schema without an explicit migration decision.

The current contract uses `tenants.is_platform_operator` for the installation
operator and `tenant_primary_companies` for each tenant's designated company.
`companies.tenant_id` is always explicit and has no database default. ID 1 is
only historical migration input in Belimbing, never a Bilimbi runtime role.

Bilimbi-owned migrations live inside their owning module, currently
`apps/base/session/priv/repo/migrations`,
`apps/base/settings/priv/repo/migrations`,
`apps/base/tenancy/priv/repo/migrations`,
`apps/base/authz/priv/repo/migrations`,
`apps/base/audit/priv/repo/migrations`,
`apps/core/company/priv/repo/migrations`,
`apps/core/geonames/priv/repo/migrations`,
`apps/core/address/priv/repo/migrations`,
`apps/core/employee/priv/repo/migrations`, and
`apps/core/user/priv/repo/migrations`. The Compatibility coordinator obtains
these paths from installed module descriptors; it contains no per-module path
list. Each migration module uses its owning public namespace. Structural and
live-data invariants are likewise implemented by the contributing module's
schema contract and invoked generically by Compatibility. Fresh installations use
`mix bilimbi.migrate`; existing databases use the explicit verify-and-adopt
workflow described in
[ADR 0002](./docs/architecture/decisions/0002-compatible-schema-baselines.md).

Core Geonames preserves Belimbing's country, administrative-division,
postcode, and city tables behind read models and lookup APIs. Fresh schemas
contain no reference rows until a separately owned import or seeding step runs.
Core Address preserves Belimbing's camel-cased legacy columns and polymorphic
Company identity behind a snake-cased Elixir API. Every Address operation takes
an explicit tenant, and its Geonames normalization foreign keys are now part of
the required verified contract.

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

### Production mail delivery

Production uses SMTP with mandatory authentication and certificate verification.
Set these environment variables before the release starts:

| Variable | Purpose |
|---|---|
| `MAIL_HOST` | SMTP relay hostname. |
| `MAIL_PORT` | Relay port (`587` for STARTTLS or commonly `465` for implicit TLS). |
| `MAIL_USERNAME` / `MAIL_PASSWORD` | SMTP credentials. |
| `MAIL_TLS_MODE` | `starttls` or `implicit_tls`; unencrypted delivery is not supported. |
| `MAIL_FROM_NAME` / `MAIL_FROM_ADDRESS` | Sender identity used for product email. |

An absent or invalid value stops a production release during configuration, so a
password-reset request cannot be the first time a mail misconfiguration is
discovered. Development uses Swoosh's local mailbox and test uses its test
adapter instead.

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

## Documentation

| Topic | Link |
|---|---|
| Agent and coding rules | [AGENTS.md](./AGENTS.md) |
| Product and interface design | [DESIGN.md](./DESIGN.md) |
| Original Mix umbrella topology | [ADR 0001](./docs/architecture/decisions/0001-mix-umbrella-topology.md) |
| Compatible schema baselines | [ADR 0002](./docs/architecture/decisions/0002-compatible-schema-baselines.md) |
| Physical deep-module packages | [ADR 0003](./docs/architecture/decisions/0003-physical-deep-module-packages.md) |
| Module contribution contract | [ADR 0004](./docs/architecture/decisions/0004-module-contribution-contract.md) |
| Source Belimbing project | [BelimbingApp/belimbing](https://github.com/BelimbingApp/belimbing) |
| Phoenix documentation | [phoenix.hexdocs.pm](https://phoenix.hexdocs.pm/) |
| Elixir documentation | [hexdocs.pm/elixir](https://hexdocs.pm/elixir/) |

## Contributors

See [`CONTRIBUTORS.md`](./CONTRIBUTORS.md) for the team of architects and AI contributors building Bilimbi.

## License

Bilimbi is released under the [MIT License](./LICENSE).
